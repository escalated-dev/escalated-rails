# frozen_string_literal: true

module Escalated
  module Admin
    # The Webhooks admin screen, shaped for the shared frontend's
    # Admin/Webhooks Index, Form and DeliveryLog pages.
    class WebhooksController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_webhook, only: %i[edit update destroy deliveries]

      def index
        webhooks = Escalated::Webhook.order(created_at: :desc, id: :desc)

        render_page 'Escalated/Admin/Webhooks/Index', {
          webhooks: webhooks.map { |webhook| webhook_json(webhook) }
        }
      end

      def new
        render_page 'Escalated/Admin/Webhooks/Form', { webhook: nil, availableEvents: available_events }
      end

      def edit
        render_page 'Escalated/Admin/Webhooks/Form', {
          webhook: webhook_json(@webhook),
          availableEvents: available_events
        }
      end

      def create
        webhook = Escalated::Webhook.new(webhook_params)

        if webhook.save
          redirect_to escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.created')
        else
          redirect_back_with_errors(webhook)
        end
      end

      def update
        attributes = webhook_params
        # The form is never handed the stored secret, so a blank one means
        # "leave it as it is", not "remove it".
        attributes.delete(:secret) if attributes[:secret].blank?

        if @webhook.update(attributes)
          redirect_to escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.updated')
        else
          redirect_back_with_errors(@webhook)
        end
      end

      def destroy
        @webhook.destroy!
        redirect_to escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.deleted')
      end

      def deliveries
        result = paginate(@webhook.deliveries.order(created_at: :desc, id: :desc))

        render_page 'Escalated/Admin/Webhooks/DeliveryLog', {
          webhook: webhook_json(@webhook),
          deliveries: paginated_page(result, result[:data].map { |delivery| delivery_json(delivery) })
        }
      end

      def retry_delivery
        delivery = Escalated::WebhookDelivery.find(params[:delivery_id])

        Escalated::DeliverWebhookJob.perform_later(delivery.webhook_id, delivery.event, delivery.payload || {})

        redirect_back_or_to(escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.delivery_retried'))
      rescue ActiveRecord::RecordNotFound
        redirect_back_or_to(escalated.admin_webhooks_path, alert: I18n.t('escalated.middleware.not_found'))
      end

      private

      def set_webhook
        @webhook = Escalated::Webhook.find(params[:id])
      end

      # The form sends these keys top-level. They appear under `webhook` only
      # when the host turns on ParamsWrapper for JSON, so nothing relies on that.
      def webhook_params
        params.slice(:url, :secret, :active, :events).permit(:url, :secret, :active, events: [])
      end

      def available_events
        Escalated::Services::WebhookDispatcher::AVAILABLE_EVENTS
      end

      # Inertia's convention for a failed form visit: back to the form, with the
      # errors in the session keyed by field so useForm shows them on the inputs.
      def redirect_back_with_errors(webhook)
        redirect_back_or_to(
          escalated.admin_webhooks_path,
          alert: webhook.errors.full_messages.join(', '),
          inertia: { errors: webhook.errors.to_hash(true).transform_values(&:first) }
        )
      end

      # The secret stays on the server; neither page has a use for it.
      def webhook_json(webhook)
        latest = webhook.deliveries.order(created_at: :desc, id: :desc).first

        {
          id: webhook.id,
          url: webhook.url,
          events: Array(webhook.events),
          active: webhook.active,
          has_secret: webhook.secret.present?,
          deliveries_count: webhook.deliveries.count,
          deliveries: latest ? [delivery_json(latest)] : [],
          created_at: webhook.created_at&.iso8601,
          updated_at: webhook.updated_at&.iso8601
        }
      end

      def delivery_json(delivery)
        {
          id: delivery.id,
          webhook_id: delivery.webhook_id,
          event: delivery.event,
          payload: delivery.payload,
          response_code: delivery.response_code,
          response_body: delivery.response_body,
          attempts: delivery.attempts,
          success: delivery.success?,
          delivered_at: delivery.delivered_at&.iso8601,
          created_at: delivery.created_at&.iso8601
        }
      end
    end
  end
end
