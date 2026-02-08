require "net/http"
require "json"
require "uri"

module Escalated
  module Drivers
    class HostedApiClient
      class ApiError < StandardError
        attr_reader :status, :body

        def initialize(message, status: nil, body: nil)
          @status = status
          @body = body
          super(message)
        end
      end

      class ConnectionError < ApiError; end
      class AuthenticationError < ApiError; end
      class RateLimitError < ApiError; end
      class ServerError < ApiError; end

      TIMEOUT = 30
      MAX_RETRIES = 3
      RETRY_DELAY = 1

      def initialize(api_url: nil, api_key: nil)
        @api_url = api_url || Escalated.configuration.hosted_api_url
        @api_key = api_key || Escalated.configuration.hosted_api_key

        raise ArgumentError, "Escalated hosted_api_url is required for cloud/synced mode" if @api_url.blank?
        raise ArgumentError, "Escalated hosted_api_key is required for cloud/synced mode" if @api_key.blank?
      end

      # Class method for fire-and-forget sync operations
      def self.emit(action, payload)
        new.emit(action, payload)
      end

      def emit(action, payload)
        post("/sync/#{action}", payload)
      rescue StandardError => e
        Rails.logger.error("[Escalated::HostedApiClient] Emit failed: #{e.message}")
        raise
      end

      def get(path, params = {})
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        execute_request(uri, request)
      end

      def post(path, body = {})
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        request.body = body.to_json
        execute_request(uri, request)
      end

      def patch(path, body = {})
        uri = build_uri(path)
        request = Net::HTTP::Patch.new(uri)
        request.body = body.to_json
        execute_request(uri, request)
      end

      def put(path, body = {})
        uri = build_uri(path)
        request = Net::HTTP::Put.new(uri)
        request.body = body.to_json
        execute_request(uri, request)
      end

      def delete(path, body = {})
        uri = build_uri(path)
        request = Net::HTTP::Delete.new(uri)
        request.body = body.to_json if body.present?
        execute_request(uri, request)
      end

      private

      def build_uri(path, params = {})
        url = "#{@api_url.chomp('/')}#{path}"
        uri = URI.parse(url)

        if params.present?
          query = params.compact.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&")
          uri.query = query
        end

        uri
      end

      def execute_request(uri, request, retries: 0)
        apply_headers(request)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        response = http.request(request)
        handle_response(response)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        if retries < MAX_RETRIES
          sleep(RETRY_DELAY * (retries + 1))
          execute_request(uri, request, retries: retries + 1)
        else
          raise ConnectionError.new(
            "Failed to connect to Escalated API after #{MAX_RETRIES} retries: #{e.message}"
          )
        end
      end

      def apply_headers(request)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request["User-Agent"] = "Escalated-Rails/#{Escalated::VERSION rescue '0.1.0'}"
        request["X-Escalated-Source"] = "rails-engine"
      end

      def handle_response(response)
        body = parse_body(response.body)

        case response.code.to_i
        when 200..299
          body
        when 401
          raise AuthenticationError.new(
            "Authentication failed. Check your Escalated API key.",
            status: 401, body: body
          )
        when 429
          raise RateLimitError.new(
            "Rate limit exceeded. Retry after #{response['Retry-After'] || '60'} seconds.",
            status: 429, body: body
          )
        when 400..499
          raise ApiError.new(
            "Client error: #{body['message'] || response.message}",
            status: response.code.to_i, body: body
          )
        when 500..599
          raise ServerError.new(
            "Server error: #{body['message'] || response.message}",
            status: response.code.to_i, body: body
          )
        else
          raise ApiError.new(
            "Unexpected response: #{response.code} #{response.message}",
            status: response.code.to_i, body: body
          )
        end
      end

      def parse_body(raw)
        return {} if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        { "raw" => raw }
      end
    end
  end
end
