module Escalated
  module Admin
    class RolesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_role, only: [:update, :destroy]

      def index
        roles = Escalated::Role.includes(:permissions).ordered

        render inertia: "Escalated/Admin/Roles/Index", props: {
          roles: roles.map { |r| role_json(r) },
          permissions: Escalated::Permission.ordered.map { |p| permission_json(p) }
        }
      end

      def create
        role = Escalated::Role.new(role_params)

        if role.save
          sync_permissions(role, params[:permission_ids])
          redirect_to escalated.admin_roles_path, notice: I18n.t('escalated.admin.role.created')
        else
          redirect_back fallback_location: escalated.admin_roles_path,
                        alert: role.errors.full_messages.join(", ")
        end
      end

      def update
        if @role.update(role_params)
          sync_permissions(@role, params[:permission_ids])
          redirect_to escalated.admin_roles_path, notice: I18n.t('escalated.admin.role.updated')
        else
          redirect_back fallback_location: escalated.admin_roles_path,
                        alert: @role.errors.full_messages.join(", ")
        end
      end

      def destroy
        if @role.is_system?
          redirect_back fallback_location: escalated.admin_roles_path,
                        alert: I18n.t('escalated.admin.role.cannot_delete_system')
          return
        end

        @role.destroy!
        redirect_to escalated.admin_roles_path, notice: I18n.t('escalated.admin.role.deleted')
      end

      private

      def set_role
        @role = Escalated::Role.find(params[:id])
      end

      def role_params
        params.require(:role).permit(:name, :description)
      end

      def sync_permissions(role, permission_ids)
        return unless permission_ids.is_a?(Array)

        role.permissions = Escalated::Permission.where(id: permission_ids)
      end

      def role_json(role)
        {
          id: role.id,
          name: role.name,
          description: role.description,
          is_system: role.is_system?,
          permissions: role.permissions.map { |p| permission_json(p) },
          created_at: role.created_at&.iso8601,
          updated_at: role.updated_at&.iso8601
        }
      end

      def permission_json(perm)
        {
          id: perm.id,
          name: perm.name,
          description: perm.description,
          resource: perm.resource,
          action: perm.action
        }
      end
    end
  end
end
