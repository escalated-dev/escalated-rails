# frozen_string_literal: true

module Escalated
  module Admin
    # Surface enough of the host User table for an admin to grant or revoke
    # agent / admin access from the panel. The default install pins this to
    # the `is_admin` and `is_agent` columns the install generator tells hosts
    # to add — hosts using a different role implementation (Pundit, custom
    # role column, etc.) should override this controller in their own routes.
    class UsersController < Escalated::ApplicationController
      include Escalated::InertiaForms

      # The roles picker exists only while roles & permissions is switched on
      # (ADR 2026-10-29-configurable-access-features); otherwise 404.
      before_action :ensure_roles_permissions_enabled!, only: :update_roles
      before_action :require_admin!

      def index
        search = filter_params[:search].to_s.strip
        scope  = user_class.all

        if search.present?
          term = "%#{search}%"
          conditions = ['email LIKE ?']
          values     = [term]
          if column_exists?('name')
            conditions << 'name LIKE ?'
            values     << term
          end
          scope = scope.where(conditions.join(' OR '), *values)
        end

        scope = scope.order(is_admin: :desc, is_agent: :desc, id: :asc)

        result = paginate(scope, per_page: 20)

        rows = result[:data].map { |u| user_json(u) }
        props = {
          users: { data: rows, meta: result[:meta] },
          filters: { search: search },
          currentUserId: current_user&.id
        }

        # Escalated roles, only while roles & permissions is enforced: each
        # user's role slugs, and the roles an admin can give them.
        if Escalated::Support::AccessFeatures.roles_permissions?
          roles = Escalated::Role.order(:name).to_a
          slugs = roles.to_h { |r| [r.id, r.slug] }
          assigned = role_user_rows(rows.pluck(:id))
          rows.each do |row|
            row[:roles] = assigned.fetch(row[:id].to_s, []).filter_map { |id| slugs[id] }.sort
          end
          props[:roles] = roles.map { |r| { id: r.id, name: r.name, slug: r.slug } }
        end

        render_page 'Escalated/Admin/Users/Index', props
      end

      # Replace a user's Escalated roles (roles & permissions on only), as
      # escalated-laravel's UserController#updateRoles.
      def update_roles
        role_ids = validated_role_ids
        return if performed?

        target = user_class.find(params.expect(:user_id))

        # Taking away your own role management would leave nobody able to undo it.
        if current_user && current_user.id.to_s == target.id.to_s &&
           !Escalated::Role.where(id: role_ids).joins(:permissions)
                           .exists?(Escalated::Permission.table_name => { slug: 'role.manage' })
          flash[:error] = I18n.t('escalated.admin.user.cannot_remove_own_role_management',
                                 default: 'You cannot remove your own role management.')
          redirect_back_or_to(escalated.admin_users_path)
          return
        end

        join = Escalated.table_name('role_users')
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.delete(
            ActiveRecord::Base.sanitize_sql_array(["DELETE FROM #{join} WHERE user_id = ?", target.id])
          )
          role_ids.each do |role_id|
            ActiveRecord::Base.connection.insert(
              ActiveRecord::Base.sanitize_sql_array(
                ["INSERT INTO #{join} (role_id, user_id) VALUES (?, ?)", role_id, target.id]
              )
            )
          end
        end

        flash[:success] = I18n.t('escalated.admin.user.updated', default: 'User updated.')
        redirect_back_or_to(escalated.admin_users_path)
      end

      def update_role
        attrs = role_params
        role  = attrs[:role].to_s
        value = ActiveModel::Type::Boolean.new.cast(attrs[:value])

        unless %w[admin agent].include?(role)
          redirect_back_or_to(escalated.admin_users_path,
                              alert: I18n.t('escalated.admin.user.invalid_role',
                                            default: 'Invalid role.'))
          return
        end

        target = user_class.find(params.expect(:user_id))

        # Don't let an admin demote themselves and lock themselves out of
        # the admin panel they're trying to use.
        if role == 'admin' && !value && current_user && current_user.id.to_s == target.id.to_s
          flash[:error] = I18n.t('escalated.admin.user.cannot_self_demote',
                                 default: 'You cannot remove your own admin role.')
          redirect_back_or_to(escalated.admin_users_path)
          return
        end

        updates = {}
        if role == 'admin'
          updates[:is_admin] = value
          # Admins are agents; flipping admin off does not also revoke agent
          # (an ex-admin can still answer tickets unless explicitly demoted).
          updates[:is_agent] = true if value
        else
          updates[:is_agent] = value
          if !value && target.respond_to?(:is_admin) && target.is_admin
            # Revoking agent from an admin would leave the admin gate on
            # but the agent gate off — confusing. Demote them fully.
            updates[:is_admin] = false
          end
        end

        target.update!(updates)

        flash[:success] = I18n.t('escalated.admin.user.updated', default: 'User updated.')
        redirect_back_or_to(escalated.admin_users_path)
      end

      private

      def ensure_roles_permissions_enabled!
        head :not_found unless Escalated::Support::AccessFeatures.roles_permissions?
      end

      # Laravel's rules: role_ids present and an array of integers that are
      # existing roles. Goes back with the errors on their keys otherwise.
      def validated_role_ids
        raw = request.request_parameters.key?('role_ids') ? request.request_parameters['role_ids'] : params[:role_ids]
        errors = role_ids_errors(raw)
        if errors.any?
          redirect_back_with_form_errors(errors, escalated.admin_users_path)
          return []
        end

        raw.map { |v| Integer(v.to_s, 10) }.uniq
      end

      def role_ids_errors(raw)
        return { 'role_ids' => 'The role ids field must be present.' } if raw.nil?
        return { 'role_ids' => 'The role ids field must be an array.' } unless raw.is_a?(Array)

        raw.each_with_index do |value, index|
          unless value.is_a?(Integer) || value.to_s.match?(/\A-?\d+\z/)
            return { "role_ids.#{index}" => "The role_ids.#{index} field must be an integer." }
          end
          next if Escalated::Role.exists?(id: value.to_i)

          return { "role_ids.#{index}" => "The selected role_ids.#{index} is invalid." }
        end
        {}
      end

      # { user_id (string) => [role_id, ...] } from the role_users join table.
      def role_user_rows(user_ids)
        return {} if user_ids.empty?

        Escalated::Role.joins(:users)
                       .where(Escalated.table_name('role_users') => { user_id: user_ids })
                       .pluck(Arel.sql("#{Escalated.table_name('role_users')}.user_id"), :id)
                       .group_by { |user_id, _| user_id.to_s }
                       .transform_values { |pairs| pairs.map(&:last) }
      end

      def filter_params
        params.permit(:search)
      end

      def role_params
        params.permit(:role, :value)
      end

      def user_class
        Escalated.configuration.user_model
      end

      def column_exists?(name)
        user_class.column_names.include?(name)
      rescue StandardError
        true
      end

      def user_json(user)
        {
          id: user.id,
          name: user.respond_to?(:name) ? user.name : nil,
          email: user.email,
          is_admin: user.respond_to?(:is_admin) && user.is_admin ? true : false,
          is_agent: user.respond_to?(:is_agent) && user.is_agent ? true : false
        }
      end
    end
  end
end
