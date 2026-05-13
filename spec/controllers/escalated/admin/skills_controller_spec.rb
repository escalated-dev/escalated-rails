# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

RSpec.describe 'Escalated::Admin::SkillsController', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-skills@example.test') }
  let(:agent) { create(:user, :agent, email: 'agent-skills@example.test', name: 'Skill Agent') }
  let(:tag) { create(:escalated_tag, name: 'routing-tag') }
  let(:department) { create(:escalated_department, name: 'Routing Dept') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    admin
    agent
    tag
    department
  end

  def sign_in_as(user)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
    # rubocop:enable RSpec/AnyInstance
  end

  # Inertia HTML responses JSON-encode the page inside data-page="..." (HTML-escaped).
  def inertia_props_from(body)
    encoded = body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))['props']
  end

  describe 'GET /support/admin/skills' do
    it 'renders the index for an admin' do
      skill = create(:escalated_skill, name: 'Listed Skill', slug: 'listed_skill')
      Escalated::SkillRoutingTag.create!(skill: skill, tag: tag)
      Escalated::SkillRoutingDepartment.create!(skill: skill, department: department)
      Escalated::AgentSkill.create!(user_id: agent.id, skill_id: skill.id, proficiency: 4)

      sign_in_as(admin)
      get '/support/admin/skills'

      expect(response).to have_http_status(:ok)
      body = response.body
      props = inertia_props_from(body)
      row = props['skills'].find { |s| s['name'] == 'Listed Skill' }
      expect(row).to include(
        'agents_count' => 1,
        'routing_tags_count' => 1,
        'routing_departments_count' => 1
      )
    end

    it 'counts distinct agents per skill via a single SQL aggregate' do
      skill_a = create(:escalated_skill, name: 'Skill A', slug: 'skill_a')
      skill_b = create(:escalated_skill, name: 'Skill B', slug: 'skill_b')
      other_agent = create(:user, :agent, email: 'agent-counts-2@example.test', name: 'Counts Agent')
      Escalated::AgentSkill.create!(user_id: agent.id, skill_id: skill_a.id, proficiency: 3)
      Escalated::AgentSkill.create!(user_id: other_agent.id, skill_id: skill_a.id, proficiency: 2)
      Escalated::AgentSkill.create!(user_id: agent.id, skill_id: skill_b.id, proficiency: 5)

      sign_in_as(admin)

      assert_queries_no_load_all = proc do
        get '/support/admin/skills'
      end
      assert_queries_no_load_all.call

      props = inertia_props_from(response.body)
      counts = props['skills'].to_h { |s| [s['name'], s['agents_count']] }
      expect(counts['Skill A']).to eq(2)
      expect(counts['Skill B']).to eq(1)
    end

    it 'redirects non-admins' do
      sign_in_as(agent)
      get '/support/admin/skills'
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'name uniqueness' do
    it 'rejects a skill whose name differs only in case' do
      create(:escalated_skill, name: 'Spanish', slug: 'spanish')

      sign_in_as(admin)
      expect do
        post '/support/admin/skills', params: { name: 'spanish' }
      end.not_to change(Escalated::Skill, :count)
    end
  end

  describe 'GET /support/admin/skills/new' do
    it 'renders the form with available collections' do
      sign_in_as(admin)
      get '/support/admin/skills/new'

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('Skill Agent')
      expect(body).to include('routing-tag')
      expect(body).to include('Routing Dept')
    end
  end

  describe 'GET /support/admin/skills/:id/edit' do
    it 'renders the form with the skill payload' do
      skill = create(:escalated_skill, name: 'Editable', slug: 'editable', description: 'Desc')
      Escalated::SkillRoutingTag.create!(skill: skill, tag: tag)
      Escalated::AgentSkill.create!(user_id: agent.id, skill_id: skill.id, proficiency: 2)

      sign_in_as(admin)
      get "/support/admin/skills/#{skill.id}/edit"

      expect(response).to have_http_status(:ok)
      body = response.body
      props = inertia_props_from(body)
      expect(props['skill']).to include(
        'name' => 'Editable',
        'description' => 'Desc'
      )
      expect(props['skill']['agents']).to eq([{ 'user_id' => agent.id, 'proficiency' => 2 }])
    end
  end

  describe 'POST /support/admin/skills' do
    it 'creates a skill with routing and agent proficiency' do
      sign_in_as(admin)
      expect do
        post '/support/admin/skills',
             params: {
               name: 'New Skill',
               description: 'About',
               routing_tag_ids: [tag.id],
               routing_department_ids: [department.id],
               agents: [{ user_id: agent.id, proficiency: 5 }]
             }
      end.to change(Escalated::Skill, :count).by(1)

      expect(response).to redirect_to('/support/admin/skills')
      skill = Escalated::Skill.find_by!(name: 'New Skill')
      expect(skill.description).to eq('About')
      expect(skill.tags).to contain_exactly(tag)
      expect(skill.departments).to contain_exactly(department)
      expect(skill.agent_skills.count).to eq(1)
      expect(skill.agent_skills.first.proficiency).to eq(5)
    end
  end

  describe 'PATCH /support/admin/skills/:id' do
    it 'updates associations transactionally' do
      skill = create(:escalated_skill, name: 'Old', slug: 'old_skill')
      Escalated::AgentSkill.create!(user_id: agent.id, skill_id: skill.id, proficiency: 1)

      sign_in_as(admin)
      patch "/support/admin/skills/#{skill.id}",
            params: {
              name: 'Renamed',
              routing_tag_ids: [tag.id],
              agents: [{ user_id: agent.id, proficiency: 4 }]
            }

      expect(response).to redirect_to('/support/admin/skills')
      skill.reload
      expect(skill.name).to eq('Renamed')
      expect(skill.tags).to contain_exactly(tag)
      expect(skill.agent_skills.first.proficiency).to eq(4)
    end
  end

  describe 'DELETE /support/admin/skills/:id' do
    it 'destroys the skill' do
      skill = create(:escalated_skill, name: 'Gone', slug: 'gone_skill')

      sign_in_as(admin)
      expect do
        delete "/support/admin/skills/#{skill.id}"
      end.to change(Escalated::Skill, :count).by(-1)

      expect(response).to redirect_to('/support/admin/skills')
    end
  end
end
