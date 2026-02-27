module Escalated
  class WebhookDelivery < ApplicationRecord
    self.table_name = Escalated.table_name("webhook_deliveries")

    belongs_to :webhook, class_name: "Escalated::Webhook"

    def success?
      response_code.to_i.between?(200, 299)
    end
  end
end
