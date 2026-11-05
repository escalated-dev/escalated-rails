# frozen_string_literal: true

require 'rails_helper'

# The host's guards for the embedded admin (ADR 2026-11-05-embeddable-admin):
# config.embed[:middleware] takes before_action method names and callables,
# run in order on the embedded routes only.
RSpec.describe 'Embedded admin: host guards', type: :request do
  let(:admin) { create(:user, :admin, email: 'embed-guards-admin@example.test') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    sign_in_as(admin)
  end

  describe 'by method name and as a block' do
    embed_admin_with(middleware: [:spec_host_guard!, -> { response.set_header('X-Host-Block', '1') }])

    it 'runs each of them on the embedded admin' do
      get '/backoffice/helpdesk/tags'

      expect(response).to have_http_status(:ok)
      expect(response.headers).to include('X-Host-Symbol' => '1', 'X-Host-Block' => '1')
    end

    it 'runs none of them anywhere else' do
      get '/support/agent'

      expect(response.headers).not_to have_key('X-Host-Symbol')
      expect(response.headers).not_to have_key('X-Host-Block')
    end
  end

  describe 'a guard that refuses' do
    embed_admin_with(middleware: [->(c) { c.head(:forbidden) }, ->(c) { c.response.set_header('X-Later', '1') }])

    it 'stops the request there' do
      get '/backoffice/helpdesk/tags'

      expect(response).to have_http_status(:forbidden)
      expect(response.headers).not_to have_key('X-Later')
    end
  end

  describe 'a method name the controller does not have' do
    embed_admin_with(middleware: [:no_such_host_guard!])

    it 'fails closed instead of skipping it' do
      get '/backoffice/helpdesk/tags'

      # The ArgumentError, rendered by the dummy app's exception handling.
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).not_to include('Escalated/Admin/Tags/Index')
    end
  end

  describe 'without host guards configured' do
    embed_admin_with(middleware: nil)

    it "runs config.middleware, every Escalated screen's default" do
      allow(Escalated.configuration).to receive(:middleware).and_return([:spec_host_guard!])
      get '/backoffice/helpdesk/tags'

      expect(response.headers['X-Host-Symbol']).to eq('1')
    end
  end
end
