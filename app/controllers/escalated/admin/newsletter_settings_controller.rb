# frozen_string_literal: true

module Escalated
  module Admin
    class NewsletterSettingsController < Escalated::ApplicationController
      include Escalated::NewsletterAccess

      KEYS = {
        default_from: 'string',
        default_reply_to: 'string',
        default_theme: 'string',
        rate_limit_per_minute: 'number',
        batch_size: 'number',
        tracking_enabled: 'boolean'
      }.freeze

      before_action :require_admin!
      before_action :ensure_newsletters_enabled!
      before_action -> { require_newsletter_permission!('newsletters.manage') }

      def show
        settings = KEYS.each_key.index_with { |key| setting_value(key) }

        render_page 'Escalated/Admin/Newsletters/Settings', {
          settings: settings,
          themes: %w[default branded]
        }
      end

      def update
        data = settings_params
        return unless data

        KEYS.each do |key, type|
          value = data[key]
          stored = type == 'boolean' ? boolean_value(value).to_s : value.to_s
          Escalated::EscalatedSetting.set("newsletter.#{key}", stored)
        end

        redirect_to admin_newsletters_settings_path
      end

      private

      def settings_params
        data = params.permit(*KEYS.keys).to_h.symbolize_keys
        errors = []
        errors << 'default_from is invalid' if data[:default_from].present? && !valid_email?(data[:default_from])
        if data[:default_reply_to].present? && !valid_email?(data[:default_reply_to])
          errors << 'default_reply_to is invalid'
        end
        errors << 'default_theme is required' if data[:default_theme].blank?
        errors << 'default_theme is too long' if data[:default_theme].to_s.length > 64
        rate = data[:rate_limit_per_minute].to_i
        batch = data[:batch_size].to_i
        errors << 'rate_limit_per_minute is invalid' unless rate.between?(1, 10_000)
        errors << 'batch_size is invalid' unless batch.between?(1, 1000)
        errors << 'tracking_enabled is required' unless data.key?(:tracking_enabled)
        return data.merge(rate_limit_per_minute: rate, batch_size: batch) if errors.empty?

        render plain: errors.join(', '), status: :unprocessable_content
        nil
      end

      def setting_value(key)
        Escalated::EscalatedSetting.get("newsletter.#{key}", configuration_default(key))
      end

      def configuration_default(key)
        Escalated.configuration.public_send("newsletter_#{key}")
      end

      def boolean_value(value)
        %w[1 true on yes].include?(value.to_s.downcase) ? 1 : 0
      end

      def valid_email?(email)
        email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
      end
    end
  end
end
