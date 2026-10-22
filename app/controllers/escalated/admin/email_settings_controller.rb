# frozen_string_literal: true

module Escalated
  module Admin
    # Admin/Settings/EmailSettings: the addresses tickets are received at and
    # answered from, and which one replies default to (escalated-laravel's
    # EmailSettingsController and EmailChannelService). As in Laravel these
    # are stored settings: the DKIM status is what the admin records, not a DNS
    # check, and outbound mail keeps using the configured from address.
    class EmailSettingsController < Escalated::ApplicationController
      include Escalated::InertiaForms

      before_action :require_admin!

      ADDRESSES_KEY = 'email_addresses'
      DEFAULT_REPLY_KEY = 'default_reply_address'
      DKIM_STATUSES = %w[verified pending failed unknown].freeze

      def show
        render_page 'Escalated/Admin/Settings/EmailSettings', {
          addresses: stored_addresses,
          defaultReplyAddress: Escalated::EscalatedSetting.get(DEFAULT_REPLY_KEY).to_s
        }
      end

      def update
        errors = {}
        addresses = submitted_addresses(errors)
        reply = params[:default_reply_address].to_s.strip
        errors[DEFAULT_REPLY_KEY] = 'Enter a valid email address.' if reply.present? && !email?(reply)
        return redirect_back_with_form_errors(errors, escalated.admin_settings_email_path) if errors.any?

        Escalated::EscalatedSetting.set(ADDRESSES_KEY, addresses.to_json)
        Escalated::EscalatedSetting.set(DEFAULT_REPLY_KEY, reply) if reply.present?

        redirect_back_or_to escalated.admin_settings_email_path, flash: { success: 'Email settings updated.' }
      end

      private

      def stored_addresses
        list = JSON.parse(Escalated::EscalatedSetting.get(ADDRESSES_KEY).presence || '[]')
        list.is_a?(Array) ? list : []
      rescue JSON::ParserError
        []
      end

      # The submitted list, each entry cut down to the four fields the screen
      # edits. Problems go into +errors+, keyed the way the form reads them.
      def submitted_addresses(errors)
        raw = params[:addresses]
        raw = raw.to_unsafe_h.sort_by { |index, _| index.to_i }.map(&:last) if raw.is_a?(ActionController::Parameters)
        unless raw.is_a?(Array)
          errors['addresses'] = 'The addresses field is required.'
          return []
        end

        raw.each_with_index.map { |entry, index| normalize_address(entry, "addresses.#{index}", errors) }
      end

      def normalize_address(entry, prefix, errors)
        entry = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry.to_h
        email = entry['email'].to_s.strip
        display_name = entry['display_name'].presence&.to_s
        department_id = entry['department_id'].presence
        dkim_status = entry['dkim_status'].presence || 'unknown'

        errors["#{prefix}.email"] = 'Enter a valid email address.' unless email?(email)
        if display_name && display_name.length > 255
          errors["#{prefix}.display_name"] = 'The display name may not be longer than 255 characters.'
        end
        if department_id
          department_id = Integer(department_id.to_s, exception: false)
          errors["#{prefix}.department_id"] = 'The department must be a whole number.' if department_id.nil?
        end
        unless DKIM_STATUSES.include?(dkim_status)
          errors["#{prefix}.dkim_status"] = "Choose one of: #{DKIM_STATUSES.join(', ')}."
        end

        { email: email, display_name: display_name, department_id: department_id, dkim_status: dkim_status }
      end

      def email?(value)
        value.length <= 255 && value.match?(URI::MailTo::EMAIL_REGEXP)
      end
    end
  end
end
