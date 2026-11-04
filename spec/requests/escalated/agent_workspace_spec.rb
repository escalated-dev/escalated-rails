# frozen_string_literal: true

require 'rails_helper'

# What the agent ticket page needs beyond the ticket itself: the agents it can
# be reassigned to, the requester's other tickets, and snoozing from the agent
# panel (until now only the admin panel could snooze). Mirrors
# escalated-laravel's tests/Feature/Agent/AgentWorkspaceTest.php.
RSpec.describe 'Agent workspace', type: :request do
  let(:agent) { create(:user, :agent, name: 'Ada Agent', email: 'ws-agent@example.test') }
  let(:customer) { create(:user, name: 'Cass Customer', email: 'ws-cass@example.test') }
  let(:signed_in) { { user: agent } }

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user) { signed_in[:user] }
  end

  def show_props(ticket)
    get "/support/agent/tickets/#{ticket.reference}"
    expect(response).to have_http_status(:ok)
    inertia_page['props']
  end

  def department_visibility!
    allow(Escalated.configuration).to receive(:visibility).and_return('department')
  end

  def snooze(ticket, until_time)
    post "/support/agent/tickets/#{ticket.reference}/snooze", params: { snoozed_until: until_time&.iso8601 }
  end

  # --- Reassigning ------------------------------------------------------------

  describe 'agents' do
    it 'sends the agents and admins a ticket can be assigned to, by id and name' do
      agent
      admin = create(:user, :admin, name: 'Al Admin', email: 'ws-al@example.test')
      customer
      ticket = create(:escalated_ticket)

      agents = show_props(ticket)['agents']

      expect(agents.map { |a| a.slice('id', 'name') }).to eq([
                                                               { 'id' => agent.id, 'name' => 'Ada Agent' },
                                                               { 'id' => admin.id, 'name' => 'Al Admin' }
                                                             ])
    end

    it 'leaves out agents who cannot see the ticket under department visibility' do
      create(:user, :agent, name: 'Otto Other', email: 'ws-otto@example.test')
      department = create(:escalated_department)
      department.agents << agent
      ticket = create(:escalated_ticket, department: department)
      department_visibility!

      names = show_props(ticket)['agents'].pluck('name')

      expect(names).to include('Ada Agent')
      expect(names).not_to include('Otto Other')
    end
  end

  # --- The requester's other tickets ------------------------------------------

  describe 'ticket.requester_tickets' do
    it "sends the requester's other tickets, newest first, at most five" do
      older = (1..6).map do |i|
        create(:escalated_ticket, requester: customer, subject: "Earlier #{i}", created_at: (10 - i).days.ago)
      end
      create(:escalated_ticket, subject: 'Someone else')
      ticket = create(:escalated_ticket, requester: customer, created_at: Time.current)

      recent = show_props(ticket)['ticket']['requester_tickets']

      expect(recent.pluck('subject')).to eq(['Earlier 6', 'Earlier 5', 'Earlier 4', 'Earlier 3', 'Earlier 2'])
      expect(recent[0].keys).to eq(%w[id reference subject status created_at updated_at])
      expect(recent[0]['reference']).to eq(older[5].reference)
      expect(recent[0]['status']).to eq('open')
      expect(Time.iso8601(recent[0]['created_at'])).to be_within(1.second).of(older[5].created_at)
    end

    it "matches a guest requester's other tickets by email" do
      create(:escalated_ticket, requester: nil, guest_email: 'guest@example.test', guest_name: 'Gus',
                                subject: 'Earlier guest ticket')
      create(:escalated_ticket, requester: nil, guest_email: 'other@example.test', subject: 'Another guest')
      ticket = create(:escalated_ticket, requester: nil, guest_email: 'guest@example.test', guest_name: 'Gus')

      recent = show_props(ticket)['ticket']['requester_tickets']

      expect(recent.pluck('subject')).to eq(['Earlier guest ticket'])
    end

    it 'only lists requester tickets the agent may see' do
      department = create(:escalated_department)
      department.agents << agent
      create(:escalated_ticket, requester: customer, department: department, subject: 'Visible')
      create(:escalated_ticket, requester: customer, department: create(:escalated_department), subject: 'Hidden')
      ticket = create(:escalated_ticket, requester: customer, department: department)
      department_visibility!

      recent = show_props(ticket)['ticket']['requester_tickets']

      expect(recent.pluck('subject')).to eq(['Visible'])
    end

    it 'sends an empty list for a ticket with no known requester' do
      create(:escalated_ticket, requester: nil)
      ticket = create(:escalated_ticket, requester: nil)

      expect(show_props(ticket)['ticket']['requester_tickets']).to eq([])
    end

    it 'leaves related_tickets as the linked tickets' do
      ticket = create(:escalated_ticket, requester: customer)
      create(:escalated_ticket, requester: customer)

      expect(show_props(ticket)['ticket']['related_tickets']).to eq([])
    end
  end

  # --- Snoozing from the agent panel --------------------------------------------

  describe 'snooze' do
    it 'lets an agent snooze a ticket' do
      ticket = create(:escalated_ticket, status: :open)
      until_time = 1.day.from_now.change(sec: 0)

      snooze(ticket, until_time)

      expect(response).to redirect_to("/support/agent/tickets/#{ticket.id}")
      expect(flash[:notice]).to be_present
      ticket.reload
      expect(ticket.snoozed_until).to be_within(1.second).of(until_time)
      expect(ticket.snoozed_by).to eq(agent.id)
      expect(ticket.status).to eq('open')
    end

    it 'rejects a snooze time in the past' do
      ticket = create(:escalated_ticket)

      snooze(ticket, 1.hour.ago)

      expect(response).to have_http_status(:redirect)
      expect(session[:inertia_errors]&.keys).to eq(['snoozed_until'])
      expect(ticket.reload.snoozed_until).to be_nil
    end

    it 'rejects a missing or unparseable snooze time' do
      ticket = create(:escalated_ticket)

      post "/support/agent/tickets/#{ticket.reference}/snooze", params: { snoozed_until: 'not a date' }
      expect(session[:inertia_errors]&.keys).to eq(['snoozed_until'])

      post "/support/agent/tickets/#{ticket.reference}/snooze"
      expect(session[:inertia_errors]&.keys).to eq(['snoozed_until'])
      expect(ticket.reload.snoozed_until).to be_nil
    end

    it 'lets an agent unsnooze a ticket and restores its status' do
      ticket = create(:escalated_ticket, status: :in_progress)
      snooze(ticket, 1.day.from_now)
      expect(ticket.reload.snoozed_until).to be_present

      post "/support/agent/tickets/#{ticket.reference}/unsnooze"

      expect(response).to redirect_to("/support/agent/tickets/#{ticket.id}")
      expect(flash[:notice]).to be_present
      ticket.reload
      expect(ticket.snoozed_until).to be_nil
      expect(ticket.status).to eq('in_progress')
    end

    it 'does not let a customer snooze through the agent panel' do
      ticket = create(:escalated_ticket)
      signed_in[:user] = customer

      snooze(ticket, 1.day.from_now)

      expect(response).not_to have_http_status(:success)
      expect(response.location.to_s).not_to include('/support/agent/tickets')
      expect(ticket.reload.snoozed_until).to be_nil
    end

    it 'does not let an agent snooze a ticket outside their departments' do
      ticket = create(:escalated_ticket, department: create(:escalated_department))
      department_visibility!

      snooze(ticket, 1.day.from_now)

      expect(response).to have_http_status(:not_found)
      expect(Escalated::Ticket.unscoped.find(ticket.id).snoozed_until).to be_nil
    end

    it 'names the agent snooze routes in the route list' do
      expect(Escalated::RouteList::ENTRIES['escalated.agent.tickets.snooze'])
        .to eq(['agent/tickets/{id}/snooze', %w[POST]])
      expect(Escalated::RouteList::ENTRIES['escalated.agent.tickets.unsnooze'])
        .to eq(['agent/tickets/{id}/unsnooze', %w[POST]])
    end

    it 'maps the agent snooze routes to the ticket edit permission' do
      %w[snooze unsnooze].each do |action|
        expect(Escalated::Support::RoutePermissions.lookup('escalated/agent/tickets', action))
          .to eq(['ticket.edit'])
      end
    end

    context 'with roles and permissions on' do
      before do
        require 'escalated/seeds/permissions'
        allow(Escalated.configuration).to receive(:notification_channels).and_return([])
        Escalated::Seeds::Permissions.seed!
        Escalated.configuration.access = { roles_permissions: true }
      end

      after { Escalated.configuration.access = {} }

      def agent_with(permissions)
        role = Escalated::Role.create!(name: "Workspace #{SecureRandom.hex(3)}")
        role.permissions = Escalated::Permission.where(slug: permissions)
        role.users << agent
        agent
      end

      it 'refuses an agent without ticket.edit' do
        agent_with(%w[ticket.view])
        ticket = create(:escalated_ticket)

        snooze(ticket, 1.day.from_now)
        expect(response).to have_http_status(:forbidden)
        post "/support/agent/tickets/#{ticket.reference}/unsnooze"
        expect(response).to have_http_status(:forbidden)
        expect(ticket.reload.snoozed_until).to be_nil
      end

      it 'lets an agent with ticket.edit snooze' do
        agent_with(%w[ticket.view ticket.edit])
        ticket = create(:escalated_ticket)

        snooze(ticket, 1.day.from_now)

        expect(ticket.reload.snoozed_until).to be_present
      end
    end
  end
end
