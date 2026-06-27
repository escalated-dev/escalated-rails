# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API auth endpoints', type: :request do
  after do
    Escalated.configure do |c|
      c.api_authenticator = nil
      c.api_logout = nil
    end
  end

  describe 'POST /support/api/v1/auth/login' do
    it 'responds 501 when no authenticator is configured' do
      post '/support/api/v1/auth/login', params: {}, as: :json
      expect(response).to have_http_status(:not_implemented)
    end

    it 'delegates to the configured authenticator' do
      Escalated.configure { |c| c.api_authenticator = ->(params) { { token: 'abc', email: params['email'] } } }

      post '/support/api/v1/auth/login', params: { email: 'a@b.com' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to eq('token' => 'abc', 'email' => 'a@b.com')
    end

    it 'responds 401 when the authenticator returns nil' do
      Escalated.configure { |c| c.api_authenticator = ->(_params) {} }

      post '/support/api/v1/auth/login', params: {}, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /support/api/v1/auth/logout' do
    it 'always succeeds and forwards the bearer token' do
      seen = {}
      Escalated.configure { |c| c.api_logout = ->(token) { seen[:token] = token } }

      post '/support/api/v1/auth/logout',
           headers: { 'Authorization' => 'Bearer tok123' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to eq('success' => true)
      expect(seen[:token]).to eq('tok123')
    end
  end
end
