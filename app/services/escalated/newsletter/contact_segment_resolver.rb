# frozen_string_literal: true

module Escalated
  class Newsletter
    # Resolves a NewsletterList to its set of contact IDs.
    # Static lists return their explicit member contact IDs.
    # Dynamic lists evaluate the saved filter against the contacts table.
    class ContactSegmentResolver
      # Operators allowed in a dynamic-list rule, mapped to their SQL form.
      # Both the field and operator in a rule come from saved (admin-authored)
      # filter JSON, so they must be allowlisted before going anywhere near a
      # SQL fragment — they were previously interpolated raw (injection).
      ALLOWED_OPS = {
        '=' => '=', '==' => '=', '!=' => '!=', '<>' => '!=',
        '>' => '>', '<' => '<', '>=' => '>=', '<=' => '<=', 'like' => 'LIKE'
      }.freeze

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
        scope = if list.kind == 'static'
                  scope.where(id: list.members.select(:contact_id))
                else
                  apply_filter(list.filter_json || { 'rules' => [] }, scope)
                end
        scope.pluck(:id)
      end

      def count_matches(filter)
        apply_filter(filter).count
      end

      private

      def apply_filter(filter, scope = Escalated::Contact.all)
        columns = Escalated::Contact.column_names
        (filter['rules'] || []).each do |rule|
          field = rule['field']
          op = rule['op'] || '='
          value = rule['value']
          next if field.blank?

          if field.start_with?('metadata.')
            key = field.sub(/\Ametadata\./, '')
            # SQLite-friendly JSON LIKE; hosts on Postgres can swap this for jsonb_path.
            # `key` lands inside a bound parameter value, so it can't alter the SQL.
            scope = scope.where('metadata LIKE ?', "%\"#{key}\":#{value.to_json}%")
            next
          end

          # Allowlist the column and operator. `value` is already bound (?),
          # but `field`/`op` would otherwise be interpolated into the SQL — skip
          # any rule that doesn't reference a real column / known operator.
          next unless columns.include?(field)

          sql_op = ALLOWED_OPS[op.to_s.strip.downcase]
          next unless sql_op

          quoted = Escalated::Contact.connection.quote_column_name(field)
          scope = scope.where("#{quoted} #{sql_op} ?", value)
        end
        scope
      end
    end
  end
end
