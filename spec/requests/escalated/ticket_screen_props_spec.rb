# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The ticket screens read the thread from `ticket.replies`, the list from
# `tickets.data`, and the canned responses from `cannedResponses`
# (Customer/Show.vue, Agent/TicketShow.vue, Admin/Tickets/Show.vue,
# TicketList.vue). The controllers sent `replies` beside the ticket, a bare
# `tickets` array and `canned_responses`, so customers saw no replies, agents
# and admins saw an empty thread, every list said "No tickets found", and the
# canned-response picker never appeared. Each one rendered on a 200.
RSpec.describe 'Ticket screen props', type: :request do
  let(:agent) { create(:user, :agent, email: 'agent-props@example.test') }
  let(:admin) { create(:user, :admin, email: 'admin-props@example.test') }
  let(:customer) { create(:user, email: 'customer-props@example.test') }
  let(:ticket) { create(:escalated_ticket, requester: customer, sla_first_response_due_at: 2.hours.from_now) }

  before do
    create(:escalated_reply, ticket: ticket, author: agent, body: 'We are on it.', is_internal: false)
    create(:escalated_canned_response, title: 'Greeting', creator: agent)
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def page_props(path)
    get path
    expect(response).to have_http_status(:ok)

    encoded = response.body[%r{data-page="(.+?)"></div>}m, 1]
    raise "no Inertia page payload in the response for #{path}" unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))['props']
  end

  describe 'Customer' do
    before { sign_in_as(customer) }

    it 'nests the public replies in the ticket on Customer/Show' do
      props = page_props("/support/customer/tickets/#{ticket.id}")

      expect(props['ticket']['replies'].pluck('body')).to eq(['We are on it.'])
    end

    it 'wraps the ticket list in data on Customer/Index' do
      props = page_props('/support/customer/tickets')

      expect(props['tickets']).to be_a(Hash)
      expect(props['tickets']['data'].pluck('reference')).to eq([ticket.reference])
      expect(props['tickets']).to include('current_page' => 1, 'last_page' => 1, 'total' => 1)
    end
  end

  describe 'Customer ticket routes' do
    before { sign_in_as(customer) }

    it 'renders the form at /tickets/create and /tickets/new' do
      %w[create new].each do |path|
        get "/support/customer/tickets/#{path}"
        expect(response.body).to include('Escalated/Customer/Create')
      end
    end

    it 'saves the ticket the Create page posts' do
      post '/support/customer/tickets',
           params: { subject: 'Printer on fire', description: 'Smoke everywhere.', priority: 'high' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Inertia' => 'true' }

      created = Escalated::Ticket.find_by(subject: 'Printer on fire')
      expect(created).to be_present
      expect(created.requester).to eq(customer)
      expect(response).to redirect_to("/support/customer/tickets/#{created.id}")
    end

    it 'finds the ticket by the reference the pages link with' do
      props = page_props("/support/customer/tickets/#{ticket.reference}")

      expect(props['ticket']['reference']).to eq(ticket.reference)
    end
  end

  describe 'Agent' do
    before { sign_in_as(agent) }

    it 'sends the thread, activity, canned responses and sidebar fields TicketShow reads' do
      props = page_props("/support/agent/tickets/#{ticket.reference}")

      expect(props['ticket']['replies'].pluck('body')).to eq(['We are on it.'])
      expect(props['ticket']).to have_key('activities')
      expect(props['cannedResponses'].pluck('title')).to include('Greeting')
      expect(props).not_to have_key('canned_responses')
      expect(props['ticket']).to include('assigned_to' => nil)
      expect(props['ticket']['first_response_due_at']).to be_present
      expect(props['ticket']).to have_key('resolution_due_at')
    end

    it 'wraps the ticket list in data on TicketIndex' do
      props = page_props('/support/agent/tickets')

      expect(props['tickets']['data'].pluck('reference')).to eq([ticket.reference])
    end
  end

  describe 'Admin' do
    before { sign_in_as(admin) }

    it 'sends the thread and canned responses Admin/Tickets/Show reads' do
      props = page_props("/support/admin/tickets/#{ticket.reference}")

      expect(props['ticket']['replies'].pluck('body')).to eq(['We are on it.'])
      expect(props['cannedResponses'].pluck('title')).to include('Greeting')
    end

    it 'wraps the ticket list in data on Admin/Tickets/Index' do
      props = page_props('/support/admin/tickets')

      expect(props['tickets']['data'].pluck('reference')).to eq([ticket.reference])
    end
  end
end
