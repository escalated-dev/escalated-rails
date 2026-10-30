# frozen_string_literal: true

require 'rails_helper'
require 'cgi'
require 'webmock/rspec'
require 'escalated/seeds/permissions'

# ADR 2026-10-29-configurable-access-features: single sign-on is an
# install-level switch (config.access[:sso] / ESCALATED_SSO). Off, every SSO
# route and the SSO settings page answer 404. On, the provider chosen in Admin >
# Settings > SSO (SAML, OAuth 2 / OIDC with state and PKCE, or JWT) signs a
# matched host user in.

# Test IdP material (a throwaway key shared with escalated-adonis) and the
# endpoints the dummy app serves.
module SsoSpecFixtures
  IDP_KEY = File.read(File.join(__dir__, '../../fixtures/saml/idp-test-key.pem'))
  IDP_CERT = File.read(File.join(__dir__, '../../fixtures/saml/idp-test-cert.pem'))
  IDP_ENTITY = 'https://idp.example.test/metadata'
  ACS = 'http://www.example.com/support/sso/saml/acs'
  SP_ENTITY = 'http://www.example.com/support/sso/saml/metadata'
  AUD = 'https://help.example.test'
  SECRET = 'shared-jwt-secret-of-enough-length'
end

RSpec.describe 'SSO enforcement', type: :request do
  let!(:alice) { create(:user, email: 'Alice@Example.test', name: 'Alice') }
  let(:signed_in) { [] }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    hook = ->(_controller, user) { signed_in << user.id }
    Escalated.configuration.sso = { sign_in: hook, jwt_audience: SsoSpecFixtures::AUD }
  end

  after do
    Escalated.configuration.access = {}
    Escalated.configuration.sso = {}
  end

  def turn_on!(roles: false)
    Escalated.configuration.access = { sso: true, roles_permissions: roles }
  end

  def configure(values)
    values.each { |key, value| Escalated::EscalatedSetting.find_or_initialize_by(key: key).update!(value: value) }
  end

  def refused?
    response.status == 403 && response.body == 'Single sign-on failed. Contact your administrator.'
  end

  describe 'switched off (the default)' do
    before { configure('sso_provider' => 'jwt', 'sso_jwt_secret' => 'x' * 32, 'sso_url' => 'https://idp.test') }

    it 'answers 404 on every SSO route and the settings page' do
      get '/support/sso/login'
      expect(response).to have_http_status(:not_found)
      get '/support/sso/saml/metadata'
      expect(response).to have_http_status(:not_found)
      post '/support/sso/saml/acs', params: { SAMLResponse: 'x' }
      expect(response).to have_http_status(:not_found)
      get '/support/sso/oauth/callback', params: { code: 'c', state: 's' }
      expect(response).to have_http_status(:not_found)
      get '/support/sso/jwt/callback', params: { jwt: 'x' }
      expect(response).to have_http_status(:not_found)

      allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user) # rubocop:disable RSpec/AnyInstance
        .and_return(create(:user, :admin))
      get '/support/admin/settings/sso'
      expect(response).to have_http_status(:not_found)
      expect(signed_in).to eq([])
    end

    it 'cannot be turned on from the settings store' do
      configure('sso' => '1', 'access.sso' => '1', 'ESCALATED_SSO' => '1')
      get '/support/sso/login'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'switched on' do
    before { turn_on! }

    it 'answers 404 on sign-in while the provider is none' do
      get '/support/sso/login'
      expect(response).to have_http_status(:not_found)
    end

    it 'renders the settings page with secrets masked and the endpoints for the IdP' do
      configure('sso_provider' => 'jwt', 'sso_jwt_secret' => 'top-secret', 'sso_url' => 'https://idp.test/login')
      allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user) # rubocop:disable RSpec/AnyInstance
        .and_return(create(:user, :admin))
      get '/support/admin/settings/sso'
      page = JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))
      expect(page['component']).to eq('Escalated/Admin/Settings/SsoSettings')
      expect(page.dig('props', 'settings', 'sso_jwt_secret')).to eq('********')
      expect(response.body).not_to include('top-secret')
      expect(page.dig('props', 'endpoints')).to eq(
        'login' => 'http://www.example.com/support/sso/login',
        'sp_entity_id' => SsoSpecFixtures::SP_ENTITY,
        'metadata' => SsoSpecFixtures::SP_ENTITY,
        'acs' => SsoSpecFixtures::ACS,
        'oauth_redirect' => 'http://www.example.com/support/sso/oauth/callback',
        'jwt_callback' => 'http://www.example.com/support/sso/jwt/callback'
      )
    end

    describe 'SAML' do
      before do
        configure('sso_provider' => 'saml', 'sso_entity_id' => SsoSpecFixtures::IDP_ENTITY,
                  'sso_login_url' => 'https://idp.example.test/sso', 'sso_certificate' => SsoSpecFixtures::IDP_CERT)
      end

      def start
        get '/support/sso/login'
        expect(response).to have_http_status(:redirect)
        location = URI.parse(response.location)
        expect("#{location.scheme}://#{location.host}#{location.path}").to eq('https://idp.example.test/sso')
        request = CGI.parse(location.query)['SAMLRequest'].first
        xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(request))
        xml[/ID=['"]([^'"]+)['"]/, 1]
      end

      def iso(offset)
        (Time.now.utc + offset).iso8601
      end

      # rubocop:disable-next Metrics/ParameterLists
      def assertion(request_id, email: 'alice@example.test', issuer: SsoSpecFixtures::IDP_ENTITY,
                    audience: SsoSpecFixtures::SP_ENTITY, recipient: SsoSpecFixtures::ACS,
                    not_on_or_after: iso(300), id: "_a#{SecureRandom.hex(10)}")
        irt = request_id ? %( InResponseTo="#{request_id}") : ''
        <<~XML.delete("\n")
          <saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="#{id}" Version="2.0" IssueInstant="#{iso(0)}">
          <saml:Issuer>#{issuer}</saml:Issuer>
          <saml:Subject><saml:NameID>#{email}</saml:NameID>
          <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
          <saml:SubjectConfirmationData Recipient="#{recipient}"#{irt} NotOnOrAfter="#{not_on_or_after}"/>
          </saml:SubjectConfirmation></saml:Subject>
          <saml:Conditions NotBefore="#{iso(-60)}" NotOnOrAfter="#{not_on_or_after}">
          <saml:AudienceRestriction><saml:Audience>#{audience}</saml:Audience></saml:AudienceRestriction>
          </saml:Conditions>
          <saml:AuthnStatement AuthnInstant="#{iso(0)}"><saml:AuthnContext><saml:AuthnContextClassRef>urn:oasis:names:tc:SAML:2.0:ac:classes:Password</saml:AuthnContextClassRef></saml:AuthnContext></saml:AuthnStatement>
          <saml:AttributeStatement>
          <saml:Attribute Name="email"><saml:AttributeValue>#{email}</saml:AttributeValue></saml:Attribute>
          </saml:AttributeStatement>
          </saml:Assertion>
        XML
      end

      # ruby-saml's signer lists samlp in InclusiveNamespaces, so the
      # assertion declares it itself, as it will be in scope inside the Response.
      def sign(xml, key: SsoSpecFixtures::IDP_KEY, cert: SsoSpecFixtures::IDP_CERT)
        document = XMLSecurity::Document.new(xml)
        document.sign_document(OpenSSL::PKey::RSA.new(key), OpenSSL::X509::Certificate.new(cert),
                               XMLSecurity::Document::RSA_SHA256, XMLSecurity::Document::SHA256)
        document.root.to_s
      end

      def response_xml(inner, request_id, destination: SsoSpecFixtures::ACS)
        irt = request_id ? %( InResponseTo="#{request_id}") : ''
        open = %(<samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="_r#{SecureRandom.hex(10)}") +
               %( Version="2.0" IssueInstant="#{iso(0)}" Destination="#{destination}"#{irt}>)
        issuer = %(<saml:Issuer xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion">#{SsoSpecFixtures::IDP_ENTITY}</saml:Issuer>)
        status = '<samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>'
        "#{open}#{issuer}#{status}#{inner}</samlp:Response>"
      end

      def post_acs(xml)
        post '/support/sso/saml/acs', params: { SAMLResponse: Base64.strict_encode64(xml) }
      end

      def other_key_and_cert
        key = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = 1
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=other-idp')
        cert.public_key = key.public_key
        cert.not_before = Time.current - 60
        cert.not_after = Time.current + 3600
        cert.sign(key, OpenSSL::Digest.new('SHA256'))
        [key.to_pem, cert.to_pem]
      end

      it 'signs in the matched user with a correctly signed response for the pending request' do
        id = start
        post_acs(response_xml(sign(assertion(id)), id))
        expect(response).to redirect_to('/support/agent')
        expect(signed_in).to eq([alice.id])
      end

      it 'serves SP metadata naming the entity ID and SsoSpecFixtures::ACS URL' do
        get '/support/sso/saml/metadata'
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(SsoSpecFixtures::SP_ENTITY).and include(SsoSpecFixtures::ACS)
      end

      {
        'with no certificate configured' => [lambda { |id|
          response_xml(sign(assertion(id)), id)
        }, { 'sso_certificate' => '' }],
        'with an unsigned assertion' => [->(id) { response_xml(assertion(id), id) }],
        'signed by another key' => [lambda { |id|
          key, cert = other_key_and_cert
          response_xml(sign(assertion(id), key: key, cert: cert), id)
        }],
        'tampered after signing' => [lambda { |id|
          response_xml(sign(assertion(id)).gsub('alice@example.test', 'mallory@example.test'), id)
        }],
        'from another Issuer' => [->(id) { response_xml(sign(assertion(id, issuer: 'https://evil.test')), id) }],
        'for another Audience' => [->(id) { response_xml(sign(assertion(id, audience: 'https://other-sp.test')), id) }],
        'to another Destination' => [lambda { |id|
          response_xml(sign(assertion(id)), id, destination: 'https://other-sp.test/acs')
        }],
        'for another Recipient' => [lambda { |id|
          response_xml(sign(assertion(id, recipient: 'https://other-sp.test/acs')), id)
        }],
        'once expired' => [->(id) { response_xml(sign(assertion(id, not_on_or_after: iso(-900))), id) }],
        'answering a request it never issued' => [->(_id) { response_xml(sign(assertion('_unknown')), '_unknown') }],
        'with no InResponseTo while IdP-initiated sign-in is off' => [lambda { |_id|
          response_xml(sign(assertion(nil)), nil)
        }]
      }.each do |why, (build, overrides)|
        it "refuses a response #{why}" do
          id = start
          configure(overrides) if overrides
          post_acs(instance_exec(id, &build))
          expect(refused?).to be(true)
          expect(signed_in).to eq([])
        end
      end

      it 'refuses the same assertion a second time' do
        id = start
        xml = response_xml(sign(assertion(id)), id)
        post_acs(xml)
        expect(signed_in).to eq([alice.id])
        post_acs(xml)
        expect(refused?).to be(true)
        expect(signed_in).to eq([alice.id])
      end

      it 'refuses a replayed assertion ID even when IdP-initiated sign-in is allowed' do
        Escalated.configuration.sso = Escalated.configuration.sso.merge(allow_idp_initiated: true)
        xml = response_xml(sign(assertion(nil)), nil)
        post_acs(xml)
        expect(signed_in).to eq([alice.id])
        post_acs(xml)
        expect(refused?).to be(true)
        expect(signed_in).to eq([alice.id])
      end
    end

    describe 'OAuth 2 / OIDC' do
      before do
        WebMock.enable!
        WebMock.disable_net_connect!(allow_localhost: true)
        configure('sso_provider' => 'oauth', 'sso_oauth_authorize_url' => 'https://idp.test/authorize',
                  'sso_oauth_token_url' => 'https://idp.test/token',
                  'sso_oauth_userinfo_url' => 'https://idp.test/userinfo',
                  'sso_oauth_client_id' => 'client-1', 'sso_oauth_client_secret' => 'client-secret')
      end

      let!(:token_stub) do
        stub_request(:post, 'https://idp.test/token')
          .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                     body: { access_token: 'at-123', token_type: 'Bearer', expires_in: 60 }.to_json)
      end

      let!(:userinfo_stub) do
        stub_request(:get, 'https://idp.test/userinfo')
          .with(headers: { 'Authorization' => 'Bearer at-123' })
          .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                     body: { email: 'alice@example.test', name: 'Alice' }.to_json)
      end

      after do
        WebMock.allow_net_connect!
        WebMock.disable!
      end

      def start
        get '/support/sso/login'
        expect(response).to have_http_status(:redirect)
        URI.parse(response.location)
      end

      it 'signs in with a matching state, sending the PKCE verifier' do
        authorize = start
        query = CGI.parse(authorize.query)
        expect(query['code_challenge_method']).to eq(['S256'])
        expect(query['redirect_uri']).to eq(['http://www.example.com/support/sso/oauth/callback'])

        get '/support/sso/oauth/callback', params: { code: 'the-code', state: query['state'].first }
        expect(response).to redirect_to('/support/agent')
        expect(signed_in).to eq([alice.id])
        expect(token_stub.with do |req|
          body = CGI.parse(req.body)
          verifier = body['code_verifier'].first.to_s
          challenge = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
          body['code'] == ['the-code'] && challenge == query['code_challenge'].first
        end).to have_been_requested
        expect(userinfo_stub).to have_been_requested
      end

      it 'refuses a missing or mismatched state and an IdP error' do
        start
        get '/support/sso/oauth/callback', params: { code: 'c' }
        expect(refused?).to be(true)
        start
        get '/support/sso/oauth/callback', params: { code: 'c', state: 'forged' }
        expect(refused?).to be(true)
        state = CGI.parse(start.query)['state'].first
        get '/support/sso/oauth/callback', params: { error: 'access_denied', state: state }
        expect(refused?).to be(true)
        expect(signed_in).to eq([])
      end
    end

    describe 'JWT' do
      before do
        configure('sso_provider' => 'jwt', 'sso_url' => 'https://idp.example.test/login',
                  'sso_jwt_secret' => SsoSpecFixtures::SECRET, 'sso_jwt_algorithm' => 'HS256')
      end

      def token(claims = {}, key = SsoSpecFixtures::SECRET, algorithm = 'HS256')
        payload = { 'email' => 'alice@example.test', 'jti' => SecureRandom.uuid, 'aud' => SsoSpecFixtures::AUD,
                    'exp' => Time.now.to_i + 300 }.merge(claims).compact
        JWT.encode(payload, key, algorithm)
      end

      def callback(value)
        get '/support/sso/jwt/callback', params: { jwt: value }
      end

      it 'starts at the configured login URL with where to come back' do
        get '/support/sso/login'
        expect(CGI.parse(URI.parse(response.location).query)['return_to'])
          .to eq(['http://www.example.com/support/sso/jwt/callback'])
      end

      it 'signs in with a valid token, by GET or POST' do
        callback(token)
        expect(response).to redirect_to('/support/agent')
        post '/support/sso/jwt/callback', params: { jwt: token }
        expect(signed_in).to eq([alice.id, alice.id])
      end

      it 'refuses a bad signature, alg none, another algorithm and algorithm confusion' do
        callback(token({}, 'another-secret-of-enough-length!!'))
        expect(refused?).to be(true)
        callback(JWT.encode({ 'email' => 'alice@example.test', 'jti' => 'n', 'aud' => SsoSpecFixtures::AUD,
                              'exp' => Time.now.to_i + 60 }, nil, 'none'))
        expect(refused?).to be(true)
        callback(token({}, SsoSpecFixtures::SECRET, 'HS512'))
        expect(refused?).to be(true)

        rsa = OpenSSL::PKey::RSA.new(2048)
        configure('sso_jwt_algorithm' => 'RS256', 'sso_jwt_secret' => rsa.public_key.to_pem)
        header = Base64.urlsafe_encode64({ alg: 'HS256', typ: 'JWT' }.to_json, padding: false)
        body = Base64.urlsafe_encode64({ email: 'alice@example.test', jti: 'c1', aud: SsoSpecFixtures::AUD,
                                         exp: Time.now.to_i + 60 }.to_json, padding: false)
        signature = Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', rsa.public_key.to_pem, "#{header}.#{body}"),
                                            padding: false)
        callback("#{header}.#{body}.#{signature}")
        expect(refused?).to be(true)

        callback(token({}, rsa, 'RS256'))
        expect(response).to redirect_to('/support/agent')
        expect(signed_in).to eq([alice.id])
      end

      it 'refuses a missing or past exp, a wrong aud and a missing or reused jti' do
        callback(token('exp' => nil))
        expect(refused?).to be(true)
        callback(token('exp' => Time.now.to_i - 900))
        expect(refused?).to be(true)
        callback(token('aud' => 'https://other.test'))
        expect(refused?).to be(true)
        callback(token('jti' => nil))
        expect(refused?).to be(true)

        once = token('jti' => 'only-once')
        callback(once)
        expect(response).to redirect_to('/support/agent')
        callback(once)
        expect(refused?).to be(true)
        expect(signed_in).to eq([alice.id])
      end

      it 'refuses an unknown email unless creating users is on' do
        callback(token('email' => 'new@example.test'))
        expect(refused?).to be(true)

        Escalated.configuration.sso = Escalated.configuration.sso.merge(create_users: true)
        expect { callback(token('email' => 'new@example.test', 'name' => 'New')) }
          .to change { Escalated.configuration.user_model.where(email: 'new@example.test').count }.from(0).to(1)
        expect(response).to have_http_status(:redirect)
      end

      it 'maps the asserted role only with roles on and sync_roles on' do
        Escalated::Seeds::Permissions.seed!
        light = Escalated::Role.find_by!(slug: 'light_agent')

        callback(token('role' => 'light_agent'))
        expect(light.users.reload).not_to include(alice)

        Escalated.configuration.sso = Escalated.configuration.sso.merge(sync_roles: true)
        callback(token('role' => 'light_agent'))
        expect(light.users.reload).not_to include(alice) # roles & permissions is off

        turn_on!(roles: true)
        callback(token('role' => 'no-such-role'))
        expect(Escalated::AccessControl.permission_slugs(alice.id)).to eq([])
        callback(token('role' => 'light_agent'))
        expect(light.users.reload).to include(alice)
      end
    end
  end
end
