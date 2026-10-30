# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

RSpec.describe Escalated::ApplicationController, type: :request do
  let(:admin) { create(:user, :admin, email: 'shared-props@example.test') }

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:current_user).and_return(user)
  end

  def inertia_props_from(body)
    encoded = body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))['props']
  end

  describe 'Inertia shared props' do
    it 'includes empty permissions when there is no current user' do
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Escalated::Admin::SkillsController).to receive(:require_admin!)
      allow_any_instance_of(described_class).to receive(:current_user).and_return(nil)
      # rubocop:enable RSpec/AnyInstance

      get '/support/admin/skills'

      expect(response).to have_http_status(:ok)
      props = inertia_props_from(response.body)
      expect(props.dig('escalated', 'permissions')).to eq([])
    end

    it 'shares a wildcard permission set for staff while roles & permissions is off' do
      sign_in_as(admin)
      get '/support/admin/skills'

      expect(response).to have_http_status(:ok)
      props = inertia_props_from(response.body)
      expect(props.dig('escalated', 'permissions')).to eq(['*'])
    end

    it 'includes permission slugs for the signed-in user via roles while roles & permissions is on' do
      manage = create(:escalated_permission, slug: 'newsletters.manage')
      view_users = create(:escalated_permission, slug: 'user.view')
      role = create(:escalated_role)
      role.permissions << [manage, view_users]
      role.users << admin
      Escalated.configuration.access = { roles_permissions: true }

      sign_in_as(admin)
      get '/support/admin/skills'

      expect(response).to have_http_status(:ok)
      props = inertia_props_from(response.body)
      expect(props.dig('escalated', 'permissions')).to contain_exactly('newsletters.manage', 'user.view')
    ensure
      Escalated.configuration.access = {}
    end
  end
end
