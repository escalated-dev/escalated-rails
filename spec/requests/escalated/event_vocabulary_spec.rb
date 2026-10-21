# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'
require 'webmock'
require 'webmock/rspec/matchers'

# escalated-developer-context decisions/2026-10-21-event-vocabulary.md: one set
# of event names for webhooks and workflow triggers, with the legacy names still
# read from stored workflows and webhook subscriptions.
RSpec.describe 'Event vocabulary', type: :request do
  include ActiveJob::TestHelper
  include WebMock::API
  include WebMock::Matchers

  let(:admin) { create(:user, :admin, email: 'events-admin@example.test') }
  let(:agent) { create(:user, :agent) }
  let(:requester) { create(:user) }
  let(:hook_url) { 'https://hooks.example.test/escalated' }
  let(:sent) { [] }

  before do
    WebMock.enable!
    WebMock.disable_net_connect!
    allow(Addrinfo).to receive(:getaddrinfo).and_return([instance_double(Addrinfo, ip_address: '93.184.215.14')])
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
  end

  after do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def capture_webhook_names
    allow_any_instance_of(Escalated::Services::WebhookDispatcher) # rubocop:disable RSpec/AnyInstance
      .to receive(:dispatch_later) { |_, name, _data| sent << name }
  end

  def inertia_page_from(body)
    encoded = body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  def inertia_post(path, body)
    post path, params: body, headers: { 'X-Inertia' => 'true' }, as: :json
  end

  def workflow_body(trigger)
    { name: "On #{trigger}", trigger_event: trigger, conditions: { all: [] },
      actions: [{ type: 'change_priority', value: 'urgent' }], is_active: true }
  end

  # A workflow stored before the vocabulary changed, written straight to the
  # column so nothing on the save path rewrites it.
  def stored_workflow(trigger)
    workflow = create(:escalated_workflow, trigger_event: 'ticket.created', conditions: { 'all' => [] },
                                           actions: [{ 'type' => 'change_priority', 'value' => 'urgent' }])
    workflow.update_column(:trigger_event, trigger)
    workflow
  end

  def stored_webhook(events)
    webhook = Escalated::Webhook.create!(url: hook_url, events: ['ticket.created'], active: true)
    webhook.update_column(:events, events)
    webhook
  end

  describe 'webhooks' do
    it 'sends an internal note as note.created and a public reply as reply.created' do
      capture_webhook_names
      ticket = create(:escalated_ticket, requester: requester)

      Escalated::Services::TicketService.reply(ticket, body: 'Public.', author: agent, is_internal: false)
      Escalated::Services::TicketService.reply(ticket, body: 'Private.', author: agent, is_internal: true)

      expect(sent).to eq(%w[reply.created note.created])
    end

    it 'still delivers to a subscription stored under the legacy names' do
      webhook = stored_webhook(%w[internal_note.added tag.added ticket.untagged])
      stub_request(:post, hook_url).to_return(status: 200)
      ticket = create(:escalated_ticket, requester: requester)
      tag = create(:escalated_tag, name: 'vip')

      perform_enqueued_jobs do
        Escalated::Services::TicketService.reply(ticket, body: 'Private.', author: agent, is_internal: true)
        Escalated::Services::TicketService.add_tags(ticket, [tag.id], actor: agent)
        Escalated::Services::TicketService.remove_tags(ticket, [tag.id], actor: agent)
      end

      expect(webhook.deliveries.order(:id).pluck(:event)).to eq(%w[note.created ticket.tag_added ticket.tag_removed])
    end

    it 'offers only canonical names and shows a legacy subscription under its canonical name' do
      webhook = stored_webhook(%w[internal_note.added ticket.created])

      get "/support/admin/webhooks/#{webhook.id}/edit"

      props = inertia_page_from(response.body)['props']
      expect(props.dig('webhook', 'events')).to eq(%w[note.created ticket.created])
      expect(props['availableEvents']).to include('note.created', 'chat.started', 'chat.ended')
      expect(props['availableEvents'] & Escalated::EventNames::LEGACY.keys).to be_empty
    end

    it 'stores a legacy name posted by an old form as its canonical name' do
      post '/support/admin/webhooks', params: { url: hook_url, events: %w[internal_note.added], active: true },
                                      as: :json

      expect(Escalated::Webhook.last.events).to eq(%w[note.created])
    end

    it 'offers exactly the names this engine emits' do
      expect(Escalated::Services::WebhookDispatcher::AVAILABLE_EVENTS).to match_array(Escalated::EventNames::EMITTED)
      expect(Escalated::EventNames::EMITTED - Escalated::EventNames::CANONICAL).to be_empty
    end
  end

  describe 'workflow triggers' do
    it 'offers reply.created, and no legacy name, in the builder' do
      get '/support/admin/workflows/new'

      triggers = inertia_page_from(response.body).dig('props', 'trigger_events')
      expect(triggers).to include('reply.created', 'note.created', 'ticket.updated', 'chat.started', 'chat.ended')
      expect(triggers & Escalated::EventNames::LEGACY.keys).to be_empty
    end

    it 'runs a reply.created workflow on a public reply and not on an internal note' do
      inertia_post('/support/admin/workflows', workflow_body('reply.created'))
      expect(Escalated::Workflow.last.trigger_event).to eq('reply.created')

      noted = create(:escalated_ticket, requester: requester, priority: :low)
      Escalated::Services::TicketService.reply(noted, body: 'Private.', author: agent, is_internal: true)
      expect(noted.reload.priority).to eq('low')

      replied = create(:escalated_ticket, requester: requester, priority: :low)
      Escalated::Services::TicketService.reply(replied, body: 'Any news?', author: requester)
      expect(replied.reload.priority).to eq('urgent')
    end

    it 'keeps running a workflow stored with ticket.replied' do
      stored_workflow('ticket.replied')
      ticket = create(:escalated_ticket, requester: requester, priority: :low)

      Escalated::Services::TicketService.reply(ticket, body: 'Any news?', author: requester)

      expect(ticket.reload.priority).to eq('urgent')
    end

    it 'saves a legacy trigger posted by an old builder under its canonical name' do
      inertia_post('/support/admin/workflows', workflow_body('ticket.replied'))

      expect(Escalated::Workflow.last.trigger_event).to eq('reply.created')
    end

    it 'shows a stored legacy trigger under its canonical name' do
      workflow = stored_workflow('ticket.replied')

      get "/support/admin/workflows/#{workflow.id}/edit"

      expect(inertia_page_from(response.body).dig('props', 'workflow', 'trigger_event')).to eq('reply.created')
    end

    {
      'ticket.updated' => ->(t, a) { Escalated::Services::TicketService.update(t, { subject: 'New' }, actor: a) },
      'ticket.department_changed' => lambda { |t, a|
        Escalated::Services::TicketService.change_department(t, FactoryBot.create(:escalated_department), actor: a)
      },
      'ticket.resolved' => ->(t, a) { Escalated::Services::TicketService.transition_status(t, :resolved, actor: a) },
      'note.created' => lambda { |t, a|
        Escalated::Services::TicketService.reply(t, body: 'Note.', author: a, is_internal: true)
      }
    }.each do |trigger, change|
      it "runs a #{trigger} workflow" do
        inertia_post('/support/admin/workflows', workflow_body(trigger))
        expect(Escalated::Workflow.last&.trigger_event).to eq(trigger)
        ticket = create(:escalated_ticket, requester: requester, priority: :low)

        change.call(ticket, agent)

        expect(ticket.reload.priority).to eq('urgent')
      end
    end
  end

  describe 'live chat' do
    let(:session) do
      Escalated::Services::ChatSessionService.start_chat(name: 'Ann', email: 'ann@example.com', message: 'Hi')[:session]
    end

    before do
      allow(Escalated::TicketAccess).to receive(:eligible_agent?).and_return(true)
      allow(Escalated::Services::ChatRoutingService).to receive(:find_available_agent).and_return(nil)
    end

    it 'emits chat.started, chat.assigned, chat.message, chat.transferred and chat.ended' do
      capture_webhook_names
      other = create(:user, :agent)

      Escalated::Services::ChatSessionService.assign_agent(session, agent.id)
      Escalated::Services::ChatSessionService.send_message(session, body: 'Hello', author: agent)
      Escalated::Services::ChatSessionService.transfer_chat(session, other.id)
      Escalated::Services::ChatSessionService.end_chat(session)

      expect(sent & Escalated::EventNames::CHAT).to eq(
        %w[chat.started chat.assigned chat.message chat.transferred chat.ended]
      )
    end

    it 'runs chat.started workflows, and chat.ended ones stored under chat.session_ended' do
      inertia_post('/support/admin/workflows', workflow_body('chat.started'))
      stored_workflow('chat.session_ended').update!(actions: [{ 'type' => 'add_tag', 'value' => 'chat-done' }])

      ticket = session.ticket
      expect(ticket.reload.priority).to eq('urgent')

      Escalated::Services::ChatSessionService.end_chat(session)
      expect(ticket.reload.tags.pluck(:name)).to include('chat-done')
    end
  end

  describe Escalated::EventNames do
    it 'maps every legacy name in the decision to its canonical name' do
      expect(described_class::LEGACY).to eq(
        'ticket.replied' => 'reply.created',
        'internal_note.added' => 'note.created', 'internal_note.created' => 'note.created',
        'tag.added' => 'ticket.tag_added', 'ticket.tagged' => 'ticket.tag_added',
        'tag.removed' => 'ticket.tag_removed', 'ticket.untagged' => 'ticket.tag_removed',
        'chat.session_started' => 'chat.started', 'chat.session_ended' => 'chat.ended'
      )
      expect(described_class.canonical('ticket.replied')).to eq('reply.created')
      expect(described_class.canonical('ticket.created')).to eq('ticket.created')
      expect(described_class.aliases('reply.created')).to contain_exactly('reply.created', 'ticket.replied')
    end
  end
end
