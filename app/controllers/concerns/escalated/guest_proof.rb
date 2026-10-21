# frozen_string_literal: true

module Escalated
  # The emailed-code proof the guest ticket, widget ticket, chat and lookup
  # endpoints require (Escalated::Services::GuestEmailVerification).
  module GuestProof
    extend ActiveSupport::Concern

    private

    # Runs the block once the request's proof for this purpose and email is
    # consumed, in one transaction with it. Renders 422 and returns nil when
    # the proof is missing or wrong.
    def with_guest_proof(purpose, email, &)
      if params[:verification_id].blank? || params[:verification_code].blank?
        render_guest_errors(:verification_code, 'Verify your email address first.')
        return nil
      end

      Services::GuestEmailVerification.consume(params[:verification_id], params[:verification_code].to_s,
                                               email, purpose, &)
    rescue Services::GuestEmailVerification::InvalidCode => e
      render_guest_errors(:verification_code, e.message)
      nil
    end

    def render_guest_errors(field, message)
      render json: { message: message, errors: { field => [message] } }, status: :unprocessable_content
    end

    # Grants travel in these responses and in guest page URLs.
    def set_guest_privacy_headers
      no_store
      response.headers['Referrer-Policy'] = 'no-referrer'
    end
  end
end
