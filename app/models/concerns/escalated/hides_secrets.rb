# frozen_string_literal: true

module Escalated
  # Keeps a model's stored secrets out of serialization (as_json, to_json,
  # serializable_hash), the way Laravel's $hidden does, and out of inspect
  # and logs. The attributes still read normally server-side.
  #
  #   include Escalated::HidesSecrets
  #   hides_secrets :secret, :recovery_codes
  module HidesSecrets
    extend ActiveSupport::Concern

    included do
      class_attribute :hidden_secret_attributes, instance_writer: false, default: []
    end

    class_methods do
      def hides_secrets(*names)
        names = names.map(&:to_s)
        self.hidden_secret_attributes = (hidden_secret_attributes + names).uniq
        self.filter_attributes += names.map(&:to_sym)
      end
    end

    def serializable_hash(options = nil)
      options = options ? options.dup : {}
      options[:except] = Array(options[:except]).map(&:to_s) | hidden_secret_attributes
      super.except(*hidden_secret_attributes)
    end
  end
end
