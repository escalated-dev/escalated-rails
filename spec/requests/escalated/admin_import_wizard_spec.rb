# frozen_string_literal: true

require 'rails_helper'

# The admin Import wizard the shared frontend drives
# (src/pages/Admin/Import/{Index,Connect,Mapping,Review,Progress}.vue), on
# escalated-laravel's routes and props (Admin\ImportController,
# ImportService, ImportJob, ImportContext).
#
# The source is FakeImportAdapter, registered through the "import.adapters"
# filter the way a plugin registers a Zendesk or Freshdesk adapter.
RSpec.describe 'Admin import wizard', type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin, name: 'Ada Admin', email: 'admin.importer@example.test') }
  let(:adapter) { FakeImportAdapter.new }
  let(:filter) { ->(adapters) { adapters + [adapter] } }
  let(:credentials) { { 'subdomain' => 'acme', 'api_token' => FakeImportAdapter::TOKEN } }

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
    Escalated.hooks.add_filter('import.adapters', filter)
  end

  after do
    Escalated.hooks.remove_filter('import.adapters', filter)
    clear_enqueued_jobs
  end

  def inertia_json
    expect(response.headers['X-Inertia']).to eq('true')
    response.parsed_body
  end

  def connect!
    post '/support/admin/import/fakedesk/test-connection', params: { credentials: credentials }, as: :json
    expect(response.parsed_body).to eq('success' => true)
  end

  def field_mappings
    { 'tickets' => { 'subject' => 'title', 'state' => 'status' } }
  end

  def start!
    connect!
    inertia_visit(:post, '/support/admin/import/fakedesk/start', { field_mappings: field_mappings })
    Escalated::ImportJob.order(:created_at).last
  end

  describe 'Index' do
    it 'lists the registered adapters and the recent jobs' do
      job = Escalated::ImportJob.create!(platform: 'fakedesk', status: 'completed', credentials: credentials)

      page = expect_screen('/support/admin/import', 'Escalated/Admin/Import/Index')

      expect(page.dig('props', 'adapters')).to eq(
        [{ 'name' => 'fakedesk', 'display_name' => 'FakeDesk', 'credential_fields' => adapter.credential_fields }]
      )
      row = page.dig('props', 'jobs').sole
      expect(row).to include('id' => job.id, 'platform' => 'fakedesk', 'status' => 'completed')
      expect(row['created_at']).to be_present
      expect(row).not_to have_key('credentials')
    end

    it 'is admin only' do
      allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
        .to receive(:current_user).and_return(create(:user, :agent))

      get '/support/admin/import'

      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'Connect' do
    it 'renders the credential form for the platform' do
      page = expect_screen('/support/admin/import/fakedesk/connect', 'Escalated/Admin/Import/Connect')

      expect(page['props']).to include('platform' => 'fakedesk', 'display_name' => 'FakeDesk',
                                       'credential_fields' => adapter.credential_fields)
    end

    it 'answers 404 for a platform no adapter provides' do
      get '/support/admin/import/nowhere/connect'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'test-connection' do
    it 'answers success false for credentials the source refuses' do
      post '/support/admin/import/fakedesk/test-connection',
           params: { credentials: credentials.merge('api_token' => 'wrong') }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('success' => false)
    end

    it 'answers 422 with the error when the source raises' do
      post '/support/admin/import/fakedesk/test-connection',
           params: { credentials: credentials.merge('subdomain' => 'down') }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('success' => false, 'error' => 'FakeDesk is unreachable')
    end
  end

  describe 'Mapping' do
    it 'sends the visitor back to Connect until a connection has been tested' do
      get '/support/admin/import/fakedesk/mapping'

      expect(response).to redirect_to('/support/admin/import/fakedesk/connect')
    end

    it 'renders defaults and source fields per entity type, read with the stored credentials' do
      connect!

      get '/support/admin/import/fakedesk/mapping'
      page = inertia_page

      expect(page['component']).to eq('Escalated/Admin/Import/Mapping')
      expect(page['props']).to include('platform' => 'fakedesk', 'display_name' => 'FakeDesk',
                                       'entity_types' => %w[contacts tags tickets replies])
      expect(page.dig('props', 'mappings', 'tickets')).to eq(
        'defaults' => { 'subject' => 'title', 'state' => 'status' },
        'source_fields' => adapter.available_source_fields('tickets', credentials)
      )
      expect(page.dig('props', 'mappings', 'contacts')).to eq('defaults' => {}, 'source_fields' => [])
      expect(adapter.source_field_credentials).to eq(credentials)
      # The credentials stay on the server: Laravel never round-trips them.
      expect(page['props']).not_to have_key('credentials')
      expect(response.body).not_to include(FakeImportAdapter::TOKEN)
    end
  end

  describe 'Review' do
    it 'echoes the chosen mappings and entity types without importing anything' do
      expect do
        inertia_visit(:post, '/support/admin/import/fakedesk/review',
                      { field_mappings: field_mappings, entity_types: %w[tickets replies] })
      end.not_to change(Escalated::ImportJob, :count)

      page = inertia_json
      expect(page['component']).to eq('Escalated/Admin/Import/Review')
      expect(page['props']).to include('platform' => 'fakedesk', 'field_mappings' => field_mappings,
                                       'entity_types' => %w[tickets replies])
      expect(Escalated::Ticket.count).to eq(0)
    end
  end

  describe 'start' do
    it 'refuses to start without a tested connection' do
      inertia_visit(:post, '/support/admin/import/fakedesk/start', { field_mappings: field_mappings })

      expect(response).to redirect_to('/support/admin/import/fakedesk/connect')
      expect(Escalated::ImportJob.count).to eq(0)
    end

    it 'creates the job, forgets the session copy of the credentials and queues the run' do
      job = start!

      expect(response).to redirect_to("/support/admin/import/progress/#{job.id}")
      expect(job).to have_attributes(platform: 'fakedesk', status: 'mapping', user_id: admin.id,
                                     field_mappings: field_mappings, credentials: credentials)
      raw = Escalated::ImportJob.connection.select_value(
        "SELECT credentials FROM #{Escalated::ImportJob.table_name} WHERE id = '#{job.id}'"
      )
      expect(raw).not_to include(FakeImportAdapter::TOKEN)
      expect(enqueued_jobs.pluck('job_class')).to include('Escalated::RunImportJob')

      get '/support/admin/import/fakedesk/mapping'
      expect(response).to redirect_to('/support/admin/import/fakedesk/connect')
    end

    context 'when the run completes' do
      let(:created) { [] }
      let(:hook) { ->(ticket) { created << ticket } }
      let(:importing_during_extract) { [] }
      let!(:job) do
        Escalated::SlaPolicy.create!(name: 'Default', is_default: true, is_active: true,
                                     first_response_hours: { 'high' => 1, 'urgent' => 1 },
                                     resolution_hours: { 'high' => 8, 'urgent' => 8 })
        Escalated.hooks.add_action('ticket_created', hook)
        adapter.on_extract = ->(*) { importing_during_extract << Escalated::Support::ImportContext.importing? }

        perform_enqueued_jobs { start! }.then { Escalated::ImportJob.sole }
      end

      after { Escalated.hooks.remove_action('ticket_created', hook) }

      it 'completes the job and drops its credentials' do
        job.reload

        expect(job).to have_attributes(status: 'completed', credentials: nil)
        expect(job.completed_at).to be_present
        expect(job.progress['tickets']).to include('total' => 3, 'processed' => 3, 'skipped' => 0, 'failed' => 0)
        expect(job.progress.keys).to eq(%w[contacts tags tickets replies])
        expect(Escalated::ImportSourceMap.where(import_job_id: job.id, entity_type: 'tickets').count).to eq(3)
      end

      it 'imports the tickets end to end' do
        tickets = Escalated::Ticket.order(:id)
        expect(tickets.map(&:subject)).to eq(['Refund please', 'Login broken', 'Feature idea'])
        expect(tickets.map(&:status)).to eq(%w[open resolved waiting_on_customer])

        refund = tickets.first
        expect(refund.requester.email).to eq('ada@customer.test')
        expect(refund.tags.map(&:name)).to eq(['Billing'])
        expect(refund.created_at).to eq(Time.utc(2024, 1, 2, 3, 4, 5))
        expect(refund.replies.sole.body).to eq('Looking into it, @admin.importer')
        expect(Escalated::Reply.where(is_internal: true).count).to eq(1)
      end

      it 'runs in import mode: no events, no SLA clock, no mention notifications' do
        expect(importing_during_extract).to all(be(true))
        expect(Escalated::Support::ImportContext.importing?).to be(false)
        expect(created).to eq([])
        expect(Escalated::Ticket.where.not(sla_policy_id: nil)).to be_empty
        expect(Escalated::Mention.count).to eq(0)
      end
    end
  end

  describe 'Progress and status' do
    let(:job) do
      Escalated::ImportJob.create!(platform: 'fakedesk', status: 'importing', credentials: credentials,
                                   field_mappings: field_mappings, started_at: Time.current,
                                   progress: { 'tickets' => { 'total' => 3, 'processed' => 1, 'skipped' => 0,
                                                              'failed' => 1, 'cursor' => '2' } },
                                   error_log: [{ 'entity_type' => 'tickets', 'source_id' => 'k9',
                                                 'error' => 'boom', 'timestamp' => '2024-01-01T00:00:00Z' }])
    end

    it 'renders the job the progress screen polls' do
      page = expect_screen("/support/admin/import/progress/#{job.id}", 'Escalated/Admin/Import/Progress')

      expect(page.dig('props', 'job')).to include(
        'id' => job.id, 'platform' => 'fakedesk', 'status' => 'importing',
        'progress' => job.progress, 'error_log' => job.error_log, 'field_mappings' => field_mappings
      )
      expect(page.dig('props', 'job')).not_to have_key('credentials')
      expect(response.body).not_to include(FakeImportAdapter::TOKEN)
    end

    it 'answers the status poll with JSON' do
      get "/support/admin/import/status/#{job.id}"

      expect(response.parsed_body.keys).to match_array(%w[status progress error_log started_at completed_at])
      expect(response.parsed_body).to include('status' => 'importing', 'progress' => job.progress,
                                              'error_log' => job.error_log)
    end

    it 'answers 404 for an unknown job' do
      get '/support/admin/import/status/00000000-0000-0000-0000-000000000000'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'pause, resume and cancel' do
    it 'pauses mid-run and resumes where it stopped, without importing anything twice' do
      adapter.on_extract = lambda do |entity_type, cursor|
        Escalated::ImportJob.update_all(status: 'paused') if entity_type == 'tickets' && cursor == '2'
      end

      job = nil
      perform_enqueued_jobs { job = start! }
      job.reload

      expect(job.status).to eq('paused')
      expect(Escalated::Ticket.count).to eq(3)
      expect(job.progress).not_to have_key('replies')
      expect(job.credentials).to eq(credentials)

      adapter.on_extract = nil
      adapter.extract_calls.clear
      perform_enqueued_jobs { inertia_visit(:post, "/support/admin/import/resume/#{job.id}") }

      expect(response).to redirect_to("/support/admin/import/progress/#{job.id}")
      expect(job.reload.status).to eq('completed')
      expect(Escalated::Ticket.count).to eq(3)
      expect(Escalated::Reply.count).to eq(2)
      # The run picked tickets up from its saved cursor, not from the start.
      expect(adapter.extract_calls).not_to include(['tickets', nil])
      expect(adapter.extract_calls).to include(%w[tickets 2])
    end

    it 'pauses an importing job' do
      job = Escalated::ImportJob.create!(platform: 'fakedesk', status: 'importing', credentials: credentials)

      inertia_visit(:post, "/support/admin/import/pause/#{job.id}")

      expect(response).to redirect_to("/support/admin/import/progress/#{job.id}")
      expect(job.reload.status).to eq('paused')
    end

    it 'resumes a failed job through mapping' do
      job = Escalated::ImportJob.create!(platform: 'fakedesk', status: 'failed', credentials: credentials)

      perform_enqueued_jobs { inertia_visit(:post, "/support/admin/import/resume/#{job.id}") }

      expect(job.reload.status).to eq('completed')
      expect(Escalated::Ticket.count).to eq(3)
    end

    it 'cancels a job and drops its credentials' do
      job = Escalated::ImportJob.create!(platform: 'fakedesk', status: 'paused', credentials: credentials)

      inertia_visit(:post, "/support/admin/import/cancel/#{job.id}")

      expect(response).to redirect_to("/support/admin/import/progress/#{job.id}")
      job.reload
      expect(job.status).to eq('failed')
      expect(job.completed_at).to be_present
      expect(job.credentials).to be_nil
    end
  end
end
