# frozen_string_literal: true

module UniquenessMatcherHelpers
  # `validate_uniqueness_of` asserts a case-*sensitive* comparison by default,
  # which is a claim about the database rather than about the model.
  #
  # Rails implements `validates :slug, uniqueness: true` as `WHERE slug = ?`, so
  # whether "Billing" collides with "billing" is decided by the column's
  # collation. MySQL's default collation folds case; PostgreSQL and SQLite do
  # not. The model says the same thing on all three.
  #
  # This asserts what is actually being claimed -- that the value is unique --
  # and leaves case folding to the adapter that owns it.
  def uniqueness_of(attribute)
    matcher = validate_uniqueness_of(attribute)

    case_insensitive_adapter? ? matcher.case_insensitive : matcher
  end

  def case_insensitive_adapter?
    ActiveRecord::Base.connection.adapter_name == 'Mysql2'
  end
end

RSpec.configure do |config|
  config.include UniquenessMatcherHelpers
end
