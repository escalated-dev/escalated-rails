# frozen_string_literal: true

module Escalated
  module Guest
    # POST /guest/verification and POST /guest/lookup for the guest pages
    # (Guest/Create's verification_url and lookup_url).
    class VerificationsController < Escalated::PublicController
      include Escalated::GuestThrottling
      include Escalated::GuestVerificationEndpoints

      protect_from_forgery with: :exception
      skip_before_action :set_inertia_shared_data, raise: false

      private

      def guest_throttle_json?
        true
      end
    end
  end
end
