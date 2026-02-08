require "escalated/drivers/local_driver"
require "escalated/drivers/synced_driver"
require "escalated/drivers/cloud_driver"

module Escalated
  class Manager
    class << self
      def driver
        @driver ||= resolve_driver
      end

      def reset_driver!
        @driver = nil
      end

      private

      def resolve_driver
        case Escalated.configuration.mode
        when :self_hosted
          Drivers::LocalDriver.new
        when :synced
          Drivers::SyncedDriver.new
        when :cloud
          Drivers::CloudDriver.new
        else
          raise ArgumentError, "Unknown Escalated mode: #{Escalated.configuration.mode}. " \
                               "Valid modes are :self_hosted, :synced, :cloud"
        end
      end
    end
  end
end
