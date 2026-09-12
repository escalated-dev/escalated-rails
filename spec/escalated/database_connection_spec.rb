# frozen_string_literal: true

require 'rails_helper'

# All of Escalated's tables resolved the host application's primary database
# with no way to change it, which made the engine unusable in any host that
# partitions its data. `Escalated.configuration.database_connection` names where they
# live instead.
#
# These specs pin the configuration contract and the one rule that keeps the
# two sides joined: Escalated's tables move together, and the host's user table
# stays exactly where the host put it.
RSpec.describe Escalated::ApplicationRecord do
  around do |example|
    original = Escalated.configuration.database_connection
    example.run
    Escalated.configuration.database_connection = original
  end

  it 'defaults to nil, so an unconfigured host keeps its primary connection' do
    expect(Escalated.configuration.database_connection).to be_nil
  end

  it 'is configurable to a database.yml entry name' do
    Escalated.configuration.database_connection = :support

    expect(Escalated.configuration.database_connection).to eq(:support)
  end

  it 'accepts a role mapping for hosts already using multiple databases' do
    Escalated.configuration.database_connection = { writing: :support_primary, reading: :support_replica }

    expect(Escalated.configuration.database_connection)
      .to eq(writing: :support_primary, reading: :support_replica)
  end

  describe 'the engine base class' do
    it 'is the single place every Escalated model resolves its connection' do
      # Read off disk rather than `descendants`, which only knows about classes
      # autoloading happens to have touched -- under a random seed that made
      # this pass or fail depending on which spec ran first. Enumerating the
      # directory also catches a model added later that forgets the base class,
      # which is the regression actually worth guarding.
      model_files = Dir[Escalated::Engine.root.join('app/models/escalated/*.rb')]

      expect(model_files).not_to be_empty

      models = model_files.filter_map do |path|
        klass = "Escalated::#{File.basename(path, '.rb').camelize}".safe_constantize

        next if klass.nil? || !klass.is_a?(Class) || !(klass < ActiveRecord::Base)
        next if klass.abstract_class?

        klass
      end

      expect(models).not_to be_empty

      models.each do |model|
        expect(model.ancestors).to include(described_class),
                                   "#{model} must inherit #{described_class} to follow the connection"
      end
    end

    it 'is abstract, so it carries the connection without owning a table' do
      expect(described_class.abstract_class?).to be(true)
    end

    it 'resolves the host primary connection when nothing is configured' do
      expect(Escalated::Ticket.connection_db_config.name)
        .to eq(ActiveRecord::Base.connection_db_config.name)
    end
  end

  describe 'the host boundary' do
    it 'leaves the host user class outside the engine base' do
      user_class = Escalated.configuration.user_class.to_s.safe_constantize

      skip 'dummy app has no user class' if user_class.nil?

      # The users table belongs to the host. Escalated must never drag it onto
      # its own connection -- host user ids are stored as plain unconstrained
      # columns precisely so the two can live apart.
      expect(user_class.ancestors).not_to include(described_class)
    end

    it 'stores host user references without a foreign key that would span connections' do
      foreign_keys = Escalated::Ticket.connection.foreign_keys(Escalated::Ticket.table_name)
      user_table = Escalated.configuration.user_class.to_s.safe_constantize&.table_name

      skip 'dummy app has no user class' if user_table.nil?

      expect(foreign_keys.map(&:to_table)).not_to include(user_table)
    end
  end
end
