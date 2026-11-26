# frozen_string_literal: true

require 'rails_helper'

# The staff API checks what a token may do and who owns it on every request,
# the same way escalated-laravel's AuthenticateApiToken does: abilities are
# `agent`, `admin` and `*` (not hierarchical), the owner must still be an
# agent, and admin endpoints need an admin-capable token owned by an admin.
RSpec.describe 'Staff API token abilities', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:agent) { create(:user, :agent) }
  let(:customer) { create(:user) }
  let(:ticket) { create(:escalated_ticket) }

  def bearer(user, abilities)
    token = Escalated::ApiToken.create_token(user, 'abilities spec', abilities)
    { 'Authorization' => "Bearer #{token[:plain_text_token]}" }
  end

  describe 'DELETE /support/api/v1/tickets/:reference' do
    it 'deletes the ticket for an admin token owned by an admin' do
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(admin, ['admin'])

      expect(response).to have_http_status(:ok)
      expect(Escalated::Ticket.exists?(ticket.id)).to be(false)
    end

    it 'deletes the ticket for a * token owned by an admin' do
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(admin, ['*'])

      expect(response).to have_http_status(:ok)
      expect(Escalated::Ticket.exists?(ticket.id)).to be(false)
    end

    it 'refuses a token owned by a customer' do
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(customer, ['*'])

      expect(response).to have_http_status(:forbidden)
      expect(Escalated::Ticket.exists?(ticket.id)).to be(true)
    end

    it 'refuses a * token owned by an agent who is not an admin' do
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(agent, ['*'])

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq('Insufficient permissions.')
      expect(Escalated::Ticket.exists?(ticket.id)).to be(true)
    end

    it 'refuses an agent-only token even when an admin owns it' do
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(admin, ['agent'])

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq('Insufficient permissions.')
      expect(Escalated::Ticket.exists?(ticket.id)).to be(true)
    end

    it 'refuses a token with an unrelated ability' do
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(admin, ['customer'])

      expect(response).to have_http_status(:forbidden)
      expect(Escalated::Ticket.exists?(ticket.id)).to be(true)
    end
  end

  describe 'agent endpoints' do
    it 'accept an agent token owned by an agent' do
      get '/support/api/v1/tickets', headers: bearer(agent, ['agent'])

      expect(response).to have_http_status(:ok)
    end

    it 'do not treat the admin ability as agent' do
      get '/support/api/v1/tickets', headers: bearer(admin, ['admin'])

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq('Insufficient permissions.')
    end

    it 'refuse a token without a staff ability' do
      get '/support/api/v1/dashboard', headers: bearer(agent, ['customer'])

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq('Insufficient permissions.')
    end

    it 'refuse a token whose owner is not an agent' do
      get "/support/api/v1/tickets/#{ticket.reference}", headers: bearer(customer, ['*'])

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq('User no longer has agent access.')
    end

    it 'refuse a token whose owner has stopped being an agent' do
      headers = bearer(agent, ['agent'])
      agent.update!(is_agent: false, role: 'customer')

      get '/support/api/v1/agents', headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq('User no longer has agent access.')
    end

    it 'refuse a customer-owned token on POST /auth/validate' do
      post '/support/api/v1/auth/validate', headers: bearer(customer, ['*'])

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'own-account endpoints' do
    it 'still accept any valid token on GET /auth/me' do
      get '/support/api/v1/auth/me', headers: bearer(customer, ['customer'])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'id')).to eq(customer.id)
    end
  end
end
