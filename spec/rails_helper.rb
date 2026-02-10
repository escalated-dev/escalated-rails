require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

# Load the dummy Rails application for testing
require File.expand_path("dummy/config/environment", __dir__)

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"
require "shoulda-matchers"
require "database_cleaner/active_record"

# Load support files
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

# Load factories
Dir[File.join(__dir__, "factories", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.fixture_path = "#{__dir__}/fixtures"
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot
  config.include FactoryBot::Syntax::Methods

  # Run migrations in memory before the suite
  config.before(:suite) do
    # Run all migrations against the in-memory SQLite database
    ActiveRecord::Migration.verbose = false

    # Run the dummy app's user migration
    dummy_migrations_path = File.expand_path("dummy/db/migrate", __dir__)
    if File.directory?(dummy_migrations_path)
      ActiveRecord::MigrationContext.new(dummy_migrations_path).migrate
    end

    # Run the engine's migrations
    engine_migrations_path = File.expand_path("../db/migrate", __dir__)
    if File.directory?(engine_migrations_path)
      ActiveRecord::MigrationContext.new(engine_migrations_path).migrate
    end

    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  # Reset Escalated driver between tests to avoid stale state
  config.before(:each) do
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
