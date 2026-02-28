module Escalated
  module Admin
    class WebhooksController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_webhook, only: [:update, :destroy, :deliveries]

      def index
        webhooks = Escalated::Webhook.ordered

        render inertia: "Escalated/Admin/Webhooks/Index", props: {
          webhooks: webhooks.map { |w| webhook_json(w) }
        }
      end

      def create
        webhook = Escalated::Webhook.new(webhook_params)

        if webhook.save
          redirect_to escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.created')
        else
          redirect_back fallback_location: escalated.admin_webhooks_path,
                        alert: webhook.errors.full_messages.join(", ")
        end
      end

      def update
        if @webhook.update(webhook_params)
          redirect_to escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.updated')
        else
          redirect_back fallback_location: escalated.admin_webhooks_path,
                        alert: @webhook.errors.full_messages.join(", ")
        end
      end

      def destroy
        @webhook.destroy!
        redirect_to escalated.admin_webhooks_path, notice: I18n.t('escalated.admin.webhook.deleted')
      end

      def deliveries
        result = paginate(@webhook.deliveries.recent)

        render inertia: "Escalated/Admin/Webhooks/Deliveries", props: {
          webhook: webhook_json(@webhook),
          deliveries: result[:data].map { |d| delivery_json(d) },
          meta: result[:meta]
        }
      end

      def retry_delivery
        delivery = Escalated::WebhookDelivery.find(params[:delivery_id])

        Services::WebhookService.retry(delivery)

        redirect_back fallback_location: escalated.admin_webhooks_path,
                      notice: I18n.t('escalated.admin.webhook.delivery_retried')
      rescue ActiveRecord::RecordNotFound
        redirect_back fallback_location: escalated.admin_webhooks_path,
                      alert: I18n.t('escalated.middleware.not_found')
      end

      private

      def set_webhook
        @webhook = Escalated::Webhook.find(params[:id])
      end

      def webhook_params
        params.require(:webhook).permit(:url, :secret, :is_active, events: [])
      end

      def webhook_json(webhook)
        {
          id: webhook.id,
          url: webhook.url,
          is_active: webhook.is_active,
          events: webhook.events,
          deliveries_count: webhook.deliveries.count,
          last_delivery_at: webhook.deliveries.recent.first&.created_at&.iso8601,
          created_at: webhook.created_at&.iso8601,
          updated_at: webhook.updated_at&.iso8601
        }
      end

      def delivery_json(delivery)
        {
          id: delivery.id,
          event: delivery.event,
          status_code: delivery.status_code,
          success: delivery.success?,
          request_body: delivery.request_body,
          response_body: delivery.response_body,
          duration_ms: delivery.duration_ms,
          created_at: delivery.created_at&.iso8601
        }
      end
    end
  end
end
