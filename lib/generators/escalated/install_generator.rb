require "rails/generators"
require "rails/generators/migration"

module Escalated
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Installs the Escalated support ticket system"

      def self.next_migration_number(dirname)
        Time.now.strftime("%Y%m%d%H%M%S")
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/escalated.rb"
        say_status :create, "config/initializers/escalated.rb", :green
      end

      def copy_migrations
        rake "escalated:install:migrations"
        say_status :info, "Copied migrations. Run `rails db:migrate` to apply.", :yellow
      end

      def add_user_concern
        inject_into_file(
          "app/models/user.rb",
          after: "class User < ApplicationRecord\n"
        ) do
          <<-RUBY
  # Escalated support system role methods
  # Customize these methods to match your authorization system
  def escalated_agent?
    # Return true if this user is a support agent
    respond_to?(:role) && %w[agent admin].include?(role)
  end

  def escalated_admin?
    # Return true if this user is a support admin
    respond_to?(:role) && role == "admin"
  end

  def self.escalated_agents
    # Return a scope of all support agents
    where(role: %w[agent admin])
  end

          RUBY
        end
        say_status :inject, "app/models/user.rb (Escalated role methods)", :green
      rescue StandardError => e
        say_status :skip, "Could not inject into User model: #{e.message}", :yellow
        say "  Add these methods to your User model manually:"
        say "    escalated_agent? - returns true for support agents"
        say "    escalated_admin? - returns true for support admins"
        say "    self.escalated_agents - scope returning all agents"
      end

      def show_post_install
        say ""
        say "Escalated installed successfully!", :green
        say ""
        say "Next steps:"
        say "  1. Run `rails db:migrate`"
        say "  2. Configure config/initializers/escalated.rb"
        say "  3. Add escalated_agent? and escalated_admin? methods to your User model"
        say "  4. Install Vue components: copy from vendor/escalated/resources/js/"
        say "  5. Set up your Inertia page resolver to include Escalated pages"
        say ""
      end
    end
  end
end
