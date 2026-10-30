# frozen_string_literal: true

module Escalated
  module Admin
    class PluginsController < Escalated::ApplicationController
      before_action :require_admin!

      def index
        plugins = Escalated::Services::PluginService.all_plugins

        render_page 'Escalated/Admin/Plugins/Index', {
          plugins: plugins.map { |p| plugin_json(p) },
          can_upload: true
        }
      end

      def upload
        if params[:plugin].blank?
          redirect_back_or_to(admin_plugins_path, alert: 'Please select a plugin ZIP file to upload.')
          return
        end

        begin
          Escalated::Services::PluginService.upload_plugin(params[:plugin])

          redirect_to admin_plugins_path,
                      notice: 'Plugin uploaded successfully. You can now activate it.'
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginsController] Upload failed: #{e.message}")
          redirect_back_or_to(admin_plugins_path, alert: "Failed to upload plugin: #{e.message}")
        end
      end

      def activate
        Escalated::Services::PluginService.activate_plugin(params[:id])

        redirect_to admin_plugins_path, status: :see_other, flash: { success: 'Plugin activated successfully.' }
      rescue Escalated::Services::PluginService::UnknownPlugin => e
        unknown_plugin(e)
      rescue StandardError => e
        Rails.logger.error("[Escalated::PluginsController] Activation failed: #{e.message}")
        redirect_to admin_plugins_path, status: :see_other, flash: { error: "Failed to activate plugin: #{e.message}" }
      end

      def deactivate
        Escalated::Services::PluginService.deactivate_plugin(params[:id])

        redirect_to admin_plugins_path, status: :see_other, flash: { success: 'Plugin deactivated successfully.' }
      rescue Escalated::Services::PluginService::UnknownPlugin => e
        unknown_plugin(e)
      rescue StandardError => e
        Rails.logger.error("[Escalated::PluginsController] Deactivation failed: #{e.message}")
        redirect_to admin_plugins_path, status: :see_other,
                                        flash: { error: "Failed to deactivate plugin: #{e.message}" }
      end

      def destroy
        # Check if plugin is gem-sourced before attempting delete
        all_plugins = Escalated::Services::PluginService.all_plugins
        plugin_data = all_plugins.find { |p| p[:slug] == params[:id] }

        if plugin_data && plugin_data[:source] == :composer
          redirect_back_or_to(admin_plugins_path,
                              alert: 'Gem plugins cannot be deleted. Remove the gem via Bundler instead.')
          return
        end

        Escalated::Services::PluginService.delete_plugin(params[:id])

        redirect_back_or_to(admin_plugins_path, notice: 'Plugin deleted successfully.')
      rescue StandardError => e
        Rails.logger.error("[Escalated::PluginsController] Deletion failed: #{e.message}")
        redirect_back_or_to(admin_plugins_path, alert: "Failed to delete plugin: #{e.message}")
      end

      private

      def admin_plugins_path
        escalated.admin_plugins_path
      end

      # An unknown slug: an error flash, or a 404 for a JSON request.
      def unknown_plugin(error)
        if request.format.json? && request.headers['X-Inertia'].blank?
          render json: { error: error.message }, status: :not_found
        else
          redirect_to admin_plugins_path, status: :see_other, flash: { error: error.message }
        end
      end

      def plugin_json(plugin)
        {
          slug: plugin[:slug],
          name: plugin[:name],
          description: plugin[:description],
          version: plugin[:version],
          author: plugin[:author],
          author_url: plugin[:author_url],
          requires: plugin[:requires],
          is_active: plugin[:is_active],
          activated_at: plugin[:activated_at]&.iso8601,
          source: (plugin[:source] || :local).to_s
        }.merge(plugin.slice(:homepage, :provides))
      end
    end
  end
end
