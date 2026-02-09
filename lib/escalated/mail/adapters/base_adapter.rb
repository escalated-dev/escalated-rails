module Escalated
  module Mail
    module Adapters
      class BaseAdapter
        # Parse the incoming webhook/request into an InboundMessage.
        # Subclasses must implement this method.
        #
        # @param request [ActionDispatch::Request] the raw HTTP request
        # @return [Escalated::Mail::InboundMessage]
        def parse_request(request)
          raise NotImplementedError, "#{self.class.name}#parse_request must be implemented"
        end

        # Verify the authenticity of the incoming request (signature check, etc.).
        # Returns true if the request is valid, false otherwise.
        # Default implementation returns true (no verification).
        #
        # @param request [ActionDispatch::Request] the raw HTTP request
        # @return [Boolean]
        def verify_request(request)
          true
        end

        # Human-readable adapter name for logging and storage
        #
        # @return [String]
        def adapter_name
          self.class.name.demodulize.underscore.sub(/_adapter\z/, "")
        end

        private

        # Safely extract a value from params, returning nil if missing
        def safe_param(params, key, default = nil)
          value = params[key]
          value.present? ? value : default
        end

        # Parse an email address string like "John Doe <john@example.com>"
        # into [name, email] tuple
        def parse_email_address(address_string)
          return [nil, nil] if address_string.blank?

          if match = address_string.match(/\A\s*(.+?)\s*<([^>]+)>\s*\z/)
            [match[1].strip.gsub(/\A["']|["']\z/, ""), match[2].strip.downcase]
          else
            [nil, address_string.strip.downcase]
          end
        end

        # Parse a comma-separated list of email addresses
        def parse_references(references_string)
          return [] if references_string.blank?

          references_string.scan(/<([^>]+)>/).flatten
        end
      end
    end
  end
end
