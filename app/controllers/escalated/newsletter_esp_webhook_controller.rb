# frozen_string_literal: true

module Escalated
  class NewsletterEspWebhookController < ActionController::API
    include Escalated::NewsletterAccess

    before_action :ensure_newsletters_enabled!

    def postmark
      token = token_from_message_id(params[:MessageID].to_s)
      case params[:RecordType].to_s
      when 'Open'
        tracker.record_open(token)
      when 'Click'
        tracker.record_click(token, params[:OriginalLink].to_s)
      when 'Bounce'
        tracker.record_bounce(token, postmark_hard_bounce?(params[:Type].to_s) ? 'hard' : 'soft',
                              params[:Description].to_s)
      when 'SpamComplaint'
        tracker.record_complaint(token)
      end

      render json: { ok: true }
    end

    def mailgun
      event = params.dig('event-data', 'event').to_s
      token = token_from_message_id(params.dig('event-data', 'message', 'headers', 'message-id').to_s)
      case event
      when 'opened'
        tracker.record_open(token)
      when 'clicked'
        tracker.record_click(token, params.dig('event-data', 'url').to_s)
      when 'failed'
        type = params.dig('event-data', 'severity') == 'permanent' ? 'hard' : 'soft'
        tracker.record_bounce(token, type, params.dig('event-data', 'delivery-status', 'description').to_s)
      when 'complained'
        tracker.record_complaint(token)
      end

      render json: { ok: true }
    end

    def ses
      body = params[:Message]
      body = JSON.parse(body) if body.is_a?(String)
      body = body.to_unsafe_h if body.respond_to?(:to_unsafe_h)
      body ||= {}
      token = token_from_message_id(body.dig('mail', 'messageId').to_s)
      case body['eventType']
      when 'Open'
        tracker.record_open(token)
      when 'Click'
        tracker.record_click(token, body.dig('click', 'link').to_s)
      when 'Bounce'
        type = body.dig('bounce', 'bounceType') == 'Permanent' ? 'hard' : 'soft'
        tracker.record_bounce(token, type, body.dig('bounce', 'bounceSubType'))
      when 'Complaint'
        tracker.record_complaint(token)
      end

      render json: { ok: true }
    end

    def sendgrid
      events = request.request_parameters
      events = JSON.parse(request.raw_post) if events.blank? && request.raw_post.present?
      Array(events).each do |event|
        token = token_from_message_id((event['smtp-id'] || event['sg_message_id']).to_s)
        case event['event']
        when 'open'
          tracker.record_open(token)
        when 'click'
          tracker.record_click(token, event['url'].to_s)
        when 'bounce'
          tracker.record_bounce(token, event['type'] == 'blocked' ? 'hard' : 'soft', event['reason'])
        when 'dropped'
          tracker.record_bounce(token, 'hard', event['reason'])
        when 'spamreport'
          tracker.record_complaint(token)
        end
      end

      render json: { ok: true }
    end

    private

    def tracker
      @tracker ||= Escalated::Newsletter::Tracker.new
    end

    def postmark_hard_bounce?(type)
      %w[HardBounce BadEmailAddress BlockedRecipient].include?(type)
    end

    def token_from_message_id(message_id)
      return Regexp.last_match(1) if message_id.match(/n-\d+-([A-Za-z0-9]+)@/)

      local_part = message_id.split('@').first.to_s
      return Regexp.last_match(1) if local_part.match(/^n-\d+-([A-Za-z0-9]+)$/)

      ''
    end
  end
end
