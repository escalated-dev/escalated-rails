# frozen_string_literal: true

require 'rails_helper'

# A server-rendered host (ADR 2026-11-05-embeddable-admin): its admin layout
# (spec/dummy/app/views/layouts/host_admin.html.erb, the template in
# docs/embedding-admin.md) becomes the Inertia root view for embedded pages,
# and only for them, and renders Escalated's menu from admin_navigation.
RSpec.describe 'Embedded admin: root view', type: :request do
  embed_admin_with(root_view: 'host_admin')

  let(:admin) { create(:user, :admin, email: 'embed-root-view@example.test') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    sign_in_as(admin)
  end

  it "renders embedded pages in the host's layout, with the admin menu" do
    get '/backoffice/helpdesk/tags'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-host-admin-sidebar')
    expect(response.body).to include('<a href="/backoffice/helpdesk/tags" class="active" aria-current="page">Tags</a>')
    expect(response.body).to include('<a href="/backoffice/helpdesk/reports">Reports</a>')
    expect(inertia_page['component']).to eq('Escalated/Admin/Tags/Index')
  end

  it 'answers an Inertia visit with JSON as usual' do
    get '/backoffice/helpdesk/tags', headers: { 'X-Inertia' => 'true' }

    expect(response.parsed_body['component']).to eq('Escalated/Admin/Tags/Index')
  end

  it 'keeps the normal root view everywhere else' do
    get '/support/agent'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-host-admin-sidebar')
  end
end
