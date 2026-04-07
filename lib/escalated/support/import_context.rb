# frozen_string_literal: true

module Escalated
  module Support
    # Thread-safe flag that signals an active bulk import is in progress.
    #
    # When importing=true, Escalated callbacks, automations, SLA timers, and
    # notification hooks should treat it as a no-op so that tens of thousands
    # of records can be written without side-effects.
    #
    # Usage in services / callbacks:
    #
    #   return if Escalated::Support::ImportContext.importing?
    #
    # Usage when running an import:
    #
    #   Escalated::Support::ImportContext.suppress do
    #     # ... write records ...
    #   end
    #
    module ImportContext
      # Thread-local key — each worker/thread gets its own flag so concurrent
      # imports and regular request threads never interfere with each other.
      THREAD_KEY = :'escalated.import_context.importing'
      private_constant :THREAD_KEY

      # Returns true while a suppress block is active on the current thread.
      #
      # @return [Boolean]
      def self.importing?
        Thread.current[THREAD_KEY] == true
      end

      # Run +block+ with the importing flag set to true on the current thread.
      # The flag is always cleared in a +ensure+ block, even if the block raises.
      #
      # @yield  The block to execute with event suppression active.
      # @return The return value of the block.
      def self.suppress
        previous = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = true

        yield
      ensure
        Thread.current[THREAD_KEY] = previous
      end
    end
  end
end
