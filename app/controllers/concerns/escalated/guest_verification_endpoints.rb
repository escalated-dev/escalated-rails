# frozen_string_literal: true

module Escalated
  # POST verification and POST lookup, under the guest and widget prefixes
  # (escalated-laravel docs/guest-access.md).
  module GuestVerificationEndpoints
    extend ActiveSupport::Concern
    include Escalated::GuestProof

    LOOKUP_LIMIT = 20

    included do
      before_action :throttle_guest_tickets!, only: :request_verification
      before_action :throttle_guest_replies!, only: :lookup
      # Its own name: a controller's after_action :set_guest_privacy_headers
      # would otherwise replace this one and its :only list.
      after_action :verification_privacy_headers, only: %i[request_verification lookup]
    end

    # POST <prefix>/verification {email, purpose: ticket|chat|lookup}
    def request_verification
      purpose = params[:purpose].to_s
      allowed = purpose == 'chat' ? Escalated::EscalatedSetting.chat_enabled? : guest_tickets_allowed?
      return render json: { message: 'Not available.' }, status: :forbidden unless allowed

      id = Services::GuestEmailVerification.challenge(params[:email], purpose, client_ip: request.remote_ip)
      render json: { verification_id: id, expires_in: Services::GuestEmailVerification::CODE_TTL.to_i,
                     message: 'Check your email for a verification code.' }, status: :accepted
    rescue Services::GuestEmailVerification::InvalidRequest => e
      render_guest_errors(params[:purpose].to_s.in?(%w[ticket chat lookup]) ? :email : :purpose, e.message)
    rescue Services::GuestEmailVerification::TooManyRequests => e
      response.headers['Retry-After'] = e.retry_after.to_s
      render json: { message: e.message }, status: :too_many_requests
    end

    # POST <prefix>/lookup {email, reference, verification_id, verification_code}
    #
    # A fresh grant for each of the guest's tickets with that reference, at
    # most 20. A reference alone never finds anything: the verified email
    # must be the ticket's guest email.
    def lookup
      return render json: { message: 'Not available.' }, status: :forbidden unless guest_tickets_allowed?

      missing = %i[email reference verification_id verification_code].select { |key| params[key].blank? }
      if missing.any?
        return render_guest_errors(missing.first, "The #{missing.first.to_s.humanize(capitalize: false)} is required.")
      end

      email = Services::GuestEmailVerification.normalize(params[:email])
      matches = with_guest_proof('lookup', email) do
        guest_tickets_for(email, params[:reference].to_s).map do |ticket|
          token = Escalated::GuestAccess.issue(ticket, email: email)
          { reference: ticket.reference, subject: ticket.subject, guest_access_token: token,
            expires_at: ticket.guest_access_expires_at.iso8601 }
        end
      end
      render json: { data: matches } unless performed?
    end

    private

    def guest_tickets_for(email, reference)
      tickets = Escalated::Ticket.arel_table
      Escalated::TicketAccess.with_actor(nil) do
        Escalated::Ticket.where(reference: reference)
                         .where(tickets[:guest_email].lower.eq(email))
                         .order(created_at: :desc).limit(LOOKUP_LIMIT).to_a
      end
    end

    def verification_privacy_headers
      set_guest_privacy_headers
    end

    def guest_tickets_allowed?
      Escalated::EscalatedSetting.guest_tickets_enabled?
    end
  end
end
