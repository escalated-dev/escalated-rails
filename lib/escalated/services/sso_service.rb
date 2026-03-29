require "base64"
require "json"
require "openssl"
require "rexml/document"
require "time"

module Escalated
  module Services
    class SsoValidationError < StandardError; end

    class SsoService
      CONFIG_KEYS = %w[sso_provider sso_entity_id sso_url sso_certificate sso_attr_email sso_attr_name sso_attr_role sso_jwt_secret sso_jwt_algorithm].freeze
      DEFAULTS = {
        "sso_provider" => "none",
        "sso_entity_id" => "",
        "sso_url" => "",
        "sso_certificate" => "",
        "sso_attr_email" => "email",
        "sso_attr_name" => "name",
        "sso_attr_role" => "role",
        "sso_jwt_secret" => "",
        "sso_jwt_algorithm" => "HS256"
      }.freeze

      SAML_NS = {
        "saml" => "urn:oasis:names:tc:SAML:2.0:assertion",
        "samlp" => "urn:oasis:names:tc:SAML:2.0:protocol"
      }.freeze

      def get_config
        CONFIG_KEYS.each_with_object({}) do |key, hash|
          setting = Escalated::EscalatedSetting.find_by(key: key)
          hash[key] = setting&.value || DEFAULTS[key]
        end
      end

      def save_config(data)
        CONFIG_KEYS.each do |key|
          next unless data.key?(key)

          Escalated::EscalatedSetting.find_or_initialize_by(key: key).update!(value: data[key])
        end
      end

      def enabled?
        provider != "none"
      end

      def provider
        Escalated::EscalatedSetting.find_by(key: "sso_provider")&.value || "none"
      end

      # -----------------------------------------------------------------
      # SAML Assertion Validation
      # -----------------------------------------------------------------

      # Validates a base64-encoded SAML response and extracts user attributes.
      # Returns a hash with :email, :name, :role, :attributes.
      # Raises SsoValidationError on failure.
      def validate_saml_assertion(saml_response)
        config = get_config

        begin
          xml = Base64.decode64(saml_response)
        rescue StandardError
          raise SsoValidationError, "Invalid SAML response: base64 decode failed."
        end

        begin
          doc = REXML::Document.new(xml)
        rescue REXML::ParseException
          raise SsoValidationError, "Invalid SAML response: malformed XML."
        end

        raise SsoValidationError, "Invalid SAML response: malformed XML." if doc.root.nil?

        # Check issuer
        entity_id = (config["sso_entity_id"] || "").strip
        unless entity_id.empty?
          issuer_el = REXML::XPath.first(doc, "//saml:Issuer", SAML_NS)
          raise SsoValidationError, "SAML assertion missing Issuer element." if issuer_el.nil?

          issuer = (issuer_el.text || "").strip
          if issuer != entity_id
            raise SsoValidationError, "SAML Issuer mismatch: expected '#{entity_id}', got '#{issuer}'."
          end
        end

        # Validate conditions
        conditions_el = REXML::XPath.first(doc, "//saml:Conditions", SAML_NS)
        validate_saml_conditions(conditions_el) if conditions_el

        # Extract attributes
        attr_email = config["sso_attr_email"] || "email"
        attr_name = config["sso_attr_name"] || "name"
        attr_role = config["sso_attr_role"] || "role"

        attributes = extract_saml_attributes(doc)

        email = attributes[attr_email]
        if email.nil? || email.empty?
          name_id_el = REXML::XPath.first(doc, "//saml:Subject/saml:NameID", SAML_NS)
          email = name_id_el&.text&.strip
        end

        raise SsoValidationError, "SAML assertion missing email attribute." if email.nil? || email.empty?

        {
          email: email,
          name: attributes[attr_name] || "",
          role: attributes[attr_role] || "",
          attributes: attributes
        }
      end

      # -----------------------------------------------------------------
      # JWT Token Validation
      # -----------------------------------------------------------------

      # Validates a JWT token and extracts user attributes.
      # Returns a hash with :email, :name, :role, :claims.
      # Raises SsoValidationError on failure.
      def validate_jwt_token(token)
        config = get_config

        parts = token.split(".")
        raise SsoValidationError, "Invalid JWT: expected 3 segments." unless parts.length == 3

        header_b64, payload_b64, signature_b64 = parts

        begin
          header = JSON.parse(base64url_decode(header_b64))
        rescue StandardError
          raise SsoValidationError, "Invalid JWT: malformed header."
        end

        begin
          payload = JSON.parse(base64url_decode(payload_b64))
        rescue StandardError
          raise SsoValidationError, "Invalid JWT: malformed payload."
        end

        secret = config["sso_jwt_secret"] || ""
        algorithm = config["sso_jwt_algorithm"] || "HS256"
        raise SsoValidationError, "JWT secret is not configured." if secret.empty?

        signature = base64url_decode(signature_b64)
        signing_input = "#{header_b64}.#{payload_b64}"

        unless verify_jwt_signature(signing_input, signature, secret, algorithm)
          raise SsoValidationError, "Invalid JWT: signature verification failed."
        end

        now = Time.now.to_i
        skew = 60

        if payload["exp"] && payload["exp"] < (now - skew)
          raise SsoValidationError, "JWT has expired."
        end

        if payload["nbf"] && payload["nbf"] > (now + skew)
          raise SsoValidationError, "JWT is not yet valid."
        end

        attr_email = config["sso_attr_email"] || "email"
        attr_name = config["sso_attr_name"] || "name"
        attr_role = config["sso_attr_role"] || "role"

        email = payload[attr_email] || payload["email"] || payload["sub"]
        raise SsoValidationError, "JWT missing email claim." if email.nil? || email.to_s.empty?

        {
          email: email,
          name: payload[attr_name] || payload["name"] || "",
          role: payload[attr_role] || payload["role"] || "",
          claims: payload
        }
      end

      private

      def validate_saml_conditions(conditions_el)
        now = Time.now.to_i
        skew = 120

        not_before = conditions_el.attributes["NotBefore"]
        if not_before && !not_before.empty?
          begin
            dt = Time.parse(not_before).to_i
            raise SsoValidationError, "SAML assertion is not yet valid." if dt > (now + skew)
          rescue ArgumentError
            # Skip if unparseable
          end
        end

        not_on_or_after = conditions_el.attributes["NotOnOrAfter"]
        if not_on_or_after && !not_on_or_after.empty?
          begin
            dt = Time.parse(not_on_or_after).to_i
            raise SsoValidationError, "SAML assertion has expired." if dt < (now - skew)
          rescue ArgumentError
            # Skip if unparseable
          end
        end
      end

      def extract_saml_attributes(doc)
        attributes = {}
        REXML::XPath.each(doc, "//saml:AttributeStatement/saml:Attribute", SAML_NS) do |attr_el|
          name = attr_el.attributes["Name"]
          value_el = REXML::XPath.first(attr_el, "saml:AttributeValue", SAML_NS)
          attributes[name] = (value_el&.text || "").strip if name
        end
        attributes
      end

      def verify_jwt_signature(signing_input, signature, secret, algorithm)
        hmac_algos = {
          "HS256" => "sha256",
          "HS384" => "sha384",
          "HS512" => "sha512"
        }

        if hmac_algos.key?(algorithm)
          expected = OpenSSL::HMAC.digest(hmac_algos[algorithm], secret, signing_input)
          return secure_compare(expected, signature)
        end

        rsa_algos = {
          "RS256" => "SHA256",
          "RS384" => "SHA384",
          "RS512" => "SHA512"
        }

        if rsa_algos.key?(algorithm)
          pub_key = OpenSSL::PKey::RSA.new(secret)
          return pub_key.verify(rsa_algos[algorithm], signature, signing_input)
        end

        raise SsoValidationError, "Unsupported JWT algorithm: #{algorithm}"
      end

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        OpenSSL.fixed_length_secure_compare(a, b)
      rescue StandardError
        # Fallback for older Ruby
        a == b
      end

      def base64url_decode(str)
        str += "=" * (-str.length % 4)
        Base64.urlsafe_decode64(str)
      end
    end
  end
end
