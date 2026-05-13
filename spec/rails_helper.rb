# frozen_string_literal: true

require 'spec_helper'

ENV['RAILS_ENV'] ||= 'test'

# Load the dummy Rails application for testing
require File.expand_path('dummy/config/environment', __dir__)

# The dummy app does not include Devise (or similar); request specs stub #current_user on instances.
Escalated::ApplicationController.class_eval do
  def current_user
    nil
  end
end

require 'faker'
Faker::Config.locale = :en

abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
require 'factory_bot_rails'
require 'shoulda-matchers'
require 'database_cleaner/active_record'

# Load services from lib/ (not auto-loaded by Rails engine)
Dir[File.join(File.dirname(__dir__), 'lib', 'escalated', 'services', '*.rb')].each { |f| require f }

# Load support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

# Tell FactoryBot where to find factories
FactoryBot.definition_file_paths = [File.join(__dir__, 'factories')]
FactoryBot.find_definitions

RSpec.configure do |config|
  config.fixture_paths = ["#{__dir__}/fixtures"]
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot
  config.include FactoryBot::Syntax::Methods

  # Run migrations in memory before the suite
  config.before(:suite) do
    if defined?(I18n) && I18n.load_path
      # Keep only English-ish locale files from escalated-locale; some locale YAML files
      # break Psych on Windows + Ruby 3.4 during Faker-backed factory resolution.
      I18n.load_path.delete_if do |path|
        path.include?('escalated-locale') && !File.basename(path).start_with?('en')
      end
    end

    # Run all migrations against the in-memory SQLite database
    ActiveRecord::Migration.verbose = false

    # Run the dummy app's user migration
    dummy_migrations_path = File.expand_path('dummy/db/migrate', __dir__)
    ActiveRecord::MigrationContext.new(dummy_migrations_path).migrate if File.directory?(dummy_migrations_path)

    # Active Storage (required for Escalated::Attachment#has_one_attached in specs)
    astorage_migrations = ActiveStorage::Engine.root.join('db/migrate')
    ActiveRecord::MigrationContext.new(astorage_migrations).migrate if astorage_migrations.exist?

    # Run the engine's migrations
    engine_migrations_path = File.expand_path('../db/migrate', __dir__)
    ActiveRecord::MigrationContext.new(engine_migrations_path).migrate if File.directory?(engine_migrations_path)

    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.after do
    Faker::UniqueGenerator.clear
  end

  # Reset Escalated driver between tests to avoid stale state
  config.before do
    Escalated::Manager.reset_driver!
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
