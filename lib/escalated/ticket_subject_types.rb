# frozen_string_literal: true

module Escalated
  # Resolves configured ticket subject type allowlists for attach APIs.
  module TicketSubjectTypes
    module_function

    def configured
      Escalated.configuration.ticket_subject_types
    end

    # Flat list of morph type strings permitted by the agent/admin API.
    def allowed_type_names
      case configured
      when Hash
        configured.keys.map(&:to_s) + configured.values.map(&:to_s)
      when Array
        configured.map(&:to_s)
      else
        []
      end
    end

    def allowlist_enforced?
      allowed_type_names.any?
    end

    # @raise [ArgumentError] when +type+ is not in the configured allowlist
    def resolve_model_class!(type)
      type = type.to_s
      names = allowed_type_names
      raise ArgumentError, "Subject type [#{type}] is not an allowed ticket subject." unless names.include?(type)

      if configured.is_a?(Hash)
        value = configured[type] || configured[type.to_sym]
        return constantize_model!(value) if value
      end

      constantize_model!(type)
    end

    def constantize_model!(name)
      klass = name.to_s.constantize
      raise ArgumentError, "Subject type [#{name}] could not be resolved to a model." unless klass < ActiveRecord::Base

      klass
    rescue NameError
      raise ArgumentError, "Subject type [#{name}] could not be resolved to a model."
    end
  end
end
