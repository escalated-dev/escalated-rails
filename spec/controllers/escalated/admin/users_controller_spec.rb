# frozen_string_literal: true

require 'rails_helper'

# Mirrors escalated-laravel's tests/Feature/Admin/UserControllerTest.php (PR #94)
# for the host User management surface.
RSpec.describe 'Escalated::Admin::UsersController', type: :request do
  let(:admin)     { create(:user, :admin,    email: 'admin@example.com') }
  let(:agent)     { create(:user, :agent,    email: 'agent@example.com') }
  let(:customer)  { create(:user,            email: 'customer@example.com') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
  end

  def sign_in_as(user)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController)
      .to receive(:current_user).and_return(user)
    # rubocop:enable RSpec/AnyInstance
  end

  describe 'GET /support/admin/users' do
    it 'lists users with their admin/agent flags for an admin' do
      admin
      customer
      agent

      sign_in_as(admin)
      get '/support/admin/users'

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('admin@example.com')
      expect(body).to include('customer@example.com')
      expect(body).to include('agent@example.com')
    end

    it 'blocks non-admins from the user list' do
      sign_in_as(agent)
      get '/support/admin/users'

      # require_admin! redirects to the host root with an alert.
      expect(response).to have_http_status(:redirect)
    end

    it 'filters users by search term' do
      admin
      jane = create(:user, email: 'jane@acme.test', name: 'Jane Acme')
      bob  = create(:user, email: 'bob@globex.test', name: 'Bob Globex')

      sign_in_as(admin)
      get '/support/admin/users', params: { search: 'acme' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(jane.email)
      expect(response.body).not_to include(bob.email)
    end
  end

  describe 'PATCH /support/admin/users/:user_id/role' do
    it 'promotes a user to admin (sets is_admin and is_agent)' do
      target = create(:user, email: 'someone@example.com')

      sign_in_as(admin)
      patch "/support/admin/users/#{target.id}/role",
            params: { role: 'admin', value: true }

      expect(response).to have_http_status(:redirect)
      target.reload
      expect(target.is_admin).to be true
      expect(target.is_agent).to be true
    end

    it 'promotes a user to agent only' do
      target = create(:user, email: 'someone2@example.com')

      sign_in_as(admin)
      patch "/support/admin/users/#{target.id}/role",
            params: { role: 'agent', value: true }

      expect(response).to have_http_status(:redirect)
      target.reload
      expect(target.is_agent).to be true
      expect(target.is_admin).to be false
    end

    it 'prevents admins from demoting themselves' do
      sign_in_as(admin)
      patch "/support/admin/users/#{admin.id}/role",
            params: { role: 'admin', value: false }

      expect(response).to have_http_status(:redirect)
      admin.reload
      expect(admin.is_admin).to be true
    end

    it 'demotes an admin and turns off agent in one step' do
      target = create(:user, :admin, email: 'someone3@example.com')

      sign_in_as(admin)
      patch "/support/admin/users/#{target.id}/role",
            params: { role: 'agent', value: false }

      expect(response).to have_http_status(:redirect)
      target.reload
      expect(target.is_agent).to be false
      expect(target.is_admin).to be false
    end
  end
end
