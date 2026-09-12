# frozen_string_literal: true

module Escalated
  # Base class for every Escalated model.
  #
  # All of Escalated's tables used to resolve the host application's primary
  # database with no way to change it, which made the engine unusable in any
  # host that partitions its data: a schema shared with a legacy system, a
  # multi-tenant split, a separate reporting store, or simply a host that would
  # rather keep support tables out of its primary database.
  #
  # `Escalated.configuration.database_connection` names where they live instead. It
  # accepts either shape Rails offers:
  #
  #   config.database_connection = :support
  #   config.database_connection = { writing: :support_primary, reading: :support_replica }
  #
  # A Symbol or String establishes that `database.yml` entry directly. A Hash is
  # passed to `connects_to`, so a host already using Rails' role-based multiple
  # databases keeps its reading/writing split.
  #
  # nil -- the default -- leaves this an ordinary abstract record on the host's
  # primary connection, exactly as before.
  #
  # The host's user table deliberately does not move. It belongs to the host,
  # and Escalated stores host user ids as plain unconstrained columns precisely
  # so the two can live on different connections with no foreign key to span
  # them.
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    connection_spec = Escalated.configuration.database_connection

    case connection_spec
    when nil
      # Host's primary connection; nothing to do.
    when Hash
      connects_to database: connection_spec
    else
      establish_connection connection_spec.to_sym
    end
  end
end
