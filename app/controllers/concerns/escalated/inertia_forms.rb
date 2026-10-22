# frozen_string_literal: true

module Escalated
  # Helpers for admin controllers whose screens are the shared frontend's Form
  # pages. Those pages post their fields at the top level of the body, the way
  # escalated-laravel reads them, and expect Inertia's answer to a form visit:
  # a redirect, with any errors in the session keyed by field so useForm shows
  # them under the inputs.
  module InertiaForms
    extend ActiveSupport::Concern

    private

    def inertia_request?
      request.headers['X-Inertia'].present?
    end

    # The form's fields. Read from the top level; a body that nests them under
    # +legacy_key+ (what these controllers used to require) still works as long
    # as it sends none of them at the top level.
    def form_source(legacy_key, keys)
      nested = params[legacy_key]
      if nested.is_a?(ActionController::Parameters) && keys.none? { |k| params.key?(k) }
        nested
      else
        params
      end
    end

    def boolean_param(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    # Back to the form with +errors+ ({ field => message }) on its fields.
    def redirect_back_with_form_errors(errors, fallback)
      redirect_back_or_to(fallback, alert: errors.values.join(', '), inertia: { errors: errors })
    end

    def record_errors(record)
      record.errors.to_hash(true).transform_keys(&:to_s).transform_values(&:first)
    end
  end
end
