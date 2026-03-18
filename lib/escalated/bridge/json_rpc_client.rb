require "json"
require "io/wait"

module Escalated
  module Bridge
    # Low-level JSON-RPC 2.0 client over stdio.
    #
    # Writes newline-delimited JSON to the process stdin and reads responses
    # line-by-line from stdout. The communication is bidirectional — the plugin
    # runtime can send ctx.* callback requests back to the host while we are
    # waiting for a response to our own request.
    class JsonRpcClient
      # Maximum message size: 10 MB
      MAX_MESSAGE_SIZE = 10 * 1024 * 1024

      # @param stdin  [IO]  writable pipe to the subprocess stdin
      # @param stdout [IO]  readable pipe from the subprocess stdout
      def initialize(stdin, stdout)
        @stdin  = stdin
        @stdout = stdout
        @next_id = 1
      end

      # Send a JSON-RPC request and block until the matching response arrives.
      # While waiting, any incoming ctx.* requests from the runtime are handled
      # by the provided ctx_handler callable.
      #
      # @param method          [String]
      # @param params          [Hash]
      # @param timeout_seconds [Integer]
      # @param ctx_handler     [#call]   called as ctx_handler.call(method, params) → result
      # @return [Object] The JSON-RPC result
      # @raise [RuntimeError] On timeout or protocol error
      def call(method, params, timeout_seconds, ctx_handler)
        id      = @next_id
        @next_id += 1

        message = JSON.generate(
          "jsonrpc" => "2.0",
          "method"  => method,
          "params"  => params,
          "id"      => id
        )

        write_line(message)
        wait_for_response(id, timeout_seconds, ctx_handler)
      end

      # Send a JSON-RPC notification (no response expected).
      #
      # @param method [String]
      # @param params [Hash]
      def notify(method, params)
        message = JSON.generate(
          "jsonrpc" => "2.0",
          "method"  => method,
          "params"  => params
        )
        write_line(message)
      end

      # Send a JSON-RPC response back to the runtime (for ctx.* callbacks).
      #
      # @param id     [Integer]
      # @param result [Object]
      def respond(id, result)
        message = JSON.generate(
          "jsonrpc" => "2.0",
          "result"  => result,
          "id"      => id
        )
        write_line(message)
      end

      # Send a JSON-RPC error response back to the runtime.
      #
      # @param id      [Integer]
      # @param code    [Integer]
      # @param message [String]
      def respond_error(id, code, message)
        payload = JSON.generate(
          "jsonrpc" => "2.0",
          "error"   => { "code" => code, "message" => message },
          "id"      => id
        )
        write_line(payload)
      end

      # Read one line from stdout (blocks until data is available or timeout).
      # Returns nil on EOF/error.
      #
      # @param timeout_seconds [Integer]
      # @return [String, nil]
      def read_line(timeout_seconds)
        ready = IO.select([@stdout], nil, nil, timeout_seconds)
        return nil if ready.nil?

        line = @stdout.gets
        return nil if line.nil?

        if line.bytesize > MAX_MESSAGE_SIZE
          raise "JSON-RPC message exceeds maximum size of 10 MB"
        end

        line.chomp
      end

      private

      # Block until we receive the response for expected_id, dispatching any
      # interleaved ctx.* requests to ctx_handler in the meantime.
      #
      # @param expected_id     [Integer]
      # @param timeout_seconds [Integer]
      # @param ctx_handler     [#call]
      # @return [Object]
      def wait_for_response(expected_id, timeout_seconds, ctx_handler)
        deadline = Time.now + timeout_seconds

        loop do
          remaining = deadline - Time.now

          if remaining <= 0
            raise "JSON-RPC timeout waiting for response to request ##{expected_id}"
          end

          line = read_line(remaining)

          if line.nil?
            raise "JSON-RPC connection lost waiting for response to request ##{expected_id}"
          end

          next if line.empty?

          decoded = begin
            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end

          unless decoded.is_a?(Hash) && decoded.key?("jsonrpc")
            Rails.logger.warn("[Escalated::Bridge] Received invalid JSON-RPC message: #{line[0, 200]}")
            next
          end

          # This is a request FROM the runtime (ctx.* callback)
          if decoded.key?("method")
            handle_incoming_request(decoded, ctx_handler)
            next
          end

          # This is a response to one of our requests
          if decoded.key?("id")
            msg_id = decoded["id"].to_i

            if msg_id == expected_id
              if decoded.key?("error")
                err = decoded["error"]
                raise "JSON-RPC error from plugin runtime: #{err["message"] || "unknown error"}"
              end

              return decoded["result"]
            end

            # Response to a different request — should not happen in the
            # synchronous single-threaded model, but log and skip.
            Rails.logger.warn(
              "[Escalated::Bridge] Unexpected response id (expected #{expected_id}, got #{msg_id})"
            )
          end
        end
      end

      # Handle an incoming JSON-RPC request from the plugin runtime.
      # Calls ctx_handler and sends back the response (or error).
      #
      # @param message     [Hash]
      # @param ctx_handler [#call]
      def handle_incoming_request(message, ctx_handler)
        id     = message.key?("id") ? message["id"].to_i : nil
        method = message["method"] || ""
        params = message["params"] || {}

        begin
          result = ctx_handler.call(method, params)
          respond(id, result) unless id.nil?
        rescue => e
          Rails.logger.warn("[Escalated::Bridge] ctx handler threw for #{method}: #{e.message}")
          respond_error(id, -32_000, e.message) unless id.nil?
        end
      end

      # Write a newline-terminated line to the subprocess stdin.
      #
      # @param data [String]
      def write_line(data)
        raise "Plugin runtime stdin is not available" unless @stdin && !@stdin.closed?

        written = @stdin.write("#{data}\n")
        raise "Failed to write to plugin runtime stdin" unless written
        @stdin.flush
      end
    end
  end
end
