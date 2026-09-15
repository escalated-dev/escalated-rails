# frozen_string_literal: true

require 'openssl'

module Escalated
  # Applies cloud-side changes to the local ticket in Synced mode.
  #
  # cloud.escalated.dev posts `ticket.updated` / `ticket.status_changed` with
  # the projected ticket. The projection carries this site's own reference as
  # `external_id`; tickets without one never came from here and are ignored.
  # Changes go through LocalDriver so listeners, notifications and workflows
  # fire exactly as for a local edit, while SyncedDriver is bypassed so
  # nothing is echoed back to the cloud.
  class CloudWebhookController < PublicController
    skip_before_action :verify_authenticity_token

    APPLIED_EVENTS = %w[ticket.updated ticket.status_changed].freeze
    REPLAY_TTL = 24.hours

    def receive
      secret = Escalated.configuration.hosted_signing_secret.to_s

      if secret.empty?
        Rails.logger.warn(
          '[Escalated::CloudWebhookController] webhook received but hosted_signing_secret is not configured.'
        )
        return render json: { error: 'Cloud webhook signing secret is not configured.' }, status: :service_unavailable
      end

      raw = request.raw_post.to_s
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw)}"
      signature = request.headers['X-Escalated-Signature'].to_s

      unless signature.present? && ActiveSupport::SecurityUtils.secure_compare(expected, signature)
        return render json: { error: 'Invalid signature.' }, status: :unauthorized
      end

      body = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
      event = body['event'].to_s
      event_id = body['event_id']
      cloud_ticket = body['ticket'].is_a?(Hash) ? body['ticket'] : {}

      if event_id.is_a?(String) && !event_id.empty? &&
         !Rails.cache.write("escalated:cloud-event:#{event_id}", true, expires_in: REPLAY_TTL, unless_exist: true)
        return render json: { received: true, applied: false, replay: true }, status: :ok
      end

      return ignored("Event #{event} carries no changes for the site.") unless APPLIED_EVENTS.include?(event)

      reference = cloud_ticket['external_id']
      return ignored('Ticket did not originate from this site.') unless reference.is_a?(String) && !reference.empty?

      ticket = Escalated::Ticket.find_by(reference: reference)
      return ignored("No local ticket with reference #{reference}.") unless ticket

      applied = apply(ticket, cloud_ticket)
      render json: { received: true, applied: applied.any?, changes: applied }, status: :ok
    rescue StandardError => e
      Rails.logger.warn("[Escalated::CloudWebhookController] could not apply #{event} to #{reference}: #{e.message}")
      render json: { received: true, applied: false, reason: e.message }, status: :ok
    end

    private

    def driver
      @driver ||= Escalated::Drivers::LocalDriver.new
    end

    def apply(ticket, cloud_ticket)
      applied = []

      content = {}
      %w[subject description].each do |field|
        value = cloud_ticket[field]
        content[field.to_sym] = value.to_s if !value.nil? && value.to_s != ticket.public_send(field).to_s
      end

      if content.any?
        ticket = driver.update_ticket(ticket, content, actor: nil)
        applied.concat(content.keys.map(&:to_s))
      end

      if cloud_ticket.key?('priority')
        priority = Escalated::Support::CloudVocabulary.priority_from_cloud(cloud_ticket['priority'])
        if Escalated::Support::CloudVocabulary::LOCAL_PRIORITIES.include?(priority) && priority != ticket.priority.to_s
          ticket = driver.change_priority(ticket, priority, actor: nil)
          applied << 'priority'
        end
      end

      if cloud_ticket.key?('status')
        status = Escalated::Support::CloudVocabulary.status_from_cloud(cloud_ticket['status'])
        if Escalated::Support::CloudVocabulary::LOCAL_STATUSES.include?(status) && status != ticket.status.to_s
          driver.transition_status(ticket, status, actor: nil)
          applied << 'status'
        end
      end

      applied
    end

    def ignored(reason)
      render json: { received: true, applied: false, reason: reason }, status: :accepted
    end
  end
end
