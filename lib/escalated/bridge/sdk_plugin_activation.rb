# frozen_string_literal: true

module Escalated
  module Bridge
    # Which SDK plugins are active (domain-model/plugin-contract.md, Storage
    # and Lifecycle). SDK plugins share the escalated_plugins table with Ruby
    # ones, keyed by the contract's slug of their name; a plugin with no row
    # is inactive.
    #
    # The runtime loads every installed SDK plugin, so the host gates each
    # call by this: hooks, endpoints, webhooks, cron, badges and UI
    # extensions only reach active plugins.
    module SdkPluginActivation
      # Set once SDK plugins have been recorded. Before it, every SDK plugin
      # ran whether or not anyone activated it.
      RECORDED_SETTING = 'plugins_sdk_activation_recorded'

      module_function

      def slug(name)
        Escalated::Services::PluginUIService.slug(name)
      end

      # The names among +names+ whose plugins are active, in the given
      # order. Nothing is active when the table cannot be read.
      #
      # @return [Array<String>]
      def active_names(names)
        by_slug = Array(names).map(&:to_s).group_by { |name| slug(name) }
        return [] if by_slug.empty?

        active = Escalated::Plugin.where(slug: by_slug.keys, is_active: true).pluck(:slug)
        by_slug.slice(*(by_slug.keys & active)).values.flatten
      rescue StandardError => e
        Rails.logger.debug { "[Escalated::Plugins] Could not read SDK plugin activation: #{e.message}" }
        []
      end

      def active?(name)
        active_names([name]).any?
      end

      # Only the manifests of active plugins.
      #
      # @param manifests [Hash{String => Hash}] keyed by plugin name
      def active_manifests(manifests)
        manifests ||= {}
        manifests.slice(*active_names(manifests.keys))
      end

      # The first time SDK plugins are seen, record every one of them as
      # active, so an upgrade from a version that ran every SDK plugin does
      # not silently switch them off. Plugins installed later start inactive.
      def record_installed(names)
        names = Array(names)
        return if names.empty?
        return unless Escalated::EscalatedSetting.get(RECORDED_SETTING).nil?

        names.each do |name|
          Escalated::Plugin.find_or_create_by!(slug: slug(name)) do |plugin|
            plugin.is_active = true
            plugin.activated_at = Time.current
          end
        end
        Escalated::EscalatedSetting.set(RECORDED_SETTING, Time.current.iso8601)
      rescue StandardError => e
        # The tables may not exist yet (first migrate); try again next boot.
        Rails.logger.debug { "[Escalated::Plugins] Could not record installed SDK plugins: #{e.message}" }
      end
    end
  end
end
