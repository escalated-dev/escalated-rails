# frozen_string_literal: true

module Escalated
  module Admin
    # Surface enough of the host User table for an admin to grant or revoke
    # agent / admin access from the panel. The default install pins this to
    # the `is_admin` and `is_agent` columns the install generator tells hosts
    # to add — hosts using a different role implementation (Pundit, custom
    # role column, etc.) should override this controller in their own routes.
    class UsersController < Escalated::ApplicationController
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

        render_page 'Escalated/Admin/Users/Index', {
          users: {
            data: result[:data].map { |u| user_json(u) },
            meta: result[:meta]
          },
          filters: { search: search },
          currentUserId: current_user&.id
        }
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
