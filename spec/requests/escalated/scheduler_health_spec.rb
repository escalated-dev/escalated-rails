# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Rails has no in-process scheduler for the engine to register with, so the
# recurring jobs run only when the host schedules them. CheckSlaJob records a
# heartbeat; admins are warned when it is missing or older than 15 minutes.
RSpec.describe 'Scheduler heartbeat', type: :request do
  let(:admin) { create(:user, :admin, email: 'scheduler-admin@example.test') }
  let(:agent) { create(:user, :agent, email: 'scheduler-agent@example.test') }

  before { allow(Escalated.configuration).to receive(:notification_channels).and_return([]) }

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  describe Escalated::CheckSlaJob do
    it 'records the heartbeat when it runs' do
      freeze_time do
        described_class.perform_now

        expect(Escalated::SchedulerHealth.last_run_at).to eq(Time.current.change(usec: 0))
        expect(Escalated::SchedulerHealth.status[:healthy]).to be(true)
      end
    end

    it 'records it with SLA switched off as well' do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(false)

      described_class.perform_now

      expect(Escalated::SchedulerHealth.last_run_at).to be_present
    end
  end

  describe Escalated::SchedulerHealth do
    it 'is unhealthy when the SLA check has never run' do
      status = described_class.status

      expect(status).to include(healthy: false, last_run_at: nil)
      expect(status[:message]).to include('not running', 'never run', 'Escalated::CheckSlaJob (every minute)')
      expect(status[:commands]).to include(
        { command: 'Escalated::CheckSlaJob', interval: 'every minute' },
        { command: 'Escalated::EvaluateEscalationsJob', interval: 'every 5 minutes' },
        { command: 'Escalated::RunAutomationsJob', interval: 'every 5 minutes' },
        { command: 'Escalated::WakeSnoozedTicketsJob', interval: 'every minute' }
      )
    end

    it 'is healthy for 15 minutes after a run and unhealthy after that' do
      ran = Time.zone.parse('2026-11-24 10:00:00 UTC')
      described_class.beat!(ran)

      expect(described_class.status(now: ran + 15.minutes)).to include(healthy: true,
                                                                       last_run_at: '2026-11-24T10:00:00Z')
      stale = described_class.status(now: ran + 16.minutes)
      expect(stale[:healthy]).to be(false)
      expect(stale[:message]).to include('last ran at 2026-11-24T10:00:00Z')
    end

    it 'logs a warning while the jobs are not running' do
      allow(Rails.logger).to receive(:warn)

      described_class.status_with_warning

      expect(Rails.logger).to have_received(:warn).with(/recurring jobs are not running/)
    end

    it 'does not break the SLA check when the heartbeat cannot be written' do
      allow(Escalated::EscalatedSetting).to receive(:set).and_raise(ActiveRecord::StatementInvalid, 'gone')

      expect(described_class.beat!).to be_nil
      expect { Escalated::CheckSlaJob.perform_now }.not_to raise_error
    end
  end

  describe 'the admin pages' do
    before { sign_in_as(admin) }

    it 'warns on the Settings page while the heartbeat is missing' do
      get '/support/admin/settings'

      scheduler = inertia_page.dig('props', 'scheduler')
      expect(scheduler).to include('healthy' => false, 'last_run_at' => nil)
      expect(scheduler['message']).to include('not running')
      expect(scheduler['commands']).to include({ 'command' => 'Escalated::CheckSlaJob', 'interval' => 'every minute' })
    end

    it 'warns on the reports dashboard while the heartbeat is stale' do
      Escalated::SchedulerHealth.beat!(20.minutes.ago)

      get '/support/admin/reports/dashboard'

      expect(inertia_page.dig('props', 'scheduler', 'healthy')).to be(false)
    end

    it 'warns on the reports overview as well' do
      get '/support/admin/reports'

      expect(inertia_page['component']).to eq('Escalated/Admin/Reports')
      expect(inertia_page.dig('props', 'scheduler', 'healthy')).to be(false)
    end

    it 'reports healthy once the SLA check has run' do
      Escalated::CheckSlaJob.perform_now

      get '/support/admin/settings'

      expect(inertia_page.dig('props', 'scheduler', 'healthy')).to be(true)
    end
  end

  describe 'the API dashboard (headless installs)' do
    def get_dashboard(user)
      token = Escalated::ApiToken.create_token(user, 'scheduler')[:plain_text_token]
      get '/support/api/v1/dashboard', headers: { 'Authorization' => "Bearer #{token}" }
    end

    it 'includes the scheduler status for admins' do
      get_dashboard(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['scheduler']).to include('healthy' => false)
    end

    it 'leaves it out for agents' do
      get_dashboard(agent)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key('scheduler')
    end
  end

  # Every recurring task is an ActiveJob, so a Solid Queue recurring.yml can
  # list them all; the rake tasks run the same jobs.
  describe 'the automation and snooze jobs' do
    around do |example|
      original = Rake.application
      Rake.application = Rake::Application.new
      Rails.application.load_tasks
      example.run
    ensure
      Rake.application = original
    end

    it 'runs the automations (the rake task named a class that does not exist)' do
      expect(Escalated::RunAutomationsJob.perform_now).to eq(0)
      expect { Rake::Task['escalated:run_automations'].invoke }
        .to output("Automations complete: 0 ticket(s) affected
").to_stdout
    end

    it 'wakes snoozed tickets whose time has passed' do
      ticket = create(:escalated_ticket)
      ticket.update_columns(snoozed_until: 1.minute.ago, status_before_snooze: 'open')

      expect(Escalated::WakeSnoozedTicketsJob.perform_now).to eq(1)
      expect(ticket.reload.snoozed_until).to be_nil
      expect { Rake::Task['escalated:wake_snoozed_tickets'].invoke }.to output("Woke 0 snoozed ticket(s)
").to_stdout
    end
  end
end
