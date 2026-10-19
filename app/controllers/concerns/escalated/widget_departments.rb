# frozen_string_literal: true

module Escalated
  # The widget offers the active departments from `/widget/config`; a ticket or
  # chat may name one of them in `department_id` and nothing else.
  module WidgetDepartments
    extend ActiveSupport::Concern

    private

    # Blank means "no department". Anything else must be an active department.
    def widget_department_valid?(department_id)
      return true if department_id.blank?

      id = Integer(department_id.to_s, exception: false)
      id.present? && Escalated::Department.active.exists?(id: id)
    end

    def render_unknown_department
      message = 'The selected department is invalid.'
      render json: { error: message, message: message, errors: { department_id: [message] } },
             status: :unprocessable_content
    end
  end
end
