# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'escalated-locale',
    git: 'https://github.com/escalated-dev/escalated-locale.git',
    glob: 'packages/rubygems/escalated-locale.gemspec',
    tag: 'v0.1.8'

# Exercise current JSON releases with the Rails versions resolved by CI.
# The SQLite, PostgreSQL and MySQL suites cover JSON 3 compatibility.
# This test dependency does not constrain host applications via the gemspec.
gem 'json', '< 4.0'

gem 'rexml'
gem 'tzinfo-data'

group :development, :test do
  gem 'database_cleaner-active_record'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'shoulda-matchers'
  gem 'sqlite3'
  gem 'webmock', require: false

  # Loaded only when ESCALATED_TEST_ADAPTER selects them, so a default `bundle
  # install` still needs no database client libraries present.
  gem 'mysql2', require: false
  gem 'pg', require: false
end
