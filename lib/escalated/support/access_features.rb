# frozen_string_literal: true

module Escalated
  module Support
    # The install-level access switches (ADR
    # 2026-10-29-configurable-access-features): roles & permissions, two-factor
    # and SSO. Read from configuration (`config.access`), else the
    # ESCALATED_* env var, else off. Never from the settings table: each one
    # changes who may sign in or what they may do.
    module AccessFeatures
      FEATURES = {
        roles_permissions: 'ESCALATED_ROLES_PERMISSIONS',
        two_factor: 'ESCALATED_TWO_FACTOR',
        sso: 'ESCALATED_SSO'
      }.freeze

      TRUE_VALUES = %w[1 true yes on].freeze

      module_function

      def enabled?(feature)
        env = FEATURES.fetch(feature.to_sym)
        configured = (Escalated.configuration.access || {}).to_h.transform_keys(&:to_sym)[feature.to_sym]
        value = configured.nil? ? ENV.fetch(env, nil) : configured
        value == true || TRUE_VALUES.include?(value.to_s.strip.downcase)
      end

      def roles_permissions?
        enabled?(:roles_permissions)
      end

      def two_factor?
        enabled?(:two_factor)
      end

      def sso?
        enabled?(:sso)
      end

      # The `escalated.features` entries the shared frontend reads.
      def shared
        { roles_permissions: roles_permissions?, two_factor: two_factor?, sso: sso? }
      end
    end
  end
end
