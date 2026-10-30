# frozen_string_literal: true

require 'rails_helper'
require 'cgi'
require 'escalated/seeds/permissions'

# The users screen's roles picker (PUT escalated.admin.users.roles with
# {role_ids: [...]}), mirroring escalated-laravel's
# Admin\UserController#updateRoles: only while roles & permissions is on,
# needs role.manage, validates the ids, refuses removing your own role
# management, and redirects back with "User updated.".
RSpec.describe 'Admin users roles picker', type: :request do
  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated::Seeds::Permissions.seed!
  end

  after { Escalated.configuration.access = {} }

  let(:light) { Escalated::Role.find_by!(slug: 'light_agent') }

  def enforce!
    Escalated.configuration.access = { roles_permissions: true }
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def user_with(kind, role)
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

  def put_roles(user, body)
    put "/support/admin/users/#{user.id}/roles", params: body, as: :json,
                                                 headers: { 'X-Inertia' => 'true',
                                                            'Referer' => 'http://www.example.com/support/admin/users' }
  end

  def page_props
    JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))['props']
  end

  def role_slugs(user)
    Escalated::Role.joins(:users)
                   .where(Escalated.table_name('role_users') => { user_id: user.id })
                   .pluck(:slug).sort
  end

  describe 'switched off' do
    it 'is not there and the screen sends no roles' do
      admin = user_with(:admin, 'admin')
      agent = user_with(:agent, 'agent')
      sign_in_as(admin)

      put_roles(agent, { role_ids: [light.id] })
      expect(response).to have_http_status(:not_found)
      expect(role_slugs(agent)).to eq(['agent'])

      get '/support/admin/users'
      expect(page_props).not_to have_key('roles')
      expect(page_props['users']['data'].first).not_to have_key('roles')
    end
  end

  describe 'switched on' do
    before { enforce! }

    it "sends the roles and each user's role slugs" do
      admin = user_with(:admin, 'admin')
      agent = user_with(:agent, 'light_agent')
      plain = create(:user)
      sign_in_as(admin)

      get '/support/admin/users'
      expect(response).to have_http_status(:ok)
      roles = page_props['roles']
      expect(roles.pluck('name')).to eq(roles.pluck('name').sort)
      expect(roles.first.keys).to contain_exactly('id', 'name', 'slug')
      expect(roles.pluck('slug')).to include('admin', 'agent', 'light_agent')

      rows = page_props['users']['data'].to_h { |u| [u['id'], u['roles']] }
      expect(rows[admin.id]).to eq(['admin'])
      expect(rows[agent.id]).to eq(['light_agent'])
      expect(rows[plain.id]).to eq([])
    end

    it "replaces a user's roles and redirects back with Laravel's flash" do
      admin = user_with(:admin, 'admin')
      agent = user_with(:agent, 'agent')
      sign_in_as(admin)

      put_roles(agent, { role_ids: [light.id] })
      expect(response).to have_http_status(:see_other).or have_http_status(:found)
      expect(response.location).to end_with('/support/admin/users')
      expect(flash[:success]).to eq('User updated.')
      expect(role_slugs(agent)).to eq(['light_agent'])

      slugs = Escalated::AccessControl.permission_slugs(agent.id)
      expect(slugs).to include('reply.create_internal')
      expect(slugs).not_to include('ticket.assign')

      put_roles(agent, { role_ids: [light.id, Escalated::Role.find_by!(slug: 'agent').id] })
      expect(role_slugs(agent)).to eq(%w[agent light_agent])

      put_roles(agent, { role_ids: [] })
      expect(role_slugs(agent)).to eq([])
    end

    it "validates role_ids as Laravel's rules do" do
      admin = user_with(:admin, 'admin')
      agent = user_with(:agent, 'agent')
      sign_in_as(admin)

      [{}, { role_ids: 'admin' }, { role_ids: ['x'] }, { role_ids: [987_654] }].each do |body|
        put_roles(agent, body)
        expect(response).to have_http_status(:redirect)
        expect(session[:inertia_errors]&.keys&.first).to match(/\Arole_ids(\.0)?\z/)
      end
      expect(role_slugs(agent)).to eq(['agent'])
    end

    it 'needs role.manage' do
      manager = user_with(:admin, %w[user.view user.manage])
      agent = user_with(:agent, 'agent')
      sign_in_as(manager)

      put_roles(agent, { role_ids: [light.id] })
      expect(response).to have_http_status(:forbidden)
      expect(role_slugs(agent)).to eq(['agent'])
    end

    it 'does not let a role manager remove their own role management' do
      admin = user_with(:admin, 'admin')
      sign_in_as(admin)

      put_roles(admin, { role_ids: [light.id] })
      expect(flash[:error]).to eq('You cannot remove your own role management.')
      expect(role_slugs(admin)).to eq(['admin'])
    end

    it 'answers 404 for an unknown user' do
      sign_in_as(user_with(:admin, 'admin'))
      put '/support/admin/users/987654/roles', params: { role_ids: [light.id] }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
