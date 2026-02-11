require "json"
require "fileutils"

module Escalated
  module Services
    class PluginService
      class << self
        # ================================================================
        # Discovery
        # ================================================================

        # Get all installed plugins with their metadata, merged with
        # database activation state. Combines local (filesystem) plugins
        # and gem-based plugins.
        #
        # @return [Array<Hash>]
        def all_plugins
          local_plugins + gem_plugins
        end

        # Return slugs of all currently activated plugins.
        #
        # @return [Array<String>]
        def activated_plugins
          Escalated::Plugin.active.pluck(:slug)
        rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
          Rails.logger.debug("[Escalated::PluginService] Could not query plugins table: #{e.message}")
          []
        end

        # ================================================================
        # Lifecycle
        # ================================================================

        # Activate a plugin by slug.
        #
        # Creates the database record if it doesn't exist, loads the plugin
        # file, and fires activation hooks.
        #
        # @param slug [String]
        # @return [Boolean]
        def activate_plugin(slug)
          validate_plugin_exists!(slug)

          plugin = Escalated::Plugin.find_or_create_by!(slug: slug) do |p|
            p.is_active = false
          end

          unless plugin.is_active
            plugin.update!(
              is_active: true,
              activated_at: Time.current,
              deactivated_at: nil
            )

            # Load the plugin so its hooks are registered
            load_plugin(slug)

            # Fire activation hooks
            Escalated.hooks.do_action("plugin_activated", slug)
            Escalated.hooks.do_action("plugin_activated_#{slug}")
          end

          true
        end

        # Deactivate a plugin by slug.
        #
        # Fires deactivation hooks *before* flipping the flag so the
        # plugin code can still run teardown logic.
        #
        # @param slug [String]
        # @return [Boolean]
        def deactivate_plugin(slug)
          plugin = Escalated::Plugin.find_by(slug: slug)

          if plugin&.is_active
            Escalated.hooks.do_action("plugin_deactivated", slug)
            Escalated.hooks.do_action("plugin_deactivated_#{slug}")

            plugin.update!(
              is_active: false,
              deactivated_at: Time.current
            )
          end

          true
        end

        # Delete a plugin entirely.
        #
        # Fires uninstall hooks, deactivates, removes the database record,
        # and deletes the plugin directory from disk. Gem-sourced plugins
        # cannot be deleted -- remove them via Bundler instead.
        #
        # @param slug [String]
        # @return [Boolean]
        def delete_plugin(slug)
          all = all_plugins
          plugin_data = all.find { |p| p[:slug] == slug }
          if plugin_data && plugin_data[:source] == :composer
            raise "Gem plugins cannot be deleted. Remove the gem via Bundler instead."
          end

          plugin_dir = File.join(plugins_path, slug)
          return false unless File.directory?(plugin_dir)

          plugin = Escalated::Plugin.find_by(slug: slug)

          # Load plugin so its uninstall hooks can run
          load_plugin(slug) if plugin&.is_active

          # Fire uninstall hooks
          Escalated.hooks.do_action("plugin_uninstalling", slug)
          Escalated.hooks.do_action("plugin_uninstalling_#{slug}")

          # Deactivate first if active
          deactivate_plugin(slug)

          # Remove database record
          plugin&.destroy

          # Remove directory
          FileUtils.rm_rf(plugin_dir)

          true
        end

        # Upload a plugin from a ZIP file.
        #
        # Extracts the archive into the plugins directory and validates
        # the presence of a plugin.json manifest.
        #
        # @param file [ActionDispatch::Http::UploadedFile]
        # @return [Hash] :slug and :path of the extracted plugin
        def upload_plugin(file)
          require "zip"

          temp_path = File.join(Dir.tmpdir, file.original_filename)
          File.open(temp_path, "wb") { |f| f.write(file.read) }

          root_folder = nil

          Zip::File.open(temp_path) do |zip|
            zip.each do |entry|
              if entry.name.include?("/")
                root_folder = entry.name.split("/").first
                break
              end
            end

            raise "Invalid plugin structure" if root_folder.blank?

            extract_path = File.join(plugins_path, root_folder)
            raise "Plugin already exists" if File.directory?(extract_path)

            zip.each do |entry|
              dest = File.join(plugins_path, entry.name)
              FileUtils.mkdir_p(File.dirname(dest))
              entry.extract(dest)
            end

            manifest_path = File.join(extract_path, "plugin.json")
            unless File.exist?(manifest_path)
              FileUtils.rm_rf(extract_path)
              raise "Invalid plugin: missing plugin.json"
            end
          end

          FileUtils.rm_f(temp_path)

          {
            slug: root_folder,
            path: File.join(plugins_path, root_folder),
          }
        end

        # ================================================================
        # Boot
        # ================================================================

        # Load all active plugins. Called once during engine initialization.
        #
        # @return [void]
        def load_active_plugins
          activated_plugins.each { |slug| load_plugin(slug) }
        end

        # Load a specific plugin by requiring its main file.
        #
        # Resolves the plugin path from both local and gem sources.
        #
        # @param slug [String]
        # @return [void]
        def load_plugin(slug)
          plugin_dir = resolve_plugin_path(slug)
          return unless plugin_dir

          manifest_path = File.join(plugin_dir, "plugin.json")
          return unless File.exist?(manifest_path)

          manifest = parse_manifest(manifest_path)
          return unless manifest

          main_file = manifest["main_file"] || "plugin.rb"
          plugin_file = File.join(plugin_dir, main_file)

          if File.exist?(plugin_file)
            load plugin_file
            Escalated.hooks.do_action("plugin_loaded", slug, manifest)
          end
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginService] Failed to load plugin #{slug}: #{e.message}")
        end

        # ================================================================
        # Helpers
        # ================================================================

        # Absolute path to the plugins directory.
        #
        # @return [String]
        def plugins_path
          path = Escalated.configuration.plugins_path
          FileUtils.mkdir_p(path) unless File.directory?(path)
          path
        end

        private

        def parse_manifest(path)
          JSON.parse(File.read(path))
        rescue JSON::ParserError => e
          Rails.logger.error("[Escalated::PluginService] Invalid plugin.json at #{path}: #{e.message}")
          nil
        end

        def validate_plugin_exists!(slug)
          plugin_dir = resolve_plugin_path(slug)
          raise "Plugin not found: #{slug}" unless plugin_dir
          raise "Plugin manifest not found: #{slug}/plugin.json" unless File.exist?(File.join(plugin_dir, "plugin.json"))
        end

        def local_plugins
          plugins = []

          Dir.glob(File.join(plugins_path, "*")).select { |f| File.directory?(f) }.each do |directory|
            slug = File.basename(directory)
            manifest_path = File.join(directory, "plugin.json")
            next unless File.exist?(manifest_path)

            manifest = parse_manifest(manifest_path)
            next unless manifest

            db_plugin = Escalated::Plugin.find_by(slug: slug)

            plugins << {
              slug: slug,
              name: manifest["name"] || slug.titleize,
              description: manifest["description"] || "",
              version: manifest["version"] || "1.0.0",
              author: manifest["author"] || "Unknown",
              author_url: manifest["author_url"] || "",
              requires: manifest["requires"] || "1.0.0",
              main_file: manifest["main_file"] || "plugin.rb",
              is_active: db_plugin&.is_active || false,
              activated_at: db_plugin&.activated_at,
              path: directory,
              source: :local,
            }
          end

          plugins
        end

        def gem_plugins
          plugins = []
          Gem::Specification.each do |spec|
            manifest_path = File.join(spec.gem_dir, "plugin.json")
            next unless File.exist?(manifest_path)

            manifest = parse_manifest(manifest_path)
            next unless manifest

            slug = spec.name
            db_plugin = Escalated::Plugin.find_by(slug: slug)

            plugins << {
              slug: slug,
              name: manifest["name"] || slug.titleize,
              description: manifest["description"] || "",
              version: manifest["version"] || "1.0.0",
              author: manifest["author"] || "Unknown",
              author_url: manifest["author_url"] || "",
              requires: manifest["requires"] || "1.0.0",
              main_file: manifest["main_file"] || "plugin.rb",
              is_active: db_plugin&.is_active || false,
              activated_at: db_plugin&.activated_at,
              path: spec.gem_dir,
              source: :composer,  # Use :composer for consistency with frontend
            }
          end
          plugins
        rescue => e
          Rails.logger.debug("[Escalated::PluginService] Could not scan gems: #{e.message}")
          []
        end

        def resolve_plugin_path(slug)
          # Check local plugins first
          local_path = File.join(plugins_path, slug)
          return local_path if File.exist?(File.join(local_path, "plugin.json"))

          # Check gem plugins
          begin
            spec = Gem::Specification.find_by_name(slug)
            gem_path = spec.gem_dir
            return gem_path if File.exist?(File.join(gem_path, "plugin.json"))
          rescue Gem::MissingSpecError
            # Not a gem plugin
          end

          nil
        end
      end
    end
  end
end
