# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The agent panel's data (ADR 2026-11-05-agent-panel-data): the agent's own
# status, knowledge-base search, per-agent unread markers, customer presence
# and the notifications feed, through the real routes.
RSpec.describe 'Agent panel data', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:agent) { create(:user, :agent, email: 'panelagent@example.test') }
  let(:other) { create(:user, :agent, email: 'panel-other@example.test') }
  let(:admin) { create(:user, :admin, email: 'panel-admin@example.test') }
  let(:customer) { create(:user, email: 'panel-customer@example.test') }
  let(:signed_in) { { user: agent } }
  let(:json_headers) { { 'ACCEPT' => 'application/json' } }

  around do |example|
    previous = Escalated.configuration.agent_inbox_cache_seconds
    Escalated.configuration.agent_inbox_cache_seconds = 0
    example.run
  ensure
    Escalated.configuration.agent_inbox_cache_seconds = previous
  end

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user) { signed_in[:user] }
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
  end

  def as(user)
    signed_in[:user] = user
  end

  def page_for(path)
    get path
    expect(response).to have_http_status(:ok)
    encoded = response.body[%r{data-page="(.+?)"></div>}m, 1]
    JSON.parse(CGI.unescapeHTML(encoded))
  end

  def rows(user = agent)
    as(user)
    page_for('/support/agent/tickets')['props']['tickets']['data'].index_by { |row| row['reference'] }
  end

  def open_ticket(ticket, user = agent)
    as(user)
    page_for("/support/agent/tickets/#{ticket.reference}")
  end

  def body
    response.parsed_body
  end

  def customer_ticket(attributes = {})
    create(:escalated_ticket, { requester: customer }.merge(attributes))
  end

  describe 'agent status' do
    %i[put post].each do |verb|
      it "lets an agent set their own status with #{verb.upcase}" do
        send(verb, '/support/agent/status', params: { status: 'away' }, headers: json_headers)

        expect(response).to have_http_status(:ok)
        expect(body).to eq('agent_status' => 'away')
        expect(Escalated::AgentProfile.find_by(user_id: agent.id).chat_status).to eq('away')
      end
    end

    it 'is the status live-chat routing reads' do
      put '/support/agent/status', params: { status: 'online' }, headers: json_headers
      expect(Escalated::AgentProfile.chat_online.pluck(:user_id)).to eq([agent.id])
    end

    it 'lets a light agent set their status' do
      create(:escalated_agent_profile, :light, user: agent)
      put '/support/agent/status', params: { status: 'away' }, headers: json_headers
      expect(Escalated::AgentProfile.find_by(user_id: agent.id).chat_status).to eq('away')
    end

    it 'rejects a status outside the allowed values' do
      put '/support/agent/status', params: { status: 'busy' }, headers: json_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(Escalated::AgentProfile.where(user_id: agent.id)).not_to exist
    end

    it 'is refused to a non-agent' do
      as(customer)
      put '/support/agent/status', params: { status: 'online' }, headers: json_headers
      expect(response).to have_http_status(:redirect)
      expect(Escalated::AgentProfile.where(user_id: customer.id)).not_to exist
    end

    it 'redirects an Inertia visit back' do
      put '/support/agent/status', params: { status: 'away' },
                                   headers: { 'X-Inertia' => 'true', 'HTTP_REFERER' => '/support/agent/tickets' }
      expect(response).to redirect_to('/support/agent/tickets')
    end

    it 'keeps the admin chat status route as an alias for the same field' do
      post '/support/admin/chat/update_status', params: { status: 'online' }, headers: json_headers
      expect(body).to include('status' => 'online', 'agent_status' => 'online')
      expect(Escalated::AgentStatus.for(agent)).to eq('online')
    end

    it 'shares agent_status and agent_statuses with agents only' do
      shared = page_for('/support/agent/tickets')['props']['escalated']
      expect(shared['agent_status']).to eq('offline')
      expect(shared['agent_statuses']).to eq(%w[online away offline])

      as(customer)
      shared = page_for('/support/customer/tickets')['props']['escalated']
      expect(shared).not_to have_key('agent_status')
      expect(shared).not_to have_key('agent_statuses')
      expect(shared).not_to have_key('notifications')
    end
  end

  describe 'knowledge-base search' do
    def article(attributes = {})
      create(:escalated_article, :published, :without_category, { body: '<p>Body</p>' }.merge(attributes))
    end

    def search(query)
      get "/support/agent/kb/search?#{query}", headers: json_headers
    end

    it 'returns matching published articles with the contract fields' do
      category = create(:escalated_article_category, name: 'Billing')
      found = article(title: 'Resetting your password', slug: 'resetting-your-password', category: category,
                      body: '<p>Open <strong>Settings</strong> and choose Reset.</p>')

      search('q=password')

      expect(response).to have_http_status(:ok)
      expect(body).to eq('data' => [{
                           'id' => found.id,
                           'title' => 'Resetting your password',
                           'excerpt' => 'Open Settings and choose Reset.',
                           'url' => 'http://www.example.com/support/customer/kb/resetting-your-password',
                           'category' => { 'id' => category.id, 'name' => 'Billing' },
                           'updated_at' => found.updated_at.iso8601
                         }])
    end

    it 'never returns drafts' do
      create(:escalated_article, :without_category, title: 'Draft about refunds')
      article(title: 'Refunds explained')
      search('q=refunds')
      expect(body['data'].pluck('title')).to eq(['Refunds explained'])
    end

    it 'ranks title matches before body matches, then the most recently updated' do
      body_only = article(title: 'Getting started', body: 'How invoices work', updated_at: 1.hour.ago)
      older = article(title: 'Invoices (old)', updated_at: 3.days.ago)
      newer = article(title: 'Invoices (new)', updated_at: 2.days.ago)

      search('q=invoices')
      expect(body['data'].pluck('id')).to eq([newer.id, older.id, body_only.id])
    end

    it 'ignores case' do
      found = article(title: 'Resetting your Password')
      search('q=PASSWORD')
      expect(body['data'].pluck('id')).to eq([found.id])
    end

    ['%25%25', '__', '0%25', 'a_b'].each do |q|
      it "takes LIKE wildcards literally (#{q})" do
        article(title: 'Plain title', body: 'Nothing special')
        literal = article(title: 'Codes: 100%% off, a_b and x__y', body: 'x')
        search("q=#{q}")
        expect(body['data'].pluck('id')).to eq([literal.id])
      end
    end

    it 'caps the number of results' do
      25.times { |i| article(title: "Shipping guide #{i}") }
      search('q=shipping')
      expect(body['data'].size).to eq(10)
      search('q=shipping&limit=20')
      expect(body['data'].size).to eq(20)
      search('q=shipping&limit=21')
      expect(response).to have_http_status(:unprocessable_content)
    end

    ['q=', 'q=a', "q=#{'a' * 201}", ''].each do |query|
      it "validates the query (#{query[0, 12]})" do
        search(query)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it 'answers 404 while the knowledge base is off' do
      Escalated::EscalatedSetting.set('knowledge_base_enabled', '0')
      search('q=password')
      expect(response).to have_http_status(:not_found)
    end

    it 'also escapes the customer knowledge base search' do
      article(title: 'Plain title')
      expect(Escalated::Article.published.search('%').count).to eq(0)
    end
  end

  describe 'unread tickets' do
    it 'shows a new ticket as unread until the agent opens it' do
      ticket = customer_ticket
      expect(rows[ticket.reference]['is_unread']).to be(true)

      show = open_ticket(ticket)
      expect(show['props']['ticket']['is_unread']).to be(false)
      expect(rows[ticket.reference]['is_unread']).to be(false)
    end

    it 'keeps read markers per agent' do
      ticket = customer_ticket
      open_ticket(ticket)
      expect(rows(agent)[ticket.reference]['is_unread']).to be(false)
      expect(rows(other)[ticket.reference]['is_unread']).to be(true)
    end

    { 'the requester' => :customer, 'a guest' => nil, 'a contact' => :contact }.each do |who, author|
      it "makes a read ticket unread again on a reply from #{who}" do
        ticket = customer_ticket
        open_ticket(ticket)
        writer = case author
                 when :customer then customer
                 when :contact then create(:escalated_contact)
                 end
        travel(1.minute) { create(:escalated_reply, ticket: ticket, author: writer, is_internal: false) }
        expect(rows[ticket.reference]['is_unread']).to be(true)
      end
    end

    it 'does not make a ticket unread for agent replies, notes or system replies' do
      ticket = customer_ticket
      open_ticket(ticket)
      travel(1.minute) do
        create(:escalated_reply, ticket: ticket, author: agent, is_internal: false)
        create(:escalated_reply, ticket: ticket, author: other, is_internal: false)
        create(:escalated_reply, ticket: ticket, author: customer, is_internal: true)
        create(:escalated_reply, ticket: ticket, author: nil, is_internal: false, is_system: true)
        ticket.replies.create!(body: 'Canned', is_internal: false, system_authored: true)
      end
      expect(rows[ticket.reference]['is_unread']).to be(false)
    end

    it 'leaves imported tickets read' do
      ticket = Escalated::Support::ImportContext.suppress { customer_ticket }
      expect(rows[ticket.reference]['is_unread']).to be(false)
    end

    it 'marks a ticket read and unread through the agent routes' do
      ticket = customer_ticket
      post "/support/agent/tickets/#{ticket.reference}/read", headers: json_headers
      expect(body).to eq('is_unread' => false)
      expect(rows[ticket.reference]['is_unread']).to be(false)

      post "/support/agent/tickets/#{ticket.reference}/unread", headers: json_headers
      expect(body).to eq('is_unread' => true)
      expect(rows[ticket.reference]['is_unread']).to be(true)

      post "/support/agent/tickets/#{ticket.reference}/read",
           headers: { 'X-Inertia' => 'true', 'HTTP_REFERER' => '/support/agent/tickets' }
      expect(response).to redirect_to('/support/agent/tickets')
    end

    it 'marks tickets read and unread in bulk' do
      first = customer_ticket
      second = customer_ticket
      post '/support/agent/tickets/bulk', params: { ticket_ids: [first.id, second.id], action: 'mark_read' }
      flags = rows
      expect([flags[first.reference]['is_unread'], flags[second.reference]['is_unread']]).to eq([false, false])

      post '/support/agent/tickets/bulk', params: { ticket_ids: [first.id], action: 'mark_unread' }
      flags = rows
      expect([flags[first.reference]['is_unread'], flags[second.reference]['is_unread']]).to eq([true, false])
    end

    it 'counts unread open tickets per queue in inbox.unread' do
      mine = customer_ticket(assigned_to: agent.id)
      customer_ticket(assigned_to: agent.id)
      unassigned = customer_ticket
      customer_ticket(status: :resolved, resolved_at: Time.current)
      open_ticket(mine)
      open_ticket(unassigned)

      inbox = page_for('/support/agent/tickets')['props']['inbox']
      expect(inbox['unread']).to eq('mine' => 1, 'unassigned' => 0, 'all' => 1)
    end

    it 'only counts and marks tickets the agent may see' do
      allow(Escalated.configuration).to receive(:visibility).and_return('department')
      support = create(:escalated_department)
      sales = create(:escalated_department)
      support.agents << agent
      visible = customer_ticket(department: support)
      hidden = customer_ticket(department: sales)

      expect(page_for('/support/agent/tickets')['props']['inbox']['unread']['all']).to eq(1)

      post "/support/agent/tickets/#{hidden.reference}/read", headers: json_headers
      expect(response).to have_http_status(:not_found)
      post '/support/agent/tickets/bulk', params: { ticket_ids: [hidden.id, visible.id], action: 'mark_read' }
      expect(Escalated::TicketRead.pluck(:ticket_id)).to eq([visible.id])
    end

    it 'removes read markers with the ticket' do
      ticket = customer_ticket
      open_ticket(ticket)
      ticket.destroy!
      expect(Escalated::TicketRead.where(ticket_id: ticket.id)).not_to exist
    end
  end

  describe 'customer presence' do
    def visit_portal
      as(customer)
      get '/support/customer/tickets'
      expect(response).to have_http_status(:ok)
    end

    it 'shows a customer as online while the portal saw them within the window' do
      freeze_time do
        ticket = customer_ticket
        expect(rows[ticket.reference].slice('requester_online', 'requester_last_seen_at'))
          .to eq('requester_online' => false, 'requester_last_seen_at' => nil)

        visit_portal
        expect(rows[ticket.reference].slice('requester_online', 'requester_last_seen_at'))
          .to eq('requester_online' => true, 'requester_last_seen_at' => Time.current.iso8601)

        travel(121.seconds)
        expect(rows[ticket.reference]['requester_online']).to be(false)
      end
    end

    it 'uses the configured online window' do
      allow(Escalated.configuration).to receive(:presence_online_window_seconds).and_return(600)
      ticket = customer_ticket
      visit_portal
      travel(9.minutes) { expect(rows[ticket.reference]['requester_online']).to be(true) }
    end

    it 'writes at most once per customer every 30 seconds' do
      start = Time.zone.local(2026, 11, 5, 10, 0, 0)
      travel_to(start)
      visit_portal
      travel_to(start + 20.seconds)
      visit_portal
      expect(Escalated::CustomerPresence.sole.last_seen_at).to eq(start)

      travel_to(start + 31.seconds)
      visit_portal
      expect(Escalated::CustomerPresence.sole.last_seen_at).to eq(start + 31.seconds)
    ensure
      travel_back
    end

    it 'records a guest from the widget chat' do
      Escalated::EscalatedSetting.set('widget_enabled', '1')
      contact = create(:escalated_contact)
      ticket = create(:escalated_ticket, requester: nil, contact: contact, guest_email: contact.email)
      token, digest, expires = Escalated::ChatSession.issue_visitor_token
      create(:escalated_chat_session, ticket: ticket, customer_session_id: digest, customer_token_expires_at: expires)

      get "/support/widget/chat/#{token}/messages", headers: json_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('requester_online')

      expect(rows[ticket.reference]['requester_online']).to be(true)
    end

    it 'sends presence on the agent ticket page' do
      ticket = customer_ticket
      visit_portal
      expect(open_ticket(ticket)['props']['ticket']['requester_online']).to be(true)
    end

    it 'does not record staff browsing the customer portal' do
      get '/support/customer/tickets'
      expect(Escalated::CustomerPresence.count).to eq(0)
    end

    it 'never shows presence to customers' do
      ticket = customer_ticket
      visit_portal
      get "/support/customer/tickets/#{ticket.reference}"
      expect(response.body).not_to include('requester_online')
      expect(response.body).not_to include('requester_last_seen_at')
    end
  end

  describe 'notifications' do
    def feed(query = '')
      get "/support/agent/notifications#{query}", headers: json_headers
      expect(response).to have_http_status(:ok)
      body
    end

    it 'lists a ticket assignment with the contract shape' do
      freeze_time do
        ticket = customer_ticket(subject: 'Printer on fire')
        Escalated::Services::TicketService.assign(ticket, agent, actor: admin)
        row = Escalated::AgentNotification.sole

        expect(feed).to eq(
          'data' => [{
            'id' => row.id,
            'type' => 'ticket_assigned',
            'title' => "#{ticket.reference} was assigned to you",
            'body' => 'Printer on fire',
            'ticket' => { 'id' => ticket.id, 'reference' => ticket.reference, 'subject' => 'Printer on fire' },
            'url' => "/support/agent/tickets/#{ticket.reference}",
            'created_at' => Time.current.iso8601,
            'read_at' => nil
          }],
          'meta' => { 'current_page' => 1, 'last_page' => 1, 'per_page' => 20, 'total' => 1 },
          'unread_count' => 1
        )
      end
    end

    it 'does not notify an agent who assigns a ticket to themselves' do
      allow(Escalated.configuration).to receive(:notification_channels).and_return([:email])
      Escalated::Services::TicketService.assign(customer_ticket, agent, actor: agent)
      expect(feed['data']).to eq([])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.dig('arguments', 1) })
        .not_to include('ticket_assigned')
    end

    it "notifies the assignee of a customer reply but not of another agent's" do
      ticket = customer_ticket(assigned_to: agent.id)
      Escalated::Services::TicketService.reply(ticket, body: 'From a colleague', author: other, is_internal: false)
      expect(feed['data']).to eq([])

      Escalated::Services::TicketService.reply(ticket, body: 'From the customer', author: customer, is_internal: false)
      expect(feed['data'].map { |item| [item['type'], item['title']] })
        .to eq([['ticket_reply', "New reply on #{ticket.reference}"]])
    end

    it 'notifies a mentioned agent of an internal note' do
      ticket = customer_ticket
      create(:escalated_reply, ticket: ticket, author: other, is_internal: true,
                               body: "Can you look, @#{agent.email.split('@').first}?")
      item = feed['data'].sole
      expect(item['type']).to eq('mention')
      expect(item['title']).to eq("#{other.name} mentioned you on #{ticket.reference}")
    end

    it 'notifies the assignee of SLA warnings and breaches' do
      ticket = customer_ticket(assigned_to: agent.id)
      Escalated::Services::NotificationService.dispatch(:sla_warning, ticket: ticket, warning_type: 'first_response')
      Escalated::Services::NotificationService.dispatch(:sla_breached, ticket: ticket, breach_type: 'resolution')

      items = feed['data']
      expect(items.pluck('type')).to contain_exactly('sla_warning', 'sla_breached')
      expect(items.find { |i| i['type'] == 'sla_warning' }['title']).to eq("SLA due soon on #{ticket.reference}")
    end

    it 'notifies the receiving agent of a chat transfer, not the sender' do
      ticket = customer_ticket
      Escalated::Services::NotificationService.dispatch(:chat_transferred, ticket: ticket, chat_session_id: 7,
                                                                           previous_agent_id: other.id.to_s,
                                                                           agent_id: agent.id.to_s)
      expect(feed['data'].pluck('type')).to eq(['chat_transferred'])
      as(other)
      expect(feed['data']).to eq([])
    end

    it 'pages newest first, filters to unread and marks read' do
      3.times do |i|
        travel_to(Time.zone.local(2026, 11, 5, 9, i)) do
          Escalated::Services::TicketService.assign(customer_ticket(subject: "Ticket #{i + 1}"), agent, actor: admin)
        end
      end

      page = feed('?per_page=2')
      expect(page['data'].pluck('body')).to eq(['Ticket 3', 'Ticket 2'])
      expect(page['meta']).to eq('current_page' => 1, 'last_page' => 2, 'per_page' => 2, 'total' => 3)

      post "/support/agent/notifications/#{page['data'][0]['id']}/read", headers: json_headers
      expect(body).to eq('unread_count' => 2)
      expect(feed('?unread=1')['data'].pluck('body')).to eq(['Ticket 2', 'Ticket 1'])

      get '/support/agent/notifications?per_page=51', headers: json_headers
      expect(response).to have_http_status(:unprocessable_content)

      post '/support/agent/notifications/read-all', headers: json_headers
      expect(body).to eq('unread_count' => 0)
      expect(feed['unread_count']).to eq(0)
    end

    it "does not mark another agent's notification read" do
      Escalated::Services::TicketService.assign(customer_ticket, other, actor: admin)
      post "/support/agent/notifications/#{Escalated::AgentNotification.sole.id}/read", headers: json_headers
      expect(response).to have_http_status(:not_found)
      expect(Escalated::AgentNotification.sole.read_at).to be_nil
    end

    it 'redacts tickets the agent can no longer view' do
      allow(Escalated.configuration).to receive(:visibility).and_return('department')
      support = create(:escalated_department)
      billing = create(:escalated_department)
      support.agents << agent
      ticket = customer_ticket(department: support, subject: 'Secret subject')
      Escalated::Services::TicketService.assign(ticket, agent, actor: admin)
      Escalated::Ticket.unscoped.where(id: ticket.id).update_all(department_id: billing.id)

      item = feed['data'].sole
      expect(item).to include('type' => 'ticket_assigned', 'title' => 'A ticket you can no longer view',
                              'body' => nil, 'ticket' => nil, 'url' => nil)
      expect(item.to_json).not_to include('Secret subject')
    end

    it 'shares the unread count with agents' do
      Escalated::Services::TicketService.assign(customer_ticket, agent, actor: admin)
      expect(page_for('/support/agent/tickets')['props']['escalated']['notifications']).to eq('unread_count' => 1)
    end

    it 'is off when agent notifications are switched off' do
      allow(Escalated.configuration).to receive(:agent_notifications).and_return(false)
      get '/support/agent/notifications', headers: json_headers
      expect(response).to have_http_status(:not_found)
      post '/support/agent/notifications/read-all', headers: json_headers
      expect(response).to have_http_status(:not_found)
      expect(page_for('/support/agent/tickets')['props']['escalated']).not_to have_key('notifications')
    end

    it 'is for agents only' do
      as(customer)
      get '/support/agent/notifications', headers: json_headers
      expect(response).not_to have_http_status(:ok)
    end

    it 'broadcasts a new notification on the agent channel while broadcasting is on' do
      allow(Escalated::Broadcasting).to receive(:enabled?).and_return(true)
      allow(ActionCable.server).to receive(:broadcast)
      ticket = customer_ticket
      Escalated::Services::TicketService.assign(ticket, agent, actor: admin)

      expect(ActionCable.server).to have_received(:broadcast).with(
        "escalated_agent_#{agent.id}",
        hash_including(event: 'notification.created',
                       data: hash_including(type: 'ticket_assigned',
                                            ticket: hash_including(reference: ticket.reference)))
      )
    end
  end
end
