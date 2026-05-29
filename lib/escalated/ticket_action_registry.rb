# frozen_string_literal: true

module Escalated
  # Holds the host application's registered custom ticket actions and resolves
  # which are available for a given ticket/user.
  #
  # Actions are registered via `config.ticket_actions` (an array of Hashes).
  # Each Hash supports: key:, label:, variant:, visible:, enabled:,
  # confirmation:, metadata: — where visible/enabled/confirmation/metadata may
  # be plain values or callables (Proc/lambda) accepting (ticket, user).
  #
  # Mirrors the Laravel TicketActionRegistry / NestJS reference.
  class TicketActionRegistry
    # @param actions [Array<Hash>]
    # @return [TicketActionRegistry]
    def self.from_config(actions)
      registry = new
      Array(actions).each { |config| registry.register(config) }
      registry
    end

    def initialize
      @actions = {}
    end

    # @param config [Hash]
    def register(config)
      key = config[:key]
      label = config[:label]
      raise ArgumentError, 'Ticket actions require both :key and :label.' if key.nil? || label.nil?

      @actions[key.to_s] = config
      self
    end

    # @return [Hash, nil]
    def find(key)
      @actions[key.to_s]
    end

    def visible?(config, ticket, user)
      resolve(config.fetch(:visible, true), ticket, user) ? true : false
    end

    def enabled?(config, ticket, user)
      resolve(config.fetch(:enabled, true), ticket, user) ? true : false
    end

    def metadata(config, ticket, user)
      value = resolve(config[:metadata] || {}, ticket, user)
      value.is_a?(Hash) ? value : {}
    end

    # The visible actions for a ticket/user, serialized for the UI. The
    # controller adds the `url` and `method` before sending to the client.
    #
    # @return [Array<Hash>]
    def for_ticket(ticket, user)
      @actions.each_value.select { |config| visible?(config, ticket, user) }.map do |config|
        confirmation = resolve(config[:confirmation], ticket, user)

        {
          key: config[:key].to_s,
          label: resolve(config[:label], ticket, user).to_s,
          variant: (config[:variant] || 'secondary').to_s,
          confirmation: confirmation&.to_s,
          disabled: !enabled?(config, ticket, user),
          metadata: metadata(config, ticket, user)
        }
      end
    end

    private

    def resolve(value, ticket, user)
      value.respond_to?(:call) ? value.call(ticket, user) : value
    end
  end
end
