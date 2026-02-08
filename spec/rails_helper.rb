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

  # Database Cleaner
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
