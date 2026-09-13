# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The Workflows admin screen as the shared frontend drives it, per
# escalated-developer-context/domain-model/workflow-admin-contract.md.
#
# Every request here sends the contract's body -- top-level keys, conditions as
# { all | any }, actions as { type, value } -- rather than the shape the engine
# stores. A suite that posts the backend's own field names stays green while the
# builder cannot save anything, which is exactly how this surface broke before.
RSpec.describe 'Admin workflows', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-workflows@example.test') }
  let(:department) { create(:escalated_department) }
  let(:requester) { create(:user) }

  let(:contract_body) do
    {
      name: 'Route refunds to billing',
      description: nil,
      trigger_event: 'ticket.created',
      conditions: { all: [{ field: 'subject', operator: 'contains', value: 'refund' }] },
      actions: [
        { type: 'change_priority', value: 'high' },
        { type: 'set_department', value: department.id.to_s }
      ],
      is_active: true
    }
  end

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    sign_in_as(admin)
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  # What an Inertia form visit sends: a JSON body and the X-Inertia header.
  def inertia_visit(method, path, body = nil, referer: nil)
    headers = { 'X-Inertia' => 'true' }
    headers['Referer'] = "http://www.example.com#{referer}" if referer
    send(method, path, params: body, headers: headers, as: :json)
  end

  # Inertia HTML responses JSON-encode the page inside data-page="..." (HTML-escaped).
  def inertia_page_from(body)
    encoded = body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  def create_ticket(subject)
    Escalated::Services::TicketService.create(subject: subject, description: 'From the request spec.',
                                              requester: requester)
  end

  describe 'creating' do
    it 'stores the contract body with the same trigger, conditions and actions' do
      expect do
        inertia_visit(:post, '/support/admin/workflows', contract_body)
      end.to change(Escalated::Workflow, :count).by(1)

      expect(response).to redirect_to('/support/admin/workflows')
      workflow = Escalated::Workflow.last
      expect(workflow.name).to eq('Route refunds to billing')
      expect(workflow.trigger_event).to eq('ticket.created')
      expect(workflow.conditions).to eq(contract_body[:conditions].deep_stringify_keys)
      expect(workflow.actions).to eq(contract_body[:actions].map(&:deep_stringify_keys))
      expect(workflow.is_active).to be(true)

      follow_redirect!
      expect(inertia_page_from(response.body).dig('props', 'flash', 'notice')).to be_present
    end

    it 'accepts the top-level body when the host app does not wrap JSON parameters' do
      # ParamsWrapper copies JSON keys under `workflow` only when the host app
      # enables it (Rails' load_defaults 7.0+). The contract cannot depend on that.
      # rubocop:disable-next RSpec/AnyInstance
      allow_any_instance_of(Escalated::Admin::WorkflowsController).to receive(:_wrapper_enabled?).and_return(false)

      expect do
        inertia_visit(:post, '/support/admin/workflows', contract_body)
      end.to change(Escalated::Workflow, :count).by(1)
      expect(Escalated::Workflow.last.actions).to eq(contract_body[:actions].map(&:deep_stringify_keys))
    end

    it 'treats omitted conditions as matching every ticket' do
      inertia_visit(:post, '/support/admin/workflows', contract_body.except(:conditions))

      expect(Escalated::Workflow.last&.conditions).to eq('all' => [])
    end

    it 'accepts a trigger this backend fires that the old list left out' do
      expect do
        inertia_visit(:post, '/support/admin/workflows', contract_body.merge(trigger_event: 'ticket.replied'))
      end.to change(Escalated::Workflow, :count).by(1)
    end

    it 'refuses a workflow with no actions and hands the errors back through the session' do
      expect do
        inertia_visit(:post, '/support/admin/workflows', contract_body.merge(actions: []),
                      referer: '/support/admin/workflows/new')
      end.not_to change(Escalated::Workflow, :count)

      expect(response).to redirect_to('/support/admin/workflows/new')
      follow_redirect!
      expect(inertia_page_from(response.body).dig('props', 'errors', 'actions')).to be_present
    end

    it 'refuses a trigger this backend never fires' do
      expect do
        inertia_visit(:post, '/support/admin/workflows', contract_body.merge(trigger_event: 'ticket.tagged'),
                      referer: '/support/admin/workflows/new')
      end.not_to change(Escalated::Workflow, :count)

      follow_redirect!
      expect(inertia_page_from(response.body).dig('props', 'errors', 'trigger_event')).to be_present
    end

    it 'refuses conditions that carry both all and any' do
      conditions = { all: [], any: [{ field: 'status', operator: 'equals', value: 'open' }] }

      expect do
        inertia_visit(:post, '/support/admin/workflows', contract_body.merge(conditions: conditions),
                      referer: '/support/admin/workflows/new')
      end.not_to change(Escalated::Workflow, :count)

      follow_redirect!
      expect(inertia_page_from(response.body).dig('props', 'errors', 'conditions')).to be_present
    end
  end

  describe 'updating' do
    it 'replaces the stored workflow with the contract body' do
      workflow = create(:escalated_workflow, name: 'Old name', trigger_event: 'ticket.assigned',
                                             conditions: { 'any' => [] },
                                             actions: [{ 'type' => 'change_status', 'value' => 'open' }])

      inertia_visit(:put, "/support/admin/workflows/#{workflow.id}", contract_body)

      expect(response).to redirect_to('/support/admin/workflows')
      workflow.reload
      expect(workflow.name).to eq('Route refunds to billing')
      expect(workflow.trigger_event).to eq('ticket.created')
      expect(workflow.conditions).to eq(contract_body[:conditions].deep_stringify_keys)
      expect(workflow.actions).to eq(contract_body[:actions].map(&:deep_stringify_keys))
    end
  end

  describe 'running a workflow saved through the endpoint' do
    it 'runs its actions when its trigger fires on a matching ticket, and only then' do
      inertia_visit(:post, '/support/admin/workflows', contract_body)
      expect(Escalated::Workflow.count).to eq(1)

      matching = create_ticket('Where is my refund?')
      other = create_ticket('Password reset')

      expect(matching.reload.priority).to eq('high')
      expect(matching.department_id).to eq(department.id)
      expect(other.reload.priority).not_to eq('high')
      expect(other.department_id).not_to eq(department.id)
    end

    it 'runs a ticket.replied workflow when a reply is added' do
      inertia_visit(:post, '/support/admin/workflows',
                    contract_body.merge(trigger_event: 'ticket.replied', conditions: { all: [] },
                                        actions: [{ type: 'change_priority', value: 'urgent' }]))
      expect(Escalated::Workflow.count).to eq(1)

      ticket = create(:escalated_ticket, requester: requester)
      Escalated::Services::TicketService.reply(ticket, body: 'Any update?', author: requester)

      expect(ticket.reload.priority).to eq('urgent')
    end

    it 'keeps running a workflow stored with a flat list of conditions' do
      create(:escalated_workflow,
             trigger_event: 'ticket.created',
             conditions: [{ 'field' => 'subject', 'operator' => 'contains', 'value' => 'refund' }],
             actions: [{ 'type' => 'change_priority', 'value' => 'urgent' }])

      expect(create_ticket('Please refund me').reload.priority).to eq('urgent')
    end
  end

  describe 'pages' do
    it 'renders the create form with the option lists and a null workflow' do
      get '/support/admin/workflows/new'

      expect(response).to have_http_status(:ok)
      page = inertia_page_from(response.body)
      expect(page['component']).to eq('Escalated/Admin/Workflows/Form')
      props = page['props']
      expect(props).to include('workflow' => nil)
      expect(props['trigger_events']).to match_array(
        %w[ticket.created ticket.status_changed ticket.assigned ticket.priority_changed
           ticket.replied ticket.escalated sla.breached sla.warning]
      )
      expect(props['action_types']).to match_array(
        %w[change_status change_priority add_tag remove_tag set_department assign_agent add_note
           insert_canned_reply add_follower send_webhook set_type]
      )
      expect(props['operators']).to include(
        'equals', 'not_equals', 'contains', 'not_contains', 'starts_with', 'ends_with', 'greater_than',
        'less_than', 'greater_or_equal', 'less_or_equal', 'is_empty', 'is_not_empty'
      )
    end

    it 'renders the edit form with the stored workflow object' do
      workflow = create(:escalated_workflow)

      get "/support/admin/workflows/#{workflow.id}/edit"

      props = inertia_page_from(response.body)['props']
      expect(props['workflow']).to include(
        'id' => workflow.id, 'name' => workflow.name, 'trigger_event' => 'ticket.created',
        'conditions' => workflow.conditions, 'actions' => workflow.actions,
        'is_active' => true, 'position' => 0
      )
      expect(props['trigger_events']).to be_present
      expect(props['action_types']).to be_present
    end

    it 'renders the index with workflow objects' do
      workflow = create(:escalated_workflow)

      get '/support/admin/workflows'

      page = inertia_page_from(response.body)
      expect(page['component']).to eq('Escalated/Admin/Workflows/Index')
      expect(page.dig('props', 'workflows').sole).to include(
        'id' => workflow.id, 'trigger_event' => 'ticket.created', 'is_active' => true, 'position' => 0
      )
    end
  end

  describe 'enabling, reordering and deleting from the index' do
    it 'toggles with a POST and redirects to the index' do
      workflow = create(:escalated_workflow, is_active: true)

      inertia_visit(:post, "/support/admin/workflows/#{workflow.id}/toggle")

      expect(response).to redirect_to('/support/admin/workflows')
      expect(workflow.reload.is_active).to be(false)
    end

    it 'still toggles a stored workflow whose trigger predates the current list' do
      workflow = build(:escalated_workflow, trigger_event: 'ticket.updated', is_active: true)
      workflow.save!(validate: false)

      inertia_visit(:post, "/support/admin/workflows/#{workflow.id}/toggle")

      expect(response).to redirect_to('/support/admin/workflows')
      expect(workflow.reload.is_active).to be(false)
    end

    it 'reorders from workflow_ids' do
      first, second, third = create_list(:escalated_workflow, 3)

      inertia_visit(:post, '/support/admin/workflows/reorder', { workflow_ids: [third.id, first.id, second.id] })

      expect([third, first, second].map { |w| w.reload.position }).to eq([0, 1, 2])
    end

    it 'deletes with a DELETE and redirects to the index' do
      workflow = create(:escalated_workflow)

      inertia_visit(:delete, "/support/admin/workflows/#{workflow.id}")

      expect(response).to redirect_to('/support/admin/workflows')
      expect(Escalated::Workflow.exists?(workflow.id)).to be(false)
    end
  end
end
