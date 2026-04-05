module Escalated
  module Admin
    class SkillsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_skill, only: [:update, :destroy]

      def index
        skills = Escalated::Skill.ordered

        render_page "Escalated/Admin/Skills/Index", {
          skills: skills.map { |s| skill_json(s) }
        }
      end

      def create
        skill = Escalated::Skill.new(skill_params)

        if skill.save
          redirect_to escalated.admin_skills_path, notice: I18n.t('escalated.admin.skill.created')
        else
          redirect_back fallback_location: escalated.admin_skills_path,
                        alert: skill.errors.full_messages.join(", ")
        end
      end

      def update
        if @skill.update(skill_params)
          redirect_to escalated.admin_skills_path, notice: I18n.t('escalated.admin.skill.updated')
        else
          redirect_back fallback_location: escalated.admin_skills_path,
                        alert: @skill.errors.full_messages.join(", ")
        end
      end

      def destroy
        @skill.destroy!
        redirect_to escalated.admin_skills_path, notice: I18n.t('escalated.admin.skill.deleted')
      end

      private

      def set_skill
        @skill = Escalated::Skill.find(params[:id])
      end

      def skill_params
        params.require(:skill).permit(:name, :description)
      end

      def skill_json(skill)
        {
          id: skill.id,
          name: skill.name,
          description: skill.description,
          agent_count: skill.respond_to?(:agent_profiles) ? skill.agent_profiles.count : 0,
          created_at: skill.created_at&.iso8601,
          updated_at: skill.updated_at&.iso8601
        }
      end
    end
  end
end
