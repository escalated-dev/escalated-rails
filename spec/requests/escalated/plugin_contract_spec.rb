# frozen_string_literal: true

require 'rails_helper'

# domain-model/plugin-contract.md: UI extensions are shared as
# `escalated.plugins`, the canonical events reach plugins' actions under their
# canonical names, and ctx ticket/reply queries filter only on the contract's
# keys.
RSpec.describe 'Plugin contract', type: :request do
  let(:admin) { create(:user, :admin, email: 'plugin-admin@example.test') }
  let(:agent) { create(:user, :agent, email: 'plugin-agent@example.test') }
  let(:requester) { create(:user, email: 'plugin-requester@example.test') }
  let(:viewer) { admin }
  let(:seen) { [] }
  let(:callbacks) { {} }

  before do
    Escalated.reset_plugins!
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
    allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_user) { viewer }
  end

  after { Escalated.reset_plugins! }

  def listen(*names)
    names.each do |name|
      Escalated.hooks.add_action(name) { |payload| seen << [name, payload] }
    end
  end

  def shared_plugins
    get '/support/agent'
    expect(response).to have_http_status(:ok)
    inertia_page['props']['escalated']['plugins']
  end

  def fake_sdk_bridge(manifests = {})
    bridge = instance_double(Escalated::Bridge::PluginBridge, booted?: true, manifests: manifests)
    allow(bridge).to receive(:dispatch_action)
    allow(Escalated).to receive(:plugin_bridge).and_return(bridge)
    bridge
  end

  describe 'escalated.plugins' do
    it 'shares Ruby plugin menus, widgets and slots in the shape the frontend reads' do
      Escalated.plugin_ui.add_menu_item(label: 'Billing', url: '/support/admin/billing', icon: 'cash',
                                        section: 'admin', position: 5)
      Escalated.plugin_ui.add_menu_item(label: 'Secret', url: '/x', permission: 'nobody-has-this', section: 'agent')
      Escalated.plugin_ui.add_dashboard_widget(id: 'acme.stats', title: 'Stats', component: 'StatsWidget',
                                               plugin: 'acme', width: 'half')
      Escalated.plugin_ui.add_page_component('ticket.show', 'sidebar',
                                             component: 'Panel', plugin: 'acme', data: { a: 1 }, position: 3)

      plugins = shared_plugins

      expect(plugins['menuItems'].pluck('label')).to eq(%w[Billing Secret])
      expect(plugins['menuItems'].first).to include('route' => '/support/admin/billing', 'icon' => 'cash',
                                                    'position' => 5, 'section' => 'admin')
      expect(plugins['dashboardWidgets'].first).to include('id' => 'acme.stats', 'title' => 'Stats',
                                                           'component' => 'StatsWidget', 'plugin' => 'acme')
      expect(plugins['pageComponents']['ticket.show.sidebar'].first)
        .to include('plugin' => 'acme', 'component' => 'Panel', 'data' => { 'a' => 1 }, 'position' => 3)
      expect(inertia_page['props']).not_to have_key('plugin_ui')
    end

    context 'when the viewer is an agent' do
      let(:viewer) { agent }

      it 'leaves out admin menu items and items whose permission the agent lacks, and sends {} when empty' do
        Escalated.plugin_ui.add_menu_item(label: 'Billing', url: '/support/admin/billing', section: 'admin')
        Escalated.plugin_ui.add_menu_item(label: 'Secret', url: '/x', permission: 'nobody-has-this',
                                          section: 'agent')

        # Permissions apply while roles & permissions is on (ADR 2026-10-29).
        Escalated.configuration.access = { roles_permissions: true }
        allow(Escalated::AccessControl).to receive(:permission_slugs).and_return(%w[ticket.view])
        expect(shared_plugins).to eq({})
      ensure
        Escalated.configuration.access = {}
      end

      it 'shows items with a permission to every agent while roles & permissions is off' do
        Escalated.plugin_ui.add_menu_item(label: 'Secret', url: '/x', permission: 'nobody-has-this',
                                          section: 'agent')

        expect(shared_plugins['menuItems'].pluck('label')).to eq(%w[Secret])
      end
    end

    it 'shares SDK plugin widgets and slots keyed by slug' do
      fake_sdk_bridge('@acme/plugin-crm' => {
                        'widgets' => [{ 'component' => 'CrmWidget', 'label' => 'CRM deals', 'order' => 2,
                                        'size' => 'full' }],
                        'components' => [{ 'page' => 'ticket.show', 'slot' => 'sidebar', 'component' => 'CrmPanel',
                                           'props' => { 'x' => 1 }, 'order' => 4 }]
                      })

      plugins = shared_plugins

      expect(plugins['dashboardWidgets']).to eq([{
                                                  'id' => 'acme--plugin-crm.CrmWidget', 'title' => 'CRM deals',
                                                  'component' => 'CrmWidget', 'plugin' => 'acme--plugin-crm',
                                                  'position' => 2, 'width' => 'full'
                                                }])
      expect(plugins['pageComponents']).to eq('ticket.show.sidebar' => [{
                                                'plugin' => 'acme--plugin-crm', 'component' => 'CrmPanel',
                                                'data' => { 'x' => 1 }, 'position' => 4
                                              }])
    end
  end

  describe 'widget badges' do
    let(:viewer) { agent }

    it 'asks the badge of each SDK widget with a badge function, as the viewer' do
      bridge = fake_sdk_bridge('@acme/plugin-crm' => {
                                 'widgets' => [
                                   { 'component' => 'Plain', 'label' => 'Plain', 'order' => 1, 'hasBadge' => false },
                                   { 'component' => 'Inbox', 'label' => 'Inbox', 'order' => 2, 'hasBadge' => true },
                                   { 'component' => 'Count', 'label' => 'Count', 'order' => 3, 'hasBadge' => true },
                                   { 'component' => 'Broken', 'label' => 'Broken', 'order' => 4, 'hasBadge' => true }
                                 ]
                               })
      allow(bridge).to receive(:badge) do |_plugin, component, user:|
        { 'Inbox' => "for #{user&.id}", 'Count' => 7 }[component]
      end

      widgets = shared_plugins['dashboardWidgets'].index_by { |w| w['component'] }

      expect(widgets['Inbox']['badge']).to eq("for #{agent.id}")
      expect(widgets['Count']['badge']).to eq(7)
      expect(widgets['Broken']).to include('badge' => nil)
      expect(widgets['Plain']).not_to have_key('badge')
      expect(bridge).to have_received(:badge).with('@acme/plugin-crm', anything, user: agent).exactly(3).times
    end
  end

  describe 'canonical events' do
    let(:viewer) { requester }

    it 'delivers ticket.created to Ruby and SDK plugins when a ticket is created over HTTP' do
      listen('ticket.created')
      bridge = fake_sdk_bridge

      post '/support/customer/tickets', params: { ticket: { subject: 'Plugin ticket', description: 'Body.' } }

      ticket = Escalated::Ticket.find_by!(subject: 'Plugin ticket')
      payload = seen.sole.last
      expect(payload).to include('id' => ticket.id, 'reference' => ticket.reference, 'subject' => 'Plugin ticket',
                                 'title' => 'Plugin ticket', 'status' => ticket.status.to_s)
      expect(payload).to include('department_id', 'assigned_to', 'requester_id', 'metadata', 'created_at')
      expect(payload['ticket']).to eq(payload.except('ticket'))
      expect(bridge).to have_received(:dispatch_action).with('ticket.created', hash_including('id' => ticket.id))
      expect(bridge).not_to have_received(:dispatch_action).with('ticket_created', anything)
    end

    it 'delivers reply.created with reply and ticket, and never a legacy name' do
      listen('reply.created', 'ticket.replied', 'note.created')
      ticket = create(:escalated_ticket, requester: requester)

      post "/support/customer/tickets/#{ticket.reference}/reply", params: { body: 'Hello plugin' }

      reply = Escalated::Reply.find_by!(body: 'Hello plugin')
      expect(seen.map(&:first)).to eq(['reply.created'])
      expect(seen.first.last).to include('id' => reply.id, 'ticket_id' => ticket.id, 'body' => 'Hello plugin',
                                         'is_internal' => false)
      expect(seen.first.last['reply']['id']).to eq(reply.id)
      expect(seen.first.last['ticket']['id']).to eq(ticket.id)
    end

    it 'does not fail the request when a plugin action raises' do
      Escalated.hooks.add_action('ticket.created') { |_| raise 'plugin broke' }
      bridge = fake_sdk_bridge
      allow(bridge).to receive(:dispatch_action).and_raise('runtime broke')

      post '/support/customer/tickets', params: { ticket: { subject: 'Still created', description: 'Body.' } }

      expect(response).to have_http_status(:redirect)
      expect(Escalated::Ticket.exists?(subject: 'Still created')).to be(true)
    end

    it 'delivers status changes with the old and new status' do
      listen('ticket.status_changed')
      ticket = create(:escalated_ticket, requester: requester, status: :open)

      Escalated::Services::TicketService.close(ticket, actor: agent)

      expect(seen.sole.last).to include('old_status' => 'open', 'new_status' => 'closed')
      expect(seen.sole.last['ticket']['id']).to eq(ticket.id)
    end
  end

  describe 'ctx' do
    let(:handler) do
      Escalated::Bridge::ContextHandler.new.tap { |h| h.current_plugin = 'acme' }
    end

    it 'filters tickets on contract keys' do
      mine = create(:escalated_ticket, requester: requester, priority: :high, assigned_to: agent.id)
      create(:escalated_ticket, requester: requester, priority: :low)

      rows = handler.call('ctx.tickets.query', { 'filter' => { 'assigned_to' => agent.id, 'priority' => 'high' } })
      expect(rows.pluck('id')).to eq([mine.id])
      rows = handler.call('ctx.tickets.query', { 'filter' => { 'reference' => mine.reference } })
      expect(rows.pluck('id')).to eq([mine.id])
    end

    it 'rejects ticket filter keys outside the contract and non-scalar values' do
      create(:escalated_ticket, requester: requester)

      ['guest_token', 'subject', 'requester_type', 'id) OR 1=1 --'].each do |key|
        expect { handler.call('ctx.tickets.query', { 'filter' => { key => 'x' } }) }.to raise_error(ArgumentError)
      end
      expect { handler.call('ctx.tickets.query', { 'filter' => { 'id' => [1, 2] } }) }.to raise_error(ArgumentError)
    end

    it 'maps is_internal and type for replies and rejects other keys' do
      ticket = create(:escalated_ticket, requester: requester)
      note = create(:escalated_reply, ticket: ticket, is_internal: true)
      create(:escalated_reply, ticket: ticket, is_internal: false)

      rows = handler.call('ctx.replies.query', { 'filter' => { 'ticket_id' => ticket.id, 'is_internal' => true } })
      expect(rows.pluck('id')).to eq([note.id])
      rows = handler.call('ctx.replies.query', { 'filter' => { 'ticket_id' => ticket.id, 'type' => 'note' } })
      expect(rows.pluck('id')).to eq([note.id])
      expect { handler.call('ctx.replies.query', { 'filter' => { 'body' => 'x' } }) }.to raise_error(ArgumentError)
    end

    it 'drops ctx.emit names that impersonate a canonical or lifecycle event' do
      bridge = instance_double(Escalated::Bridge::PluginBridge, dispatch_action: nil)
      handler.bridge = bridge

      %w[ticket.created plugin.activated ticket.replied acme.synced].each do |hook|
        handler.call('ctx.emit', { 'hook' => hook, 'data' => { 'n' => 1 } })
      end

      expect(bridge).to have_received(:dispatch_action).once
      expect(bridge).to have_received(:dispatch_action).with('acme.synced', { 'n' => 1 })
    end
  end
end
