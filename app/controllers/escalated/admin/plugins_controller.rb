module Escalated
  module Admin
    class PluginsController < Escalated::ApplicationController
      before_action :require_admin!

      def index
        plugins = Escalated::Services::PluginService.all_plugins

        render inertia: "Escalated/Admin/Plugins/Index", props: {
          plugins: plugins.map { |p| plugin_json(p) }
        }
      end

      def upload
        unless params[:plugin].present?
          redirect_back fallback_location: admin_plugins_path,
                        alert: "Please select a plugin ZIP file to upload."
          return
        end

        begin
          result = Escalated::Services::PluginService.upload_plugin(params[:plugin])

          redirect_to admin_plugins_path,
                      notice: "Plugin uploaded successfully. You can now activate it."
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginsController] Upload failed: #{e.message}")
          redirect_back fallback_location: admin_plugins_path,
                        alert: "Failed to upload plugin: #{e.message}"
        end
      end

      def activate
        begin
          Escalated::Services::PluginService.activate_plugin(params[:id])

          redirect_back fallback_location: admin_plugins_path,
                        notice: "Plugin activated successfully."
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginsController] Activation failed: #{e.message}")
          redirect_back fallback_location: admin_plugins_path,
                        alert: "Failed to activate plugin: #{e.message}"
        end
      end

      def deactivate
        begin
          Escalated::Services::PluginService.deactivate_plugin(params[:id])

          redirect_back fallback_location: admin_plugins_path,
                        notice: "Plugin deactivated successfully."
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginsController] Deactivation failed: #{e.message}")
          redirect_back fallback_location: admin_plugins_path,
                        alert: "Failed to deactivate plugin: #{e.message}"
        end
      end

      def destroy
        begin
          Escalated::Services::PluginService.delete_plugin(params[:id])

          redirect_back fallback_location: admin_plugins_path,
                        notice: "Plugin deleted successfully."
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginsController] Deletion failed: #{e.message}")
          redirect_back fallback_location: admin_plugins_path,
                        alert: "Failed to delete plugin: #{e.message}"
        end
      end

      private

      def admin_plugins_path
        escalated.admin_plugins_path
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
        }
      end
    end
  end
end
