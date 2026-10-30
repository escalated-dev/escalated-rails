# frozen_string_literal: true

require 'rails_helper'

# The `ziggy` prop every Escalated Inertia response carries.
RSpec.describe 'Built-in route list', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-route-list@example.test') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
  end

  describe 'the ziggy prop' do
    it 'is shared with staff screens in the Ziggy shape' do
      get '/support/admin/reports'

      ziggy = inertia_page.dig('props', 'ziggy')
      expect(ziggy).to include('url' => 'http://www.example.com', 'port' => nil, 'defaults' => {},
                               'location' => 'http://www.example.com/support/admin/reports')
      expect(ziggy.dig('routes', 'escalated.admin.tickets.show'))
        .to eq('uri' => 'support/admin/tickets/{id}', 'methods' => %w[GET HEAD])
      expect(ziggy['routes'].keys).to match_array(Escalated::RouteList.routes.keys)
    end

    it 'is shared with guest screens' do
      get '/support/guest/create'

      expect(inertia_page.dig('props', 'ziggy', 'routes', 'escalated.guest.tickets.store'))
        .to eq('uri' => 'support/guest', 'methods' => %w[POST])
    end

    it 'carries the host overrides over the built-in entries' do
      allow(Escalated.configuration).to receive(:route_overrides)
        .and_return('login' => '/users/sign_in', 'escalated.admin.reports' => 'insights')

      get '/support/admin/reports'

      routes = inertia_page.dig('props', 'ziggy', 'routes')
      expect(routes['login']).to eq('uri' => 'users/sign_in', 'methods' => %w[GET HEAD])
      expect(routes['escalated.admin.reports']).to eq('uri' => 'insights', 'methods' => %w[GET HEAD])
    end
  end

  # The split dialog posts to the ticket with the reply in the body.
  it 'splits a reply off at the listed path' do
    ticket = create(:escalated_ticket)
    reply = create(:escalated_reply, ticket: ticket)
    path = "/#{Escalated::RouteList.routes['escalated.admin.tickets.split'][:uri].sub('{id}', ticket.reference)}"

    expect { post path, params: { reply_id: reply.id } }.to change(Escalated::Ticket, :count).by(1)
    expect(response).to have_http_status(:redirect)
  end
end
