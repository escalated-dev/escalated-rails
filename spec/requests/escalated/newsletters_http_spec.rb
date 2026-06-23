# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Escalated newsletter HTTP layer', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin@example.com') }
  let(:agent) { create(:user, :agent, email: 'agent@example.com') }

  before do
    allow(Escalated.configuration).to receive(:enable_newsletters?).and_return(true)
    allow(Escalated.configuration).to receive_messages(
      newsletter_default_from: 'news@example.com',
      newsletter_default_reply_to: 'reply@example.com',
      newsletter_default_theme: 'default',
      newsletter_rate_limit_per_minute: 60,
      newsletter_batch_size: 50,
      newsletter_tracking_enabled?: true,
      app_url: 'https://app.test',
      notification_channels: [],
      webhook_url: nil
    )
  end

  def sign_in_as(user)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
    # rubocop:enable RSpec/AnyInstance
  end

  describe 'admin campaign routes' do
    it 'renders the newsletter index Inertia page for admins' do
      sign_in_as(admin)
      create(:escalated_newsletter, status: 'draft')

      get '/support/admin/newsletters'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Escalated/Admin/Newsletters/Index')
    end

    it 'creates a draft newsletter' do
      sign_in_as(admin)
      list = create(:escalated_newsletter_list)

      expect do
        post '/support/admin/newsletters',
             params: {
               subject: 'June update',
               from_email: 'news@example.com',
               target_list_id: list.id,
               status: 'draft',
               body_markdown: 'Hello'
             }
      end.to change(Escalated::Newsletter, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end

    it 'blocks non-admins before newsletter management' do
      sign_in_as(agent)

      get '/support/admin/newsletters'

      expect(response).to have_http_status(:redirect)
    end

    it 'enforces newsletter manage permission when host roles are present' do
      role = create(:escalated_role)
      admin.define_singleton_method(:roles) { [role] }
      sign_in_as(admin)

      get '/support/admin/newsletters'

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires newsletters.send for test sends when host roles are present' do
      manage = create(:escalated_permission, slug: 'newsletters.manage')
      role = create(:escalated_role)
      role.permissions << manage
      admin.define_singleton_method(:roles) { [role] }
      sign_in_as(admin)
      list = create(:escalated_newsletter_list)

      post '/support/admin/newsletters/test',
           params: {
             subject: 'Test',
             from_email: 'news@example.com',
             target_list_id: list.id,
             status: 'draft',
             body_markdown: 'Hello'
           }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'admin list/template/settings routes' do
    before { sign_in_as(admin) }

    it 'creates and shows a static newsletter list' do
      post '/support/admin/newsletters/lists',
           params: { name: 'Customers', kind: 'static', description: 'Customers' }

      expect(response).to have_http_status(:redirect)
      list = Escalated::NewsletterList.last

      get "/support/admin/newsletters/lists/#{list.id}"
      expect(response.body).to include('Escalated/Admin/Newsletters/Lists/Show')
    end

    it 'creates a template and renders newsletter settings' do
      post '/support/admin/newsletters/templates',
           params: { name: 'Default', theme: 'default', body_markdown: 'Hello' }

      expect(response).to have_http_status(:redirect)
      expect(Escalated::NewsletterTemplate.count).to eq(1)

      get '/support/admin/newsletters/settings'
      expect(response.body).to include('Escalated/Admin/Newsletters/Settings')
    end
  end

  describe 'public tracking routes' do
    let(:contact) { create(:escalated_contact, email: 'reader@example.com') }
    let(:newsletter) { create(:escalated_newsletter, status: 'sending') }
    let(:delivery) do
      create(:escalated_newsletter_delivery, newsletter: newsletter, contact: contact, status: 'sent',
                                             tracking_token: 'abc123')
    end

    it 'returns a tracking pixel and records opens' do
      get "/escalated/n/o/#{delivery.tracking_token}.gif"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
      expect(delivery.reload.opened_at).to be_present
    end

    it 'redirects valid clicks and rejects invalid destinations' do
      encoded = Base64.urlsafe_encode64('https://example.com/path', padding: false)

      get "/escalated/n/c/#{delivery.tracking_token}", params: { u: encoded }
      expect(response).to redirect_to('https://example.com/path')

      get "/escalated/n/c/#{delivery.tracking_token}", params: { u: Base64.urlsafe_encode64('javascript:alert(1)') }
      expect(response).to have_http_status(:bad_request)
    end

    it 'unsubscribes without authentication or CSRF' do
      post "/escalated/n/u/#{delivery.tracking_token}"

      expect(response).to have_http_status(:ok)
      expect(contact.reload.marketing_opt_out_at).to be_present
    end

    it 'returns 200 for missing view-in-browser tokens' do
      get '/escalated/n/v/missing-token'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('This email is no longer available.')
    end

    it 'returns 404 while newsletters are disabled' do
      allow(Escalated.configuration).to receive(:enable_newsletters?).and_return(false)

      get "/escalated/n/o/#{delivery.tracking_token}.gif"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'ESP webhooks' do
    it 'maps provider payloads to tracker events' do
      delivery = create(:escalated_newsletter_delivery, status: 'sent', tracking_token: 'tok123')

      post '/escalated/webhooks/newsletter/postmark',
           params: {
             RecordType: 'Bounce',
             MessageID: "n-#{delivery.newsletter_id}-#{delivery.tracking_token}@app.test",
             Type: 'HardBounce',
             Description: 'Mailbox unavailable'
           }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true)
      expect(delivery.reload.status).to eq('bounced')
    end
  end
end
