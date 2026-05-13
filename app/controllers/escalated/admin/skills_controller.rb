# frozen_string_literal: true

module Escalated
  module Admin
    class SkillsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_skill, only: %i[edit update destroy]

      def index
        skills = Escalated::Skill.ordered
        skill_ids = skills.map(&:id)

        agents_counts = skill_ids.any? ? agents_counts_by_skill_id(skill_ids) : {}
        routing_tag_counts = skill_ids.any? ? Escalated::SkillRoutingTag.where(skill_id: skill_ids).group(:skill_id).count : {}
        routing_department_counts = skill_ids.any? ? Escalated::SkillRoutingDepartment.where(skill_id: skill_ids).group(:skill_id).count : {}

        render_page 'Escalated/Admin/Skills/Index', {
          skills: skills.map do |s|
            skill_json(s,
                       agents_count: agents_counts[s.id] || 0,
                       routing_tags_count: routing_tag_counts[s.id] || 0,
                       routing_departments_count: routing_department_counts[s.id] || 0)
          end
        }
      end

      def new
        render_page 'Escalated/Admin/Skills/Form', form_context_props.merge(skill: nil)
      end

      def edit
        render_page 'Escalated/Admin/Skills/Form', form_context_props.merge(skill: skill_form_json(@skill))
      end

      def create
        skill = Escalated::Skill.new(skill_field_attributes)
        ActiveRecord::Base.transaction do
          skill.save!
          sync_skill_associations(skill, association_params)
        end
        redirect_to escalated.admin_skills_path, notice: I18n.t('escalated.admin.skill.created')
      rescue ActiveRecord::RecordInvalid => e
        redirect_back_or_to(escalated.admin_skills_path, alert: e.record.errors.full_messages.join(', '))
      end

      def update
        ActiveRecord::Base.transaction do
          @skill.update!(skill_field_attributes)
          sync_skill_associations(@skill, association_params)
        end
        redirect_to escalated.admin_skills_path, notice: I18n.t('escalated.admin.skill.updated')
      rescue ActiveRecord::RecordInvalid => e
        redirect_back_or_to(escalated.admin_skills_path, alert: e.record.errors.full_messages.join(', '))
      end

      def destroy
        @skill.destroy!
        redirect_to escalated.admin_skills_path, notice: I18n.t('escalated.admin.skill.deleted')
      end

      private

      def set_skill
        @skill = Escalated::Skill.find(params[:id])
      end

      def skill_param_source
        nested = params[:skill]
        nested.is_a?(ActionController::Parameters) && nested.present? ? nested : params
      end

      def skill_field_attributes
        skill_param_source.permit(:name, :description)
      end

      def association_params
        skill_param_source.permit(routing_tag_ids: [], routing_department_ids: [], agents: %i[user_id proficiency])
      end

      def sync_skill_associations(skill, payload)
        tag_ids = Array(payload[:routing_tag_ids]).compact_blank.map(&:to_i)
        dept_ids = Array(payload[:routing_department_ids]).compact_blank.map(&:to_i)

        skill.tag_ids = tag_ids
        skill.department_ids = dept_ids
        sync_agent_skills(skill, payload[:agents])
        skill.save!
      end

      def sync_agent_skills(skill, agents_param)
        skill.agent_skills.delete_all
        return if agents_param.blank?

        agents_param.each do |row|
          h = if row.respond_to?(:permit)
                row.permit(:user_id, :proficiency).to_h
              else
                row.to_h
              end
          h = h.symbolize_keys
          uid = h[:user_id]
          next if uid.blank?

          proficiency = h[:proficiency].nil? ? 3 : h[:proficiency].to_i
          proficiency = 3 unless (1..5).cover?(proficiency)

          skill.agent_skills.create!(user_id: uid, proficiency: proficiency)
        end
      end

      def agents_counts_by_skill_id(skill_ids)
        return {} if skill_ids.empty?

        Escalated::AgentSkill
          .where(skill_id: skill_ids)
          .group_by(&:skill_id)
          .transform_values { |rows| rows.map(&:user_id).uniq.size }
      end

      def form_context_props
        {
          availableAgents: available_agents,
          availableTags: available_tags,
          availableDepartments: available_departments
        }
      end

      def available_agents
        if Escalated.configuration.user_model.respond_to?(:escalated_agents)
          Escalated.configuration.user_model.escalated_agents.order(:name).map do |a|
            { id: a.id, name: a.respond_to?(:name) ? a.name : a.email, email: a.email }
          end
        else
          []
        end
      end

      def available_tags
        Escalated::Tag.ordered.map { |t| { id: t.id, name: t.name } }
      end

      def available_departments
        Escalated::Department.ordered.map { |d| { id: d.id, name: d.name } }
      end

      def skill_json(skill, agents_count:, routing_tags_count:, routing_departments_count:)
        {
          id: skill.id,
          name: skill.name,
          agents_count: agents_count,
          routing_tags_count: routing_tags_count,
          routing_departments_count: routing_departments_count,
          updated_at: skill.updated_at&.iso8601
        }
      end

      def skill_form_json(skill)
        skill = Escalated::Skill.includes(:tags, :departments, :agent_skills).find(skill.id)
        {
          id: skill.id,
          name: skill.name,
          description: skill.description,
          routing_tag_ids: skill.tags.pluck(:id),
          routing_department_ids: skill.departments.pluck(:id),
          agents: skill.agent_skills.map { |as| { user_id: as.user_id, proficiency: as.proficiency } }
        }
      end
    end
  end
end
