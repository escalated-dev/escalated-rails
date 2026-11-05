# frozen_string_literal: true

require 'rails_helper'

# replace_admin_gate (ADR 2026-11-05-embeddable-admin): only when the host
# opts in does its own guard replace Escalated's admin gate, and only on the
# embedded admin routes. Two-factor and route permissions still apply.
RSpec.describe 'Embedded admin: the host gate replaces the admin gate', type: :request do
  embed_admin_with(middleware: [EmbedHelpers::HOST_AUTHENTICATE, EmbedHelpers::HOST_OWNER_GATE],
                   replace_admin_gate: true)

  let(:owner) { create(:user, email: EmbedHelpers::OWNER_EMAIL) }

  before { allow(Escalated.configuration).to receive(:notification_channels).and_return([]) }

  it 'lets the host gate alone decide who reaches the embedded admin' do
    sign_in_as(owner)
    get '/backoffice/helpdesk/tags'

    expect(response).to have_http_status(:ok)
    expect(Escalated.admin_navigation(owner)).not_to be_empty
  end

  it 'refuses an Escalated admin the host gate refuses' do
    sign_in_as(create(:user, :admin, email: 'escalated-admin@example.test'))
    get '/backoffice/helpdesk/tags'

    expect(response).to have_http_status(:forbidden)
  end

  it 'still enforces route permissions' do
    allow(Escalated.configuration).to receive(:access).and_return(roles_permissions: true)
    sign_in_as(owner)
    get '/backoffice/helpdesk/tags'

    expect(response).to have_http_status(:forbidden)
  end

  it "keeps Escalated's gates on the agent panel and the standalone pages" do
    sign_in_as(owner)
    get '/support/agent'
    expect(response).to redirect_to('/')

    get '/support/admin/newsletters'
    expect(response).to redirect_to('/')
  end

  it 'refuses to replace the gate without host guards' do
    expect { Escalated.configuration.embed_admin(replace_admin_gate: true) }
      .to raise_error(ArgumentError, /middleware/)
  end
end
