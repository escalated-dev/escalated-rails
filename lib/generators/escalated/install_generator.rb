require "rails/generators"
require "rails/generators/migration"

module Escalated
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc I18n.t('escalated.commands.install.installing', default: "Installs the Escalated support ticket system")

      def self.next_migration_number(dirname)
        Time.now.strftime("%Y%m%d%H%M%S")
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/escalated.rb"
        say_status :create, I18n.t('escalated.commands.install.create_initializer'), :green
      end

      def copy_migrations
        rake "escalated:install:migrations"
        say_status :info, I18n.t('escalated.commands.install.copy_migrations'), :yellow
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
        say_status :inject, I18n.t('escalated.commands.install.inject_user_model'), :green
      rescue StandardError => e
        say_status :skip, I18n.t('escalated.commands.install.inject_skip', error: e.message), :yellow
        say "  #{I18n.t('escalated.commands.install.inject_manual')}"
        say "    #{I18n.t('escalated.commands.install.inject_agent')}"
        say "    #{I18n.t('escalated.commands.install.inject_admin')}"
        say "    #{I18n.t('escalated.commands.install.inject_agents_scope')}"
      end

      def show_post_install
        say ""
        say I18n.t('escalated.commands.install.success'), :green
        say ""
        say I18n.t('escalated.commands.install.next_steps')
        say "  #{I18n.t('escalated.commands.install.step1')}"
        say "  #{I18n.t('escalated.commands.install.step2')}"
        say "  #{I18n.t('escalated.commands.install.step3')}"
        say "  #{I18n.t('escalated.commands.install.step4')}"
        say "  #{I18n.t('escalated.commands.install.step5')}"
        say ""
      end
    end
  end
end
