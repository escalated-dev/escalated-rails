# frozen_string_literal: true

# Every route Escalated registers, with what guards it, as plain data: the
# host-app routes it appends (the engine mount, the API, newsletter tracking)
# and every engine route, each with its verb, path, controller#action and the
# before_action callbacks that run for that action (Rails' equivalent of a
# route's middleware).
#
# spec/fixtures/embed/default-routes.json is this table taken from main before
# the embeddable admin existed (ADR 2026-11-05-embeddable-admin); the default
# configuration must still produce it exactly. Regenerate it only for a change
# that is meant to alter the default route table:
#
#   ESCALATED_WRITE_ROUTE_SNAPSHOT=1 bundle exec rspec spec/requests/escalated/embed_default_unchanged_spec.rb
module EscalatedRouteTable
  module_function

  def snapshot
    {
      'host' => host_routes,
      'engine' => engine_routes
    }
  end

  def host_routes
    Rails.application.routes.routes.filter_map do |route|
      app = route.app.respond_to?(:app) ? route.app.app : route.app
      engine = app == Escalated::Engine
      controller = route.defaults[:controller].to_s
      next unless engine || controller.start_with?('escalated/') || route.name.to_s.start_with?('escalated')

      describe(route).merge('mount' => engine)
    end
  end

  def engine_routes
    Escalated::Engine.routes.routes.map { |route| describe(route) }
  end

  def describe(route)
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    {
      'name' => route.name,
      'verb' => route.verb,
      'path' => route.path.spec.to_s,
      'endpoint' => controller ? "#{controller}##{action}" : nil,
      'defaults' => route.defaults.except(:controller, :action).transform_keys(&:to_s).transform_values(&:to_s),
      'before' => controller ? before_callbacks(controller, action) : []
    }
  end

  # The before_action callbacks that apply to +action+, in order. `only:` /
  # `except:` are resolved; any other condition is recorded by name.
  def before_callbacks(controller, action)
    klass = "#{controller.camelize}Controller".safe_constantize
    return ['(no controller)'] unless klass

    klass._process_action_callbacks.select { |cb| cb.kind == :before }.filter_map do |cb|
      conditions = []
      applies = conditions_apply?(cb.instance_variable_get(:@if), action, conditions, positive: true) &&
                conditions_apply?(cb.instance_variable_get(:@unless), action, conditions, positive: false)
      next unless applies

      ([cb.filter.is_a?(Symbol) ? cb.filter.to_s : cb.filter.class.name] + conditions).join(' ')
    end
  end

  def conditions_apply?(conditions, action, notes, positive:)
    Array(conditions).all? do |condition|
      if condition.is_a?(AbstractController::Callbacks::ActionFilter)
        actions = condition.instance_variable_get(:@actions)
        actions.include?(action.to_s) == positive
      else
        notes << "#{positive ? 'if' : 'unless'}:#{condition.is_a?(Symbol) ? condition : 'proc'}"
        true
      end
    end
  end
end
