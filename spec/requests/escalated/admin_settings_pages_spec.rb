# frozen_string_literal: true

require 'rails_helper'

# The admin Settings sub-pages of the shared frontend: CsatSettings,
# DataRetention, EmailSettings and PublicTickets. Their props, paths and
# validation follow escalated-laravel's controllers for the same screens, and
# each one stores its values in the engine's settings table.
RSpec.describe 'Admin settings pages', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-settings@example.test') }

  before do
    allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_user).and_return(admin)
  end

  def setting(key)
    Escalated::EscalatedSetting.get(key)
  end

  describe 'CsatSettings' do
    it 'shows the defaults when nothing has been saved' do
      page = expect_screen('/support/admin/settings/csat', 'Escalated/Admin/Settings/CsatSettings')

      expect(page.dig('props', 'settings')).to eq(
        'csat_question_text' => 'How would you rate your support experience?',
        'csat_scale' => '1-5',
        'csat_delivery_trigger' => 'on_resolve',
        'csat_delay_hours' => 0
      )
    end

    it 'saves the settings and shows them back' do
      inertia_visit(:post, '/support/admin/settings/csat',
                    { csat_question_text: 'How did we do?', csat_scale: '1-3',
                      csat_delivery_trigger: 'delayed', csat_delay_hours: 24 },
                    referer: '/support/admin/settings/csat')

      expect(response).to redirect_to('/support/admin/settings/csat')
      expect(flash[:success]).to eq('CSAT settings updated.')
      expect(%w[csat_question_text csat_scale csat_delivery_trigger csat_delay_hours].map { |k| setting(k) })
        .to eq(['How did we do?', '1-3', 'delayed', '24'])

      get '/support/admin/settings/csat'
      expect(inertia_page.dig('props', 'settings')).to include('csat_scale' => '1-3', 'csat_delay_hours' => 24)
    end

    it 'refuses invalid values and saves nothing' do
      inertia_visit(:post, '/support/admin/settings/csat',
                    { csat_question_text: '', csat_scale: '1-10', csat_delivery_trigger: 'weekly',
                      csat_delay_hours: 500 },
                    referer: '/support/admin/settings/csat')

      expect(response).to redirect_to('/support/admin/settings/csat')
      expect(session[:inertia_errors].keys).to contain_exactly(
        'csat_question_text', 'csat_scale', 'csat_delivery_trigger', 'csat_delay_hours'
      )
      expect(setting('csat_scale')).to be_nil
    end
  end

  describe 'DataRetention' do
    it 'shows the defaults and a zero preview when nothing is set' do
      create(:escalated_ticket, status: :closed, closed_at: 10.years.ago)

      page = expect_screen('/support/admin/settings/data-retention', 'Escalated/Admin/Settings/DataRetention')

      expect(page.dig('props', 'settings')).to eq(
        'retention_closed_tickets' => 'never',
        'retention_attachments' => 'never',
        'retention_audit_logs' => 'never',
        'retention_user_data_gdpr' => false
      )
      expect(page.dig('props', 'purgePreview')).to eq('tickets' => 0, 'attachments' => 0, 'audit_logs' => 0)
    end

    it 'previews what the configured retention would purge' do
      old_closed = create(:escalated_ticket, status: :closed, closed_at: 2.years.ago)
      create(:escalated_ticket, status: :closed, closed_at: 2.months.ago)
      create(:escalated_ticket, status: :open, created_at: 3.years.ago)
      Escalated::Attachment.create!(attachable: old_closed, filename: 'old.txt', content_type: 'text/plain',
                                    byte_size: 1, created_at: 4.years.ago)
      Escalated::Attachment.create!(attachable: old_closed, filename: 'new.txt', content_type: 'text/plain',
                                    byte_size: 1)
      create(:escalated_audit_log, created_at: 100.days.ago)
      create(:escalated_audit_log)

      Escalated::EscalatedSetting.set('retention_closed_tickets', '1_year')
      Escalated::EscalatedSetting.set('retention_attachments', '3_years')
      Escalated::EscalatedSetting.set('retention_audit_logs', '90_days')
      Escalated::EscalatedSetting.set('retention_user_data_gdpr', '1')

      page = expect_screen('/support/admin/settings/data-retention', 'Escalated/Admin/Settings/DataRetention')

      expect(page.dig('props', 'settings', 'retention_user_data_gdpr')).to be(true)
      expect(page.dig('props', 'purgePreview')).to eq('tickets' => 1, 'attachments' => 1, 'audit_logs' => 1)
    end

    it 'saves the settings' do
      inertia_visit(:post, '/support/admin/settings/data-retention',
                    { retention_closed_tickets: '2_years', retention_attachments: '5_years',
                      retention_audit_logs: '180_days', retention_user_data_gdpr: true },
                    referer: '/support/admin/settings/data-retention')

      expect(response).to redirect_to('/support/admin/settings/data-retention')
      expect(flash[:success]).to eq('Data retention settings updated.')
      expect(%w[retention_closed_tickets retention_attachments retention_audit_logs
                retention_user_data_gdpr].map { |k| setting(k) }).to eq(%w[2_years 5_years 180_days 1])
    end

    it 'refuses invalid values and saves nothing' do
      inertia_visit(:post, '/support/admin/settings/data-retention',
                    { retention_closed_tickets: '7_years', retention_attachments: 'never',
                      retention_audit_logs: '1_year', retention_user_data_gdpr: 'maybe' },
                    referer: '/support/admin/settings/data-retention')

      expect(response).to redirect_to('/support/admin/settings/data-retention')
      expect(session[:inertia_errors].keys).to contain_exactly(
        'retention_closed_tickets', 'retention_audit_logs', 'retention_user_data_gdpr'
      )
      expect(setting('retention_attachments')).to be_nil
    end
  end

  describe 'EmailSettings' do
    it 'shows no addresses and no default reply address when nothing is set' do
      page = expect_screen('/support/admin/settings/email', 'Escalated/Admin/Settings/EmailSettings')

      expect(page['props']).to include('addresses' => [], 'defaultReplyAddress' => '')
    end

    it 'saves the addresses, keeping only the four fields the screen edits' do
      inertia_visit(:post, '/support/admin/settings/email',
                    { addresses: [
                        { email: 'support@example.test', display_name: 'Support', department_id: 3,
                          dkim_status: 'verified', smtp_password: 'nope' },
                        { email: 'billing@example.test' }
                      ],
                      default_reply_address: 'support@example.test' },
                    referer: '/support/admin/settings/email')

      expect(response).to redirect_to('/support/admin/settings/email')
      expect(flash[:success]).to eq('Email settings updated.')
      expect(setting('default_reply_address')).to eq('support@example.test')

      get '/support/admin/settings/email'
      expect(inertia_page.dig('props', 'addresses')).to eq(
        [{ 'email' => 'support@example.test', 'display_name' => 'Support', 'department_id' => 3,
           'dkim_status' => 'verified' },
         { 'email' => 'billing@example.test', 'display_name' => nil, 'department_id' => nil,
           'dkim_status' => 'unknown' }]
      )
      expect(inertia_page.dig('props', 'defaultReplyAddress')).to eq('support@example.test')
    end

    it 'refuses an invalid address and saves nothing' do
      inertia_visit(:post, '/support/admin/settings/email',
                    { addresses: [{ email: 'not-an-email', dkim_status: 'great' }],
                      default_reply_address: 'also bad' },
                    referer: '/support/admin/settings/email')

      expect(response).to redirect_to('/support/admin/settings/email')
      expect(session[:inertia_errors].keys).to contain_exactly(
        'addresses.0.email', 'addresses.0.dkim_status', 'default_reply_address'
      )
      expect(setting('email_addresses')).to be_nil
    end
  end

  describe 'PublicTickets' do
    it 'shows the guest policy' do
      Escalated::EscalatedSetting.set('guest_policy_mode', 'guest_user')
      Escalated::EscalatedSetting.set('guest_policy_user_id', '42')

      page = expect_screen('/support/admin/settings/public-tickets', 'Escalated/Admin/Settings/PublicTickets')

      expect(page.dig('props', 'settings')).to eq(
        'guest_policy_mode' => 'guest_user', 'guest_policy_user_id' => '42',
        'guest_policy_signup_url_template' => ''
      )
    end

    it 'saves the policy from the POST the page sends' do
      inertia_visit(:post, '/support/admin/settings/public-tickets',
                    { guest_policy_mode: 'prompt_signup', guest_policy_user_id: '9',
                      guest_policy_signup_url_template: 'https://example.test/join?email={email}' },
                    referer: '/support/admin/settings/public-tickets')

      expect(response).to redirect_to('/support/admin/settings/public-tickets')
      expect(flash[:success]).to eq('Guest policy updated.')
      expect(setting('guest_policy_mode')).to eq('prompt_signup')
      expect(setting('guest_policy_user_id')).to eq('')
      expect(setting('guest_policy_signup_url_template')).to eq('https://example.test/join?email={email}')
    end

    it 'saves the policy from a PUT as well' do
      inertia_visit(:put, '/support/admin/settings/public-tickets',
                    { guest_policy_mode: 'guest_user', guest_policy_user_id: 7 })

      expect(setting('guest_policy_mode')).to eq('guest_user')
      expect(setting('guest_policy_user_id')).to eq('7')
    end

    it 'refuses a guest-user policy with no user, and an unknown mode' do
      inertia_visit(:post, '/support/admin/settings/public-tickets', { guest_policy_mode: 'guest_user' },
                    referer: '/support/admin/settings/public-tickets')

      expect(response).to redirect_to('/support/admin/settings/public-tickets')
      expect(session[:inertia_errors].keys).to eq(['guest_policy_user_id'])

      inertia_visit(:post, '/support/admin/settings/public-tickets', { guest_policy_mode: 'everyone' },
                    referer: '/support/admin/settings/public-tickets')

      expect(session[:inertia_errors].keys).to eq(['guest_policy_mode'])
      expect(setting('guest_policy_mode')).to be_nil
    end
  end

  it 'is for admins only' do
    allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_user).and_return(create(:user, :agent))

    %w[csat data-retention email public-tickets].each do |screen|
      get "/support/admin/settings/#{screen}"
      expect(response).to have_http_status(:redirect)

      post "/support/admin/settings/#{screen}", params: {}
      expect(response).to have_http_status(:redirect)
    end

    expect(Escalated::EscalatedSetting.count).to eq(0)
  end
end
