# frozen_string_literal: true

module Escalated
  module Admin
    # Admin/Settings/CsatSettings: the satisfaction survey's question, scale
    # and delivery (escalated-laravel's CsatSettingsController). As in Laravel,
    # the screen stores these settings; it does not send surveys itself.
    class CsatSettingsController < Escalated::ApplicationController
      include Escalated::InertiaForms

      before_action :require_admin!

      DEFAULTS = {
        'csat_question_text' => 'How would you rate your support experience?',
        'csat_scale' => '1-5',
        'csat_delivery_trigger' => 'on_resolve',
        'csat_delay_hours' => '0'
      }.freeze

      SCALES = %w[1-3 1-5].freeze
      TRIGGERS = %w[on_resolve delayed manual].freeze

      def show
        values = DEFAULTS.to_h { |key, default| [key, Escalated::EscalatedSetting.get(key).presence || default] }

        render_page 'Escalated/Admin/Settings/CsatSettings', {
          settings: values.merge('csat_delay_hours' => values['csat_delay_hours'].to_i)
        }
      end

      def update
        values = {
          'csat_question_text' => params[:csat_question_text].to_s.strip,
          'csat_scale' => params[:csat_scale].to_s,
          'csat_delivery_trigger' => params[:csat_delivery_trigger].to_s,
          'csat_delay_hours' => Integer(params[:csat_delay_hours].to_s, exception: false)
        }

        errors = validation_errors(values)
        return redirect_back_with_form_errors(errors, escalated.admin_settings_csat_path) if errors.any?

        values.each { |key, value| Escalated::EscalatedSetting.set(key, value.to_s) }

        redirect_back_or_to escalated.admin_settings_csat_path, flash: { success: 'CSAT settings updated.' }
      end

      private

      def validation_errors(values)
        errors = {}
        question = values['csat_question_text']
        if question.empty?
          errors['csat_question_text'] = 'The question is required.'
        elsif question.length > 500
          errors['csat_question_text'] = 'The question may not be longer than 500 characters.'
        end
        errors['csat_scale'] = 'The scale must be 1-3 or 1-5.' unless SCALES.include?(values['csat_scale'])
        unless TRIGGERS.include?(values['csat_delivery_trigger'])
          errors['csat_delivery_trigger'] = 'The delivery trigger must be on_resolve, delayed or manual.'
        end
        unless values['csat_delay_hours']&.between?(0, 168)
          errors['csat_delay_hours'] = 'The delay must be a whole number of hours from 0 to 168.'
        end
        errors
      end
    end
  end
end
