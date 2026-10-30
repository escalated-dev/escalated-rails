# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'
require 'zlib'
require 'ruby-saml'
require 'jwt'
require 'oauth2'

module Escalated
  module Services
    # Why a sign-in was refused: for the log, never for the user.
    class SsoValidationError < StandardError; end

    # Single sign-on through the provider an admin picks in Admin > Settings >
    # SSO (ADR 2026-10-29-configurable-access-features). Crypto is left to
    # maintained libraries: ruby-saml (SAML 2.0, strict), oauth2 (OAuth 2 /
    # OIDC with PKCE) and jwt.
    #
    # Every validate method returns { email:, name:, role: } or raises
    # SsoValidationError.
    class SsoService
      CONFIG_KEYS = %w[
        sso_provider sso_entity_id sso_url sso_login_url sso_logout_url sso_metadata_url sso_certificate
        sso_attr_email sso_attr_name sso_attr_role sso_jwt_secret sso_jwt_algorithm
        sso_oauth_authorize_url sso_oauth_token_url sso_oauth_userinfo_url sso_oauth_client_id
        sso_oauth_client_secret sso_oauth_scopes
      ].freeze

      SECRET_KEYS = %w[sso_jwt_secret sso_oauth_client_secret].freeze

      DEFAULTS = {
        'sso_provider' => 'none',
        'sso_attr_email' => 'email',
        'sso_attr_name' => 'name',
        'sso_attr_role' => 'role',
        'sso_jwt_algorithm' => 'HS256',
        'sso_oauth_scopes' => 'openid profile email'
      }.freeze

      PROVIDERS = %w[saml oauth jwt].freeze
      JWT_ALGORITHMS = %w[HS256 HS384 HS512 RS256 RS384 RS512].freeze
      # How long an AuthnRequest ID stays answerable, in seconds.
      SAML_REQUEST_TTL = 600
      EMAIL = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

      def get_config
        config = CONFIG_KEYS.index_with do |key|
          value = Escalated::EscalatedSetting.find_by(key: key)&.value
          value.nil? ? DEFAULTS.fetch(key, '') : value.to_s
        end
        # The single URL older versions stored.
        legacy = config['sso_url'].to_s.strip
        if legacy.present?
          config['sso_login_url'] = legacy if config['sso_login_url'].blank?
          if config['sso_provider'] == 'oauth' && config['sso_oauth_authorize_url'].blank?
            config['sso_oauth_authorize_url'] = legacy
          end
        end
        config
      end

      def save_config(data)
        CONFIG_KEYS.each do |key|
          next unless data.key?(key)

          Escalated::EscalatedSetting.find_or_initialize_by(key: key).update!(value: data[key].to_s)
        end
      end

      def provider
        value = Escalated::EscalatedSetting.find_by(key: 'sso_provider')&.value.to_s
        PROVIDERS.include?(value) ? value : 'none'
      end

      def enabled?
        Escalated::Support::AccessFeatures.sso? && provider != 'none'
      end

      def self.options
        (Escalated.configuration.sso || {}).to_h.symbolize_keys
      end

      def self.truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.strip.downcase)
      end

      def self.option(name, env)
        value = options[name]
        value.nil? ? ENV.fetch(env, nil) : value
      end

      def clock_skew
        raw = self.class.option(:clock_skew, 'ESCALATED_SSO_CLOCK_SKEW')
        value = raw.nil? ? 120 : raw.to_i
        value.negative? ? 120 : [value, 300].min
      end

      # ---- Endpoints -------------------------------------------------------

      def sp_entity_id(urls)
        self.class.option(:sp_entity_id, 'ESCALATED_SSO_SP_ENTITY_ID').presence || urls.sso_saml_metadata_url
      end

      # The URLs an admin gives the identity provider. +urls+ is the engine's
      # URL helpers in the request's context.
      def endpoints(urls)
        {
          login: urls.sso_login_url,
          sp_entity_id: sp_entity_id(urls),
          metadata: urls.sso_saml_metadata_url,
          acs: urls.sso_saml_acs_url,
          oauth_redirect: urls.sso_oauth_callback_url,
          jwt_callback: urls.sso_jwt_callback_url
        }
      end

      # ---- SAML ---------------------------------------------------------------

      def saml_settings(urls, config = get_config, require_certificate: true)
        certificate = config['sso_certificate'].to_s.strip
        if require_certificate && certificate.empty?
          raise SsoValidationError, 'SAML refused: no IdP certificate is configured.'
        end

        settings = OneLogin::RubySaml::Settings.new
        settings.sp_entity_id = sp_entity_id(urls)
        settings.assertion_consumer_service_url = urls.sso_saml_acs_url
        settings.assertion_consumer_service_binding = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'
        settings.idp_entity_id = config['sso_entity_id'].to_s.strip
        settings.idp_sso_service_url = config['sso_login_url'].to_s.strip
        settings.idp_cert = certificate unless certificate.empty?
        settings.name_identifier_format = 'urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified'
        settings.soft = false
        # The assertion itself must carry the IdP's signature; a signed
        # Response around an unsigned assertion is refused.
        settings.security[:want_assertions_signed] = true
        settings.security[:strict_audience_validation] = true
        settings.security[:digest_method] = XMLSecurity::Document::SHA256
        settings.security[:signature_method] = XMLSecurity::Document::RSA_SHA256
        settings
      end

      # The IdP sign-in URL for a new AuthnRequest. Its ID is stored
      # server-side (the IdP's cross-site POST back carries no SameSite=Lax
      # session cookie) and must come back as InResponseTo within the TTL.
      def saml_login_url(urls)
        config = get_config
        settings = saml_settings(urls, config)
        if settings.idp_sso_service_url.blank?
          raise SsoValidationError,
                'SAML refused: no IdP sign-in URL is configured.'
        end

        request = OneLogin::RubySaml::Authrequest.new
        url = request.create(settings)
        Escalated::SsoMessageId.remember('saml_request', request.uuid, Time.now.to_i + SAML_REQUEST_TTL)
        url
      end

      def saml_metadata(urls)
        OneLogin::RubySaml::Metadata.new.generate(saml_settings(urls, get_config, require_certificate: false), true)
      end

      def validate_saml_response(urls, saml_response)
        config = get_config
        settings = saml_settings(urls, config)
        raise SsoValidationError, 'SAML refused: no IdP entity ID is configured.' if settings.idp_entity_id.blank?

        xml = Base64.decode64(saml_response.to_s)
        if xml.include?('EncryptedAssertion')
          raise SsoValidationError,
                'SAML refused: encrypted assertions are not supported.'
        end

        request_id = in_response_to(xml)
        if request_id.nil?
          unless self.class.truthy?(self.class.option(:allow_idp_initiated, 'ESCALATED_SSO_ALLOW_IDP_INITIATED'))
            raise SsoValidationError,
                  'SAML refused: unsolicited response (no InResponseTo) and IdP-initiated sign-in is off.'
          end
        elsif !Escalated::SsoMessageId.consume('saml_request', request_id)
          raise SsoValidationError, "SAML refused: InResponseTo [#{request_id}] is not a pending request."
        end

        response = OneLogin::RubySaml::Response.new(
          saml_response.to_s,
          settings: settings,
          matches_request_id: request_id,
          allowed_clock_drift: clock_skew
        )
        raise SsoValidationError, "SAML refused: #{response.errors.join('; ')}" unless response.is_valid?(true)

        assertion_id = response.assertion_id.to_s
        until_at = (response.not_on_or_after || (Time.current + 300)).to_i + clock_skew
        if assertion_id.empty? || !Escalated::SsoMessageId.claim('saml_assertion', assertion_id, until_at)
          raise SsoValidationError, "SAML refused: assertion [#{assertion_id}] was already used."
        end

        attributes = response.attributes
        first = ->(name) { Array(attributes.multi(name.to_s)).first.to_s.strip }
        email = first.call(config['sso_attr_email'].presence || 'email')
        email = response.nameid.to_s.strip if email.empty? && response.nameid.to_s.match?(EMAIL)
        identity(email, first.call(config['sso_attr_name'].presence || 'name'),
                 first.call(config['sso_attr_role'].presence || 'role'))
      rescue OneLogin::RubySaml::ValidationError => e
        raise SsoValidationError, "SAML refused: #{e.message}"
      end

      # ---- OAuth 2 / OIDC -----------------------------------------------------

      def oauth_client(config)
        authorize = URI.parse(config['sso_oauth_authorize_url'])
        token = URI.parse(config['sso_oauth_token_url'])
        OAuth2::Client.new(
          config['sso_oauth_client_id'], config['sso_oauth_client_secret'],
          site: "#{token.scheme}://#{token.host}:#{token.port}",
          authorize_url: authorize.to_s,
          token_url: token.to_s,
          auth_scheme: :request_body
        )
      end

      # The provider's authorization URL with a fresh state and a PKCE (S256)
      # challenge; the caller keeps state and verifier in the session.
      def oauth_start(urls)
        config = get_config
        if config['sso_oauth_authorize_url'].blank? || config['sso_oauth_token_url'].blank? ||
           config['sso_oauth_client_id'].blank?
          raise SsoValidationError, 'OAuth refused: the provider is not fully configured.'
        end

        state = SecureRandom.urlsafe_base64(32)
        verifier = SecureRandom.urlsafe_base64(48)
        challenge = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
        url = oauth_client(config).auth_code.authorize_url(
          redirect_uri: urls.sso_oauth_callback_url,
          scope: config['sso_oauth_scopes'].to_s.split(/[\s,]+/).reject(&:empty?).join(' '),
          state: state,
          code_challenge: challenge,
          code_challenge_method: 'S256'
        )
        { url: url, state: state, verifier: verifier }
      end

      # Exchange the code (with the PKCE verifier) server to server and read
      # the profile from the userinfo endpoint.
      def oauth_identity(urls, code, verifier)
        config = get_config
        begin
          token = oauth_client(config).auth_code.get_token(
            code, redirect_uri: urls.sso_oauth_callback_url, code_verifier: verifier
          )
          profile = token.get(config['sso_oauth_userinfo_url'], headers: { 'Accept' => 'application/json' }).parsed
        rescue StandardError => e
          raise SsoValidationError, "OAuth refused: #{e.message}"
        end
        profile = {} unless profile.is_a?(Hash)
        if [false, 'false', 0, '0'].include?(profile['email_verified'])
          raise SsoValidationError, 'OAuth refused: the provider says the email is not verified.'
        end

        claim = ->(name, fallback = nil) { (profile[name] || (fallback && profile[fallback])).to_s.strip }
        identity(claim.call(config['sso_attr_email'].presence || 'email', 'email'),
                 claim.call(config['sso_attr_name'].presence || 'name', 'name'),
                 claim.call(config['sso_attr_role'].presence || 'role'))
      end

      # ---- JWT -------------------------------------------------------------------

      def jwt_login_url(urls)
        config = get_config
        url = (config['sso_login_url'].presence || config['sso_url']).to_s.strip
        raise SsoValidationError, 'JWT sign-in has no login URL configured.' if url.empty?

        "#{url}#{url.include?('?') ? '&' : '?'}#{URI.encode_www_form(return_to: urls.sso_jwt_callback_url)}"
      end

      # The token's alg must be the configured algorithm (so none and switching
      # are refused); exp is required; nbf/iat hold within the skew; aud names
      # this install; jti is required and used once.
      def validate_jwt(token, default_audience)
        config = get_config
        algorithm = config['sso_jwt_algorithm'].presence || 'HS256'
        secret = config['sso_jwt_secret'].to_s
        unless JWT_ALGORITHMS.include?(algorithm)
          raise SsoValidationError,
                "JWT refused: unsupported algorithm #{algorithm}."
        end
        raise SsoValidationError, 'JWT refused: no secret or public key is configured.' if secret.empty?

        audience = self.class.option(:jwt_audience, 'ESCALATED_SSO_JWT_AUDIENCE').presence || default_audience
        raise SsoValidationError, 'JWT refused: no audience is configured.' if audience.blank?

        key = algorithm.start_with?('RS') ? OpenSSL::PKey::RSA.new(secret) : secret
        claims, = JWT.decode(token.to_s, key, true,
                             algorithm: algorithm, required_claims: %w[exp jti],
                             aud: audience, verify_aud: true, leeway: clock_skew,
                             verify_iat: true)
        jti = claims['jti'].to_s
        raise SsoValidationError, 'JWT refused: no jti claim.' if jti.empty?
        unless Escalated::SsoMessageId.claim('jwt', jti, claims['exp'].to_i + clock_skew)
          raise SsoValidationError, "JWT refused: jti [#{jti}] was already used."
        end

        claim = ->(name, fallback = nil) { (claims[name] || (fallback && claims[fallback])).to_s.strip }
        identity(claim.call(config['sso_attr_email'].presence || 'email', 'email'),
                 claim.call(config['sso_attr_name'].presence || 'name', 'name'),
                 claim.call(config['sso_attr_role'].presence || 'role'))
      rescue JWT::DecodeError, OpenSSL::PKey::PKeyError => e
        raise SsoValidationError, "JWT refused: #{e.message}"
      end

      private

      def in_response_to(xml)
        doc = REXML::Document.new(xml)
        raise SsoValidationError, 'SAML refused: malformed XML.' if doc.root.nil?

        value = doc.root.attributes['InResponseTo'].to_s.strip
        value.empty? ? nil : value
      rescue REXML::ParseException
        raise SsoValidationError, 'SAML refused: malformed XML.'
      end

      def identity(email, name, role)
        raise SsoValidationError, 'SSO refused: no valid email in the identity.' unless email.to_s.match?(EMAIL)

        { email: email, name: name.to_s, role: role.to_s }
      end
    end
  end
end
