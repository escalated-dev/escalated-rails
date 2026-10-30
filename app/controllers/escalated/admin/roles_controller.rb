# frozen_string_literal: true

module Escalated
  module Admin
    class RolesController < Escalated::ApplicationController
      include Escalated::InertiaForms

      FIELDS = %i[name description].freeze

      # The roles screens exist only while roles & permissions is switched on
      # (ADR 2026-10-29-configurable-access-features); otherwise 404.
      before_action :ensure_roles_permissions_enabled!
      before_action :require_admin!
      before_action :set_role, only: %i[edit update destroy]

      def index
        roles = Escalated::Role.order(:name)
        user_counts = Escalated::Role.joins(:users).group("#{Escalated::Role.table_name}.id").count

        render_page 'Escalated/Admin/Roles/Index', {
          roles: roles.map { |r| role_json(r).merge(users_count: user_counts.fetch(r.id, 0)) }
        }
      end

      def new
        render_page 'Escalated/Admin/Roles/Form', {
          role: nil,
          permissions: grouped_permissions
        }
      end

      def edit
        render_page 'Escalated/Admin/Roles/Form', {
          role: role_json(@role).merge(permissions: @role.permissions.map { |p| permission_json(p) }),
          permissions: grouped_permissions
        }
      end

      def create
        role = Escalated::Role.new(role_params)
        return redirect_back_with_form_errors(name_required, escalated.new_admin_role_path) if role.name.blank?

        Escalated::Role.transaction do
          role.save!
          sync_permissions(role, permission_ids)
        end

        redirect_to escalated.admin_roles_path, notice: I18n.t('escalated.admin.role.created')
      rescue ActiveRecord::RecordInvalid
        redirect_back_with_form_errors(record_errors(role), escalated.new_admin_role_path)
      end

      def update
        @role.assign_attributes(role_params)
        return redirect_back_with_form_errors(name_required, escalated.edit_admin_role_path(@role)) if @role.name.blank?

        Escalated::Role.transaction do
          @role.save!
          # Laravel syncs to what was sent, so an empty list clears them. A body
          # with no list at all (an older caller) leaves them alone.
          sync_permissions(@role, permission_ids) unless permission_ids.nil?
        end

        redirect_to escalated.admin_roles_path, notice: I18n.t('escalated.admin.role.updated')
      rescue ActiveRecord::RecordInvalid
        redirect_back_with_form_errors(record_errors(@role), escalated.edit_admin_role_path(@role))
      end

      def destroy
        if @role.is_system?
          redirect_back_or_to(escalated.admin_roles_path, alert: I18n.t('escalated.admin.role.cannot_delete_system'))
          return
        end

        @role.destroy!
        redirect_to escalated.admin_roles_path, notice: I18n.t('escalated.admin.role.deleted')
      end

      private

      def ensure_roles_permissions_enabled!
        head :not_found unless Escalated::Support::AccessFeatures.roles_permissions?
      end

      def set_role
        @role = Escalated::Role.find(params[:id])
      end

      def role_params
        form_source(:role, FIELDS).permit(*FIELDS)
      end

      def name_required
        { 'name' => 'The name field is required.' }
      end

      # The form sends `permissions`; older callers sent `permission_ids`.
      # Either way a list of ids. nil when neither was sent.
      def permission_ids
        return @permission_ids if defined?(@permission_ids)

        raw = params.key?(:permissions) ? params[:permissions] : params[:permission_ids]
        @permission_ids = if raw.nil? && !params.key?(:permissions)
                            nil
                          else
                            Array(raw).map(&:to_i)
                          end
      end

      def sync_permissions(role, ids)
        return if ids.nil?

        role.permissions = Escalated::Permission.where(id: ids)
      end

      # The permission matrix reads permissions grouped by their group, as
      # Laravel's Permission::all()->groupBy('group') sends them.
      def grouped_permissions
        Escalated::Permission.ordered.group_by(&:group).transform_values do |perms|
          perms.map { |p| permission_json(p) }
        end
      end

      def role_json(role)
        {
          id: role.id,
          name: role.name,
          slug: role.slug,
          description: role.description,
          is_system: role.is_system?,
          created_at: role.created_at&.iso8601,
          updated_at: role.updated_at&.iso8601
        }
      end

      def permission_json(perm)
        {
          id: perm.id,
          name: perm.name,
          slug: perm.slug,
          group: perm.group,
          description: perm.description
        }
      end
    end
  end
end
