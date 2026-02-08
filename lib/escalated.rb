require "escalated/engine"
require "escalated/configuration"
require "escalated/manager"

module Escalated
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def driver
      Manager.driver
    end

    def table_name(name)
      "#{configuration.table_prefix}#{name}"
    end
  end
end
