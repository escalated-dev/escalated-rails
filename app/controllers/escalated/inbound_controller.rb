module Escalated
  class InboundController < ActionController::Base
    skip_before_action :verify_authenticity_token

    before_action :ensure_inbound_enabled

    def webhook
      adapter = resolve_adapter(params[:adapter])

      unless adapter
        render json: { error: "Unknown adapter: #{params[:adapter]}" }, status: :bad_request
        return
      end

      # Verify request authenticity (signature, token, etc.)
      unless adapter.verify_request(request)
        Rails.logger.warn(
          "[Escalated::InboundController] Webhook verification failed for adapter: #{params[:adapter]}"
        )
        render json: { error: "Verification failed" }, status: :unauthorized
        return
      end

      # Parse the request into an InboundMessage
      message = adapter.parse_request(request)

      # SES subscription confirmations return nil — acknowledge silently
      unless message
        render json: { status: "ok" }, status: :ok
        return
      end

      # Process the inbound email
      inbound_email = Services::InboundEmailService.process(
        message,
        adapter_name: adapter.adapter_name
      )

      if inbound_email&.processed?
        render json: {
          status: "processed",
          ticket_id: inbound_email.ticket_id,
          reply_id: inbound_email.reply_id
        }, status: :ok
      elsif inbound_email&.failed?
        render json: {
          status: "failed",
          error: inbound_email.error_message
        }, status: :unprocessable_entity
      else
        render json: { status: "ok" }, status: :ok
      end
    rescue StandardError => e
      Rails.logger.error(
        "[Escalated::InboundController] Unexpected error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      )
      render json: { error: "Internal error" }, status: :internal_server_error
    end

    private

    def ensure_inbound_enabled
      unless Escalated.configuration.inbound_email_enabled
        render json: { error: "Inbound email is disabled" }, status: :not_found
      end
    end

    ADAPTER_MAP = {
      "mailgun" => -> { Escalated::Mail::Adapters::MailgunAdapter.new },
      "postmark" => -> { Escalated::Mail::Adapters::PostmarkAdapter.new },
      "ses" => -> { Escalated::Mail::Adapters::SesAdapter.new }
    }.freeze

    def resolve_adapter(adapter_name)
      factory = ADAPTER_MAP[adapter_name.to_s.downcase]
      factory&.call
    end
  end
end
