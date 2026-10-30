# frozen_string_literal: true

module Escalated
  # Roles & permissions (ADR 2026-10-29-configurable-access-features).
  #
  # A user's permissions are the union of their Escalated roles' permissions
  # (role_users and role_permissions). Nothing else grants one: not the host's
  # admin or agent gate, not is_admin. While the switch is off the gates decide
  # everything and every check here passes.
  module AccessControl
    extend ActiveSupport::Concern

    # Every permission slug the user's roles grant; [] without any.
    def self.permission_slugs(user_id)
      return [] if user_id.blank?

      Escalated::Permission.joins(roles: :users)
                           .where(Escalated.table_name('role_users') => { user_id: user_id })
                           .distinct
                           .pluck(:slug)
                           .sort
    rescue ActiveRecord::StatementInvalid
      []
    end

    # Whether the user may do what the permission covers: always while the
    # switch is off (the gates decide), else only with a role granting it.
    def self.allows?(user_id, slug)
      return true unless Escalated::Support::AccessFeatures.roles_permissions?

      permission_slugs(user_id).include?(slug.to_s)
    end

    # Gives a user (email or id) an Escalated role by slug, keeping their other
    # roles: how the first admin is bootstrapped before switching roles on.
    def self.assign_role!(user_ref, role_slug)
      model = Escalated.configuration.user_model
      user = model.find_by(email: user_ref) || (user_ref.to_s.match?(/\A\d+\z/) && model.find_by(id: user_ref))
      raise ArgumentError, "No user [#{user_ref}]." unless user

      role = Escalated::Role.find_by(slug: role_slug)
      raise ArgumentError, "No role [#{role_slug}]. Run rake escalated:permissions:seed first." unless role

      role.users << user unless role.users.exists?(user.id)
      user
    end

    private

    def access_control_user
      return escalated_current_user if respond_to?(:escalated_current_user, true)

      respond_to?(:current_user, true) ? current_user : nil
    end

    # The action's permissions (Escalated::Support::RoutePermissions) from the
    # user's roles, after the admin/agent gate or the API token admitted the
    # request. An action missing from the map is refused. Does nothing while off.
    def enforce_route_permissions!
      return true unless Escalated::Support::AccessFeatures.roles_permissions?

      user = access_control_user
      required = Escalated::Support::RoutePermissions.required_for(
        controller_path, action_name, params,
        bulk_action: request.request_parameters['action']
      )
      return deny_permission!('This route has no permission mapping.') if user.nil? || required.nil?

      missing = required - Escalated::AccessControl.permission_slugs(user.id)
      return true if missing.empty?

      deny_permission!("You do not have the required permission: #{missing.first}")
    end

    def deny_permission!(message)
      if request.format.json? || !respond_to?(:render_page, true)
        render json: { message: message }, status: :forbidden
      else
        render_page 'Escalated/Error', { status: 403, message: message }, status: :forbidden
      end
      false
    end

    # The `escalated.permissions` the shared frontend checks: the user's slugs
    # while on; ['*'] for staff while off; [] for anyone else.
    def shared_permissions(user, staff)
      return [] if user.nil?
      return (staff ? ['*'] : []) unless Escalated::Support::AccessFeatures.roles_permissions?

      Escalated::AccessControl.permission_slugs(user.id)
    end
  end
end
