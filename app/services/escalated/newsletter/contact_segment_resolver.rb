# frozen_string_literal: true

module Escalated
  module Newsletter
    # Resolves a NewsletterList to its set of contact IDs.
    # Static lists return their explicit member contact IDs.
    # Dynamic lists evaluate the saved filter against the contacts table.
    class ContactSegmentResolver
      def resolve(list)
        if list.kind == 'static'
          list.members.pluck(:contact_id)
        else
          apply_filter(list.filter_json || { 'rules' => [] }).pluck(:id)
        end
      end

      # Sendable IDs (opt-out filtered). Caller still needs to filter
      # hard-bounced emails via BounceSuppressionStore.
      def resolve_sendable(list)
        scope = Escalated::Contact.where(marketing_opt_out_at: nil)
        if list.kind == 'static'
          scope = scope.where(id: list.members.select(:contact_id))
        else
          scope = apply_filter(list.filter_json || { 'rules' => [] }, scope)
        end
        scope.pluck(:id)
      end

      def count_matches(filter)
        apply_filter(filter).count
      end

      private

      def apply_filter(filter, scope = Escalated::Contact.all)
        (filter['rules'] || []).each do |rule|
          field = rule['field']
          op = rule['op'] || '='
          value = rule['value']
          next if field.nil? || field.empty?

          if field.start_with?('metadata.')
            key = field.sub(/\Ametadata\./, '')
            # SQLite-friendly JSON LIKE; hosts on Postgres can swap this for jsonb_path.
            scope = scope.where("metadata LIKE ?", "%\"#{key}\":#{value.to_json}%")
            next
          end
          scope = scope.where("#{field} #{op} ?", value)
        end
        scope
      end
    end
  end
end
