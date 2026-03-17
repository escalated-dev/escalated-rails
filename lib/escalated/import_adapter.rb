module Escalated
  # Value object returned by ImportAdapter#extract.
  #
  # @attr records    [Array<Hash>]   Normalized records ready for persistence.
  # @attr cursor     [String, nil]   Opaque pagination cursor; nil when exhausted.
  # @attr total_count [Integer, nil] Estimated total records, if the API provides it.
  ExtractResult = Struct.new(:records, :cursor, :total_count, keyword_init: true) do
    # Returns true when there are no more pages to fetch.
    #
    # @return [Boolean]
    def exhausted?
      cursor.nil?
    end
  end

  # Mixin / interface that every import adapter must implement.
  #
  # Adapters are registered via the hook system:
  #
  #   Escalated.hooks.add_filter("import.adapters") do |adapters|
  #     adapters + [MyAdapter.new]
  #   end
  #
  # Required methods are declared here and will raise NotImplementedError if
  # not overridden, giving a clear error message during development.
  module ImportAdapter
    # Unique slug, e.g. "zendesk".
    #
    # @return [String]
    def name
      raise NotImplementedError, "#{self.class}#name is not implemented"
    end

    # Human-readable label, e.g. "Zendesk".
    #
    # @return [String]
    def display_name
      raise NotImplementedError, "#{self.class}#display_name is not implemented"
    end

    # Credential field definitions for the setup UI.
    #
    # Each element is a Hash with keys:
    #   name    [String]   Parameter name, e.g. "api_token"
    #   label   [String]   UI label, e.g. "API Token"
    #   type    [String]   "text" | "password" | "url"
    #   help    [String]   Optional hint text
    #
    # @return [Array<Hash>]
    def credential_fields
      raise NotImplementedError, "#{self.class}#credential_fields is not implemented"
    end

    # Validate credentials by making a live API call.
    #
    # @param credentials [Hash]
    # @return [Boolean]
    def test_connection(credentials)
      raise NotImplementedError, "#{self.class}#test_connection is not implemented"
    end

    # Ordered list of entity types this adapter supports.
    # The import service iterates them in this order.
    #
    # @return [Array<String>]  e.g. ["agents", "tags", "contacts", "tickets", "replies"]
    def entity_types
      raise NotImplementedError, "#{self.class}#entity_types is not implemented"
    end

    # Default field mapping for an entity type.
    #
    # @param entity_type [String]
    # @return [Hash]
    def default_field_mappings(entity_type)
      raise NotImplementedError, "#{self.class}#default_field_mappings is not implemented"
    end

    # Available source fields for an entity type (fetched live from the API).
    #
    # @param entity_type [String]
    # @param credentials [Hash]
    # @return [Array<String>]
    def available_source_fields(entity_type, credentials)
      raise NotImplementedError, "#{self.class}#available_source_fields is not implemented"
    end

    # Extract a batch of normalized records for the given entity type.
    #
    # @param entity_type [String]
    # @param credentials [Hash]
    # @param cursor      [String, nil]  Pagination cursor from a previous call.
    # @return [Escalated::ExtractResult]
    def extract(entity_type, credentials, cursor)
      raise NotImplementedError, "#{self.class}#extract is not implemented"
    end

    # Optional: receive the ImportJob UUID so the adapter can cross-reference
    # previously imported records via ImportSourceMap.
    #
    # @param job_id [String]
    # @return [void]
    def job_id=(job_id)
      @job_id = job_id
    end

    def job_id
      @job_id
    end
  end
end
