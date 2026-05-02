# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'escalated-locale',
    git: 'https://github.com/escalated-dev/escalated-locale.git',
    glob: 'packages/rubygems/escalated-locale.gemspec',
    tag: 'v0.1.1'

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
end
