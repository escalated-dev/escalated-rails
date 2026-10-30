# frozen_string_literal: true

require 'rails_helper'
require 'cgi'
require 'escalated/seeds/permissions'

# ADR 2026-10-29-configurable-access-features: roles & permissions is an
# install-level switch (config.access[:roles_permissions] /
# ESCALATED_ROLES_PERMISSIONS). Off, the host gates decide everything and the
# roles screens answer 404. On, every admin, agent and staff API action also
# needs its permission from the user's Escalated roles.
RSpec.describe 'Roles & permissions enforcement', type: :request do
  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated::Seeds::Permissions.seed!
  end

  after { Escalated.configuration.access = {} }

  def enforce!
    Escalated.configuration.access = { roles_permissions: true }
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def staff(kind, role = nil)
    user = create(:user, kind)
    case role
    when String then Escalated::Role.find_by!(slug: role).users << user
    when Array
      custom = Escalated::Role.create!(name: "Custom #{SecureRandom.hex(3)}")
      custom.permissions = Escalated::Permission.where(slug: role)
      custom.users << user
    end
    user
  end

  def page_props
    JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))['props']
  end

  describe 'switched off (the default)' do
    it 'is off without configuration' do
      expect(Escalated::Support::AccessFeatures.roles_permissions?).to be(false)
    end

    it 'hides the roles screens' do
      sign_in_as(staff(:admin, 'admin'))
      get '/support/admin/roles'
      expect(response).to have_http_status(:not_found)
      get '/support/admin/roles/new'
      expect(response).to have_http_status(:not_found)
      expect { post '/support/admin/roles', params: { name: 'X' } }.not_to change(Escalated::Role, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'lets the gates alone decide' do
      agent = staff(:agent, 'light_agent')
      other = create(:user, :agent)
      ticket = create(:escalated_ticket)
      sign_in_as(agent)

      post "/support/agent/tickets/#{ticket.id}/assign", params: { agent_id: other.id }
      expect(ticket.reload.assigned_to).to eq(other.id)

      sign_in_as(staff(:admin))
      get '/support/admin/departments'
      expect(response).to have_http_status(:ok)
    end

    it 'shares the switches off and a wildcard permission set for staff' do
      sign_in_as(staff(:admin))
      get '/support/admin/departments'
      expect(page_props.dig('escalated', 'features')).to include(
        'roles_permissions' => false, 'two_factor' => false, 'sso' => false
      )
      expect(page_props.dig('escalated', 'permissions')).to eq(['*'])
    end

    it 'cannot be turned on from the settings store' do
      %w[roles_permissions access.roles_permissions ESCALATED_ROLES_PERMISSIONS].each do |key|
        Escalated::EscalatedSetting.set(key, '1')
      end
      sign_in_as(staff(:admin, 'admin'))
      get '/support/admin/roles'
      expect(response).to have_http_status(:not_found)
    end

    it 'does not apply the newsletter permissions' do
      allow(Escalated.configuration).to receive(:enable_newsletters?).and_return(true)
      sign_in_as(staff(:admin))
      get '/support/admin/newsletters'
      expect(response).to have_http_status(:ok)

      enforce!
      get '/support/admin/newsletters'
      expect(response).to have_http_status(:forbidden)
      sign_in_as(staff(:admin, 'admin'))
      get '/support/admin/newsletters'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'switched on' do
    before { enforce! }

    it 'shows the roles screens to a role manager' do
      sign_in_as(staff(:admin, 'admin'))
      get '/support/admin/roles'
      expect(response).to have_http_status(:ok)
      expect(page_props['roles'].pluck('slug')).to include('admin', 'agent', 'light_agent')
    end

    it 'grants nothing to an admin without a role' do
      sign_in_as(staff(:admin))
      get '/support/admin/departments'
      expect(response).to have_http_status(:forbidden)
      get '/support/admin/roles'
      expect(response).to have_http_status(:forbidden)
      post '/support/admin/settings', params: { show_powered_by: '0' }
      expect(response).to have_http_status(:forbidden)
    end

    it 'lets an admin with the admin role through' do
      sign_in_as(staff(:admin, 'admin'))
      get '/support/admin/departments'
      expect(response).to have_http_status(:ok)
      get '/support/admin/settings'
      expect(response).to have_http_status(:ok)
    end

    it 'checks admin reads and writes against separate permissions' do
      sign_in_as(staff(:admin, %w[department.view]))
      get '/support/admin/departments'
      expect(response).to have_http_status(:ok)
      expect { post '/support/admin/departments', params: { department: { name: 'Billing' } } }
        .not_to change(Escalated::Department, :count)
      expect(response).to have_http_status(:forbidden)
      get '/support/admin/webhooks'
      expect(response).to have_http_status(:forbidden)
    end

    it "shares the user's permission slugs and the switch" do
      sign_in_as(staff(:admin, %w[department.view]))
      get '/support/admin/departments'
      expect(page_props.dig('escalated', 'features', 'roles_permissions')).to be(true)
      expect(page_props.dig('escalated', 'permissions')).to eq(['department.view'])
    end

    it 'limits a light agent to viewing and notes' do
      agent = staff(:agent, 'light_agent')
      ticket = create(:escalated_ticket)
      sign_in_as(agent)

      get "/support/agent/tickets/#{ticket.id}"
      expect(response).to have_http_status(:ok)
      expect { post "/support/agent/tickets/#{ticket.id}/note", params: { body: 'Internal' } }
        .to change(Escalated::Reply, :count).by(1)

      post "/support/agent/tickets/#{ticket.id}/assign", params: { agent_id: agent.id }
      expect(response).to have_http_status(:forbidden)
      post "/support/agent/tickets/#{ticket.id}/priority", params: { priority: 'high' }
      expect(response).to have_http_status(:forbidden)
      post "/support/agent/tickets/#{ticket.id}/status", params: { status: 'closed' }
      expect(response).to have_http_status(:forbidden)

      ticket.reload
      expect(ticket.assigned_to).to be_nil
      expect(ticket.priority).to eq('medium')
      expect(ticket.status).to eq('open')
    end

    it 'lets a full agent assign' do
      agent = staff(:agent, 'agent')
      ticket = create(:escalated_ticket)
      sign_in_as(agent)
      post "/support/agent/tickets/#{ticket.id}/assign", params: { agent_id: agent.id }
      expect(ticket.reload.assigned_to).to eq(agent.id)
    end

    it 'needs ticket.close only to close, resolve or reopen' do
      ticket = create(:escalated_ticket)
      sign_in_as(staff(:agent, %w[ticket.view ticket.edit]))

      post "/support/agent/tickets/#{ticket.id}/status", params: { status: 'closed' }
      expect(response).to have_http_status(:forbidden)
      post "/support/agent/tickets/#{ticket.id}/status", params: { status: 'resolved' }
      expect(response).to have_http_status(:forbidden)
      post "/support/agent/tickets/#{ticket.id}/status", params: { status: 'in_progress' }
      expect(ticket.reload.status).to eq('in_progress')

      sign_in_as(staff(:agent, %w[ticket.view ticket.edit ticket.close]))
      post "/support/agent/tickets/#{ticket.id}/status", params: { status: 'resolved' }
      expect(ticket.reload.status).to eq('resolved')
    end

    it 'checks each bulk action against its own permission' do
      agent = staff(:agent, 'light_agent')
      ticket = create(:escalated_ticket)
      sign_in_as(agent)

      post '/support/agent/tickets/bulk', params: { ticket_ids: [ticket.id], action: 'assign', value: agent.id },
                                          as: :json
      expect(response).to have_http_status(:forbidden)
      post '/support/agent/tickets/bulk', params: { ticket_ids: [ticket.id], action: 'delete' }, as: :json
      expect(response).to have_http_status(:forbidden)
      post '/support/agent/tickets/bulk', params: { ticket_ids: [ticket.id], action: 'close' }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(ticket.reload.status).to eq('open')

      sign_in_as(staff(:agent, %w[ticket.view ticket.edit]))
      post '/support/agent/tickets/bulk', params: { ticket_ids: [ticket.id], action: 'priority', value: 'high' },
                                          as: :json
      expect(ticket.reload.priority).to eq('high')
    end

    it "checks the API token owner's permissions" do
      agent = staff(:agent, 'light_agent')
      ticket = create(:escalated_ticket)
      token = Escalated::ApiToken.create_token(agent, 'roles spec')
      headers = { 'Authorization' => "Bearer #{token[:plain_text_token]}" }

      get "/support/api/v1/tickets/#{ticket.reference}", headers: headers
      expect(response).to have_http_status(:ok)
      post "/support/api/v1/tickets/#{ticket.reference}/assign", params: { agent_id: agent.id }, headers: headers
      expect(response).to have_http_status(:forbidden)
      delete "/support/api/v1/tickets/#{ticket.reference}", headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(Escalated::Ticket.exists?(ticket.id)).to be(true)
    end

    it 'refuses an action that has no permission mapping' do
      expect(Escalated::Support::RoutePermissions.required_for('escalated/admin/not_in_the_map', 'index', {}))
        .to be_nil
    end

    it 'assigns a role with the rake task helper' do
      user = create(:user, :admin)
      Escalated::AccessControl.assign_role!(user.email, 'admin')
      expect(Escalated::AccessControl.permission_slugs(user.id)).to include('role.manage')
      expect { Escalated::AccessControl.assign_role!('nobody@example.test', 'admin') }.to raise_error(ArgumentError)
      expect { Escalated::AccessControl.assign_role!(user.email, 'nope') }.to raise_error(ArgumentError)
    end
  end

  it 'maps every admin, agent and staff API action to a permission' do
    unmapped = [Rails.application.routes, Escalated::Engine.routes].flat_map do |set|
      set.routes.filter_map do |route|
        controller = route.defaults[:controller].to_s
        next unless controller.start_with?('escalated/admin/', 'escalated/agent/', 'escalated/api/v1/')
        next if controller == 'escalated/api/v1/mobile_guest'
        next if controller == 'escalated/api/v1/auth' && %w[login register refresh
                                                            logout].include?(route.defaults[:action])

        key = "#{controller}##{route.defaults[:action]}"
        key unless Escalated::Support::RoutePermissions.mapped?(controller, route.defaults[:action])
      end
    end

    expect(unmapped.uniq).to eq([])
  end

  it 'names only seeded permissions' do
    seeded = Escalated::Seeds::Permissions::PERMISSIONS.pluck(:slug)
    named = Escalated::Support::RoutePermissions::MAP.flat_map(&:last).uniq
    expect(named - seeded).to eq([])
  end
end
