module Escalated
  module Support
    class HookManager
      def initialize
        @actions = {}
        @filters = {}
      end

      # ================================================================
      # Actions
      # ================================================================

      # Add an action hook.
      #
      # @param tag      [String]   The action name
      # @param callback [#call, nil] A callable, or nil when using a block
      # @param priority [Integer]  Lower numbers run first (default 10)
      # @yield Optional block used as callback when no callable is given
      # @return [void]
      def add_action(tag, callback = nil, priority: 10, &block)
        cb = callback || block
        raise ArgumentError, "add_action requires a callback or block" unless cb

        @actions[tag] ||= {}
        @actions[tag][priority] ||= []
        @actions[tag][priority] << cb
      end

      # Execute all callbacks registered for an action.
      #
      # @param tag  [String] The action name
      # @param args [Array]  Arguments forwarded to each callback
      # @return [void]
      def do_action(tag, *args)
        return unless @actions.key?(tag)

        @actions[tag].sort.each do |_priority, callbacks|
          callbacks.each { |cb| cb.call(*args) }
        end
      end

      # Check whether an action has any registered callbacks.
      #
      # @param tag [String]
      # @return [Boolean]
      def has_action?(tag)
        @actions.key?(tag) && !@actions[tag].empty?
      end

      # Remove callbacks for an action.
      #
      # When +callback+ is nil every callback for the tag is removed.
      # When +callback+ is given only that specific callable is removed.
      #
      # @param tag      [String]
      # @param callback [#call, nil]
      # @return [void]
      def remove_action(tag, callback = nil)
        if callback.nil?
          @actions.delete(tag)
          return
        end

        return unless @actions.key?(tag)

        @actions[tag].each do |priority, callbacks|
          callbacks.reject! { |cb| cb == callback }
          @actions[tag].delete(priority) if callbacks.empty?
        end

        @actions.delete(tag) if @actions[tag]&.empty?
      end

      # ================================================================
      # Filters
      # ================================================================

      # Add a filter hook.
      #
      # Filters are identical to actions except the first argument is the
      # *value* being filtered and the return value of each callback
      # replaces it for the next callback in the chain.
      #
      # @param tag      [String]
      # @param callback [#call, nil]
      # @param priority [Integer]
      # @yield Optional block used as callback
      # @return [void]
      def add_filter(tag, callback = nil, priority: 10, &block)
        cb = callback || block
        raise ArgumentError, "add_filter requires a callback or block" unless cb

        @filters[tag] ||= {}
        @filters[tag][priority] ||= []
        @filters[tag][priority] << cb
      end

      # Apply all filter callbacks to a value.
      #
      # @param tag   [String] The filter name
      # @param value [Object] The value to filter
      # @param args  [Array]  Additional arguments forwarded to callbacks
      # @return [Object] The filtered value
      def apply_filters(tag, value, *args)
        return value unless @filters.key?(tag)

        @filters[tag].sort.each do |_priority, callbacks|
          callbacks.each { |cb| value = cb.call(value, *args) }
        end

        value
      end

      # Check whether a filter has any registered callbacks.
      #
      # @param tag [String]
      # @return [Boolean]
      def has_filter?(tag)
        @filters.key?(tag) && !@filters[tag].empty?
      end

      # Remove callbacks for a filter.
      #
      # @param tag      [String]
      # @param callback [#call, nil]
      # @return [void]
      def remove_filter(tag, callback = nil)
        if callback.nil?
          @filters.delete(tag)
          return
        end

        return unless @filters.key?(tag)

        @filters[tag].each do |priority, callbacks|
          callbacks.reject! { |cb| cb == callback }
          @filters[tag].delete(priority) if callbacks.empty?
        end

        @filters.delete(tag) if @filters[tag]&.empty?
      end

      # ================================================================
      # Introspection
      # ================================================================

      # @return [Hash] all registered actions
      def actions
        @actions
      end

      # @return [Hash] all registered filters
      def filters
        @filters
      end

      # Reset all hooks (useful for testing).
      #
      # @return [void]
      def clear!
        @actions = {}
        @filters = {}
      end
    end
  end
end
