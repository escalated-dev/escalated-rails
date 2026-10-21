# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Escalated
  # Expiring guest grants (escalated-laravel docs/guest-access.md).
  #
  # A grant is an opaque, encrypted and authenticated token naming one ticket,
  # its purpose, a digest of the verified email, a random nonce and an expiry.
  # The ticket stores only the nonce's SHA-256 (guest_access_hash) and the
  # expiry, so issuing a new grant, changing the guest email or #revoke
  # invalidates every earlier one, and the attachment links issued under it.
  #
  # Issue a grant only after GuestEmailVerification has consumed a proof for
  # the ticket's email.
  #
  # Tickets created before grants carry a permanent guest_token. While
  # `accept_legacy_guest_tokens` is on (the default for now), those tokens keep
  # working on the guest page and the widget until a grant is issued for the
  # ticket, which retires the token.
  module GuestAccess
    PURPOSES = %w[ticket chat].freeze
    VERSION = 1

    module_function

    # Marks the ticket's email as verified and returns a new grant.
    def issue(ticket, email:, purpose: 'ticket')
      raise ArgumentError, "Unsupported guest access purpose: #{purpose}" unless PURPOSES.include?(purpose.to_s)

      email = Services::GuestEmailVerification.normalize(email)
      unless email.present? && Services::GuestEmailVerification.normalize(ticket.guest_email) == email
        raise ArgumentError, 'Guest access needs the ticket email that was verified'
      end

      nonce = SecureRandom.alphanumeric(64)
      expires_at = ttl.from_now.change(usec: 0)
      ticket.update_columns(
        guest_verified_email: email, guest_email_verified_at: Time.current.change(usec: 0),
        guest_access_hash: Digest::SHA256.hexdigest(nonce), guest_access_expires_at: expires_at,
        guest_token: nil
      )

      claims = {
        'v' => VERSION, 'ticket' => ticket.id.to_s, 'purpose' => purpose.to_s,
        'email' => Digest::SHA256.hexdigest(email), 'nonce' => nonce, 'expires' => expires_at.to_i
      }
      encryptor.encrypt_and_sign(claims, expires_at: expires_at, purpose: :escalated_guest_access)
    end

    # The ticket a grant names, or nil when it is forged, expired, rotated,
    # revoked or for another purpose.
    def resolve(token, purpose: 'ticket')
      token = token.to_s
      return nil if token.empty? || token.length > 4096 || !token.match?(/\A[A-Za-z0-9_\-=]+\z/)

      claims = encryptor.decrypt_and_verify(token, purpose: :escalated_guest_access)
      return nil unless valid_claims?(claims, purpose)

      # Under the caller's ticket visibility: a guest sees every ticket, a
      # restricted agent signed in on the same site only their own.
      ticket = Escalated::Ticket.find_by(id: claims['ticket'])
      return nil unless ticket && active?(ticket)
      return nil unless ticket.guest_access_expires_at.to_i == claims['expires']
      return nil unless ActiveSupport::SecurityUtils.secure_compare(ticket.guest_access_hash,
                                                                    Digest::SHA256.hexdigest(claims['nonce']))
      return nil unless claims['email'] == Digest::SHA256.hexdigest(ticket.guest_verified_email.to_s)

      ticket
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature,
           ArgumentError, TypeError
      nil
    end

    # The guest page and widget: a grant, or a legacy permanent token while
    # those are still accepted.
    def find_ticket(token, purpose: 'ticket')
      resolve(token, purpose: purpose) || legacy_ticket(token)
    end

    def legacy_ticket(token)
      return nil unless Escalated.configuration.accept_legacy_guest_tokens
      return nil unless token.is_a?(String) && token.match?(/\A[0-9A-Za-z_-]{1,64}\z/)

      Escalated::Ticket.find_by(guest_token: token)
    end

    def active?(ticket)
      verified?(ticket) && ticket.guest_access_hash.to_s.length == 64 &&
        ticket.guest_access_expires_at.present? && ticket.guest_access_expires_at > Time.current
    end

    def revoke(ticket)
      ticket.update_columns(guest_access_hash: nil, guest_access_expires_at: nil, guest_token: nil)
    end

    def verified?(ticket)
      ticket.guest_email_verified_at.present? && ticket.guest_email.present? &&
        ticket.guest_verified_email == Services::GuestEmailVerification.normalize(ticket.guest_email)
    end

    def ttl
      Escalated.configuration.guest_access_ttl_minutes.to_i.clamp(5, 10_080).minutes
    end

    def valid_claims?(claims, purpose)
      claims.is_a?(Hash) && claims['v'] == VERSION && claims['purpose'] == purpose.to_s &&
        claims['ticket'].is_a?(String) && claims['nonce'].is_a?(String) && claims['nonce'].length == 64 &&
        claims['expires'].is_a?(Integer) && claims['expires'] > Time.current.to_i
    end

    def encryptor
      key = Rails.application.key_generator.generate_key('escalated guest access grant', 32)
      ActiveSupport::MessageEncryptor.new(key, url_safe: true, serializer: JSON)
    end
  end
end
