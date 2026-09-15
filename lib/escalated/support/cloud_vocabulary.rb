# frozen_string_literal: true

module Escalated
  module Support
    # Translation between this gem's ticket vocabulary and the one
    # cloud.escalated.dev speaks. Used by the cloud webhook receiver on the
    # way in. Values not listed pass through unchanged.
    module CloudVocabulary
      PRIORITY_FROM_CLOUD = { 'normal' => 'medium' }.freeze
      STATUS_FROM_CLOUD = { 'waiting' => 'waiting_on_customer', 'snoozed' => 'open' }.freeze
      PRIORITY_TO_CLOUD = { 'medium' => 'normal', 'critical' => 'urgent' }.freeze
      STATUS_TO_CLOUD = {
        'waiting_on_customer' => 'waiting', 'waiting_on_agent' => 'waiting',
        'escalated' => 'open', 'reopened' => 'open'
      }.freeze

      LOCAL_STATUSES = %w[
        open in_progress waiting_on_customer waiting_on_agent escalated resolved closed reopened
      ].freeze
      LOCAL_PRIORITIES = %w[low medium high urgent critical].freeze

      module_function

      def priority_from_cloud(value)
        PRIORITY_FROM_CLOUD.fetch(value.to_s, value.to_s)
      end

      def status_from_cloud(value)
        STATUS_FROM_CLOUD.fetch(value.to_s, value.to_s)
      end

      def priority_to_cloud(value)
        PRIORITY_TO_CLOUD.fetch(value.to_s, value.to_s)
      end

      def status_to_cloud(value)
        STATUS_TO_CLOUD.fetch(value.to_s, value.to_s)
      end
    end
  end
end
