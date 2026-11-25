# frozen_string_literal: true

module Escalated
  # Raised when a signed-in user reaches a staff screen and the host's user
  # model has no way to say who is staff. Without it every staff request is
  # turned away with "not an agent", which reads as a permissions problem
  # rather than a setup one.
  class UserModelNotConfigured < StandardError
    def self.for(user_class)
      new(
        "#{user_class.name || user_class} does not implement Escalated's user contract: define #escalated_agent? and " \
        '#escalated_admin? (true for support agents / admins) and a .escalated_agents scope on it. ' \
        '`rails generate escalated:install` adds all three to app/models/user.rb; see ' \
        'docs/getting-started.md. Run `bin/rails escalated:doctor` to check the setup.'
      )
    end
  end

  # The setup checks behind `bin/rails escalated:doctor` and the install
  # generator: the host user model's contract (the staff gates) and whether
  # the recurring jobs run.
  module SetupCheck
    INSTANCE_METHODS = {
      escalated_agent?: 'true for support agents (admins count as agents)',
      escalated_admin?: 'true for support admins'
    }.freeze
    CLASS_METHODS = {
      escalated_agents: 'a scope of every support agent (assignee lists)'
    }.freeze
    FIX_HINT = '`rails generate escalated:install` adds them to app/models/user.rb; see docs/getting-started.md.'

    class << self
      # Whether +user+ can be asked if it is staff at all.
      def staff_contract?(user)
        INSTANCE_METHODS.keys.any? { |name| user.respond_to?(name) }
      end

      # [{ level: :ok | :warning | :error, message: }]
      def run
        user_model_results + scheduler_results
      end

      def user_model_results
        model = Escalated.configuration.user_class.to_s
        klass = model.safe_constantize
        return [error("config.user_class #{model.inspect} is not a loadable class.")] unless klass

        missing = INSTANCE_METHODS.reject { |name, _| klass.method_defined?(name) }
        missing_class = CLASS_METHODS.reject { |name, _| klass.respond_to?(name) }
        if missing.empty? && missing_class.empty?
          return [ok("#{model} implements escalated_agent?, escalated_admin? and .escalated_agents.")]
        end

        results = missing.map { |name, what| error("#{model}##{name} is not defined (#{what}).") }
        results += missing_class.map { |name, what| warning("#{model}.#{name} is not defined (#{what}).") }
        results << warning(FIX_HINT)
      end

      def scheduler_results
        status = Escalated::SchedulerHealth.status
        return [warning('Could not read the scheduler heartbeat (run the migrations first).')] unless status
        return [ok(status[:message])] if status[:healthy]

        [warning(status[:message])]
      end

      private

      def ok(message) = { level: :ok, message: message }
      def warning(message) = { level: :warning, message: message }
      def error(message) = { level: :error, message: message }
    end
  end
end
