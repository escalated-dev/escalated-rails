# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'escalated-locale',
    git: 'https://github.com/escalated-dev/escalated-locale.git',
    glob: 'packages/rubygems/escalated-locale.gemspec',
    tag: 'v0.1.8'

# json 3.0 removed the positional options argument from JSON.parse, and
# Rails 8.1's SQLite adapter still passes one while reading table metadata
# during a table rebuild. The first migration that rebuilds a table (011,
# a change_column_null) then aborts the whole suite with
# "wrong number of arguments (given 2, expected 1)" out of
# json/common.rb#parse.
#
# Gemfile.lock is not committed -- correct for a gem, since the suite
# should prove the library works against current dependencies -- so CI
# picked json 3.0 up the day it shipped and main went red with nobody
# touching it. Pinned until Rails is compatible; the constraint is only in
# the Gemfile, so it applies to this repo's own test run and is not
# imposed on host applications through the gemspec.
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
