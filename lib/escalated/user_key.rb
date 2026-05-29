# frozen_string_literal: true

module Escalated
  # Returns the ActiveRecord column type to use for host-user foreign keys:
  # :bigint (default) | :uuid | :string. With :auto it introspects the
  # configured user model's primary key type, falling back to :bigint.
  def self.user_id_type
    configured = configuration.user_id_type
    return configured unless configured.nil? || configured == :auto

    klass = configuration.user_class.to_s.safe_constantize
    if klass&.table_exists?
      col = klass.columns_hash[klass.primary_key.to_s]
      case col&.type
      when :uuid then :uuid
      when :string, :text then :string
      else :bigint
      end
    else
      :bigint
    end
  rescue StandardError
    :bigint
  end
end
