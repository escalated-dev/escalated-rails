# frozen_string_literal: true

require 'digest'

module Escalated
  # Who may download an attachment, and the short-lived signed links the
  # serializers hand out (escalated-laravel docs/private-attachments.md).
  #
  # A link names one attachment and expires after
  # `attachment_download_ttl_minutes` (default 10, 1 to 60). It never grants
  # anything by itself: the download still needs, at that moment,
  #
  # - an agent or admin who can see the ticket (TicketPolicy#show?), or
  # - the ticket's requester, for an attachment that is not on an internal
  #   note, or
  # - a guest capability baked into the link when a guest page that had
  #   already proved the ticket's guest credential rendered it. It is bound to
  #   that ticket and to the credential, so rotating or expiring the credential
  #   revokes the links issued under it. It never covers internal notes.
  module AttachmentAccess
    PURPOSE = :escalated_attachment_download

    # The stored types a browser may be told; everything else is sent as
    # application/octet-stream. Always with Content-Disposition: attachment
    # and nosniff, so nothing is rendered inline on the help desk's origin.
    SAFE_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp application/pdf].freeze

    module_function

    def ticket_for(attachment)
      parent = attachment.attachable
      case parent
      when Escalated::Ticket then parent
      when Escalated::Reply then parent.ticket
      end
    end

    # On the ticket itself or on a public reply; never on an internal note.
    def public?(attachment)
      parent = attachment.attachable
      parent.is_a?(Escalated::Ticket) || (parent.is_a?(Escalated::Reply) && !parent.is_internal)
    end

    def ttl
      minutes = Escalated.configuration.attachment_download_ttl_minutes.to_i
      minutes.clamp(1, 60).minutes
    end

    # The download link for a serializer. Pass the ticket a guest page has
    # authenticated to give the link that guest's capability.
    def url(attachment, guest_ticket: nil)
      data = { 'id' => attachment.id.to_s }
      expires_in = ttl
      if guest_ticket && guest_capability?(attachment, guest_ticket)
        data['guest'] = guest_secret(guest_ticket)
        remaining = guest_expires_at(guest_ticket)&.-(Time.current)
        expires_in = [expires_in, remaining].min if remaining
      end

      token = verifier.generate(data, expires_in: expires_in, purpose: PURPOSE)
      Escalated::Engine.routes.url_helpers.attachment_download_path(
        attachment.id, token: token, script_name: "/#{Escalated.configuration.route_prefix}"
      )
    end

    # The link's payload when it is genuine, unexpired and names this
    # attachment; nil otherwise.
    def verify(token, attachment)
      data = verifier.verified(token.to_s, purpose: PURPOSE)
      return nil unless data.is_a?(Hash) && data['id'].to_s == attachment.id.to_s

      data
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
      nil
    end

    # :ok, :not_found or :forbidden for a verified link and the caller.
    def authorize(attachment, link, user)
      ticket = unscoped { ticket_for(attachment) }
      return :not_found unless ticket && attachment.file.attached?
      return :ok if guest_allowed?(attachment, ticket, link['guest'])
      return :forbidden unless user && Escalated::TicketPolicy.new(user, ticket).show?
      return :ok if public?(attachment)

      staff?(user) ? :ok : :forbidden
    end

    def content_type_for(attachment)
      type = attachment.content_type.to_s.downcase
      SAFE_CONTENT_TYPES.include?(type) ? type : 'application/octet-stream'
    end

    # The stored name with any path and control characters removed.
    def safe_filename(attachment)
      name = File.basename(attachment.filename.to_s.tr('\\', '/'))
      name = name.gsub(/[\x00-\x1F\x7F]/, '')
      name.presence || 'attachment'
    end

    def guest_capability?(attachment, ticket)
      public?(attachment) && ticket_for(attachment)&.id == ticket.id && guest_secret(ticket).present?
    end

    def guest_allowed?(attachment, ticket, secret)
      return false unless secret.is_a?(String) && public?(attachment)

      current = guest_secret(ticket)
      return false if current.blank?

      expires_at = guest_expires_at(ticket)
      return false if expires_at && expires_at <= Time.current

      ActiveSupport::SecurityUtils.secure_compare(current, secret)
    end

    # A digest of the ticket's guest credential -- its active grant, or a
    # legacy guest_token while those are accepted -- so the link carries no
    # credential and goes dead when the grant is rotated, revoked or expires.
    def guest_secret(ticket)
      credential = if Escalated::GuestAccess.active?(ticket)
                     ticket.guest_access_hash
                   elsif Escalated.configuration.accept_legacy_guest_tokens
                     ticket.guest_token
                   end
      credential.present? ? Digest::SHA256.hexdigest("escalated-attachment:#{credential}") : nil
    end

    def guest_expires_at(ticket)
      ticket.guest_access_expires_at if Escalated::GuestAccess.active?(ticket)
    end

    def staff?(user)
      (user.respond_to?(:escalated_agent?) && user.escalated_agent?) ||
        (user.respond_to?(:escalated_admin?) && user.escalated_admin?)
    end

    # The ticket default scope narrows by the current actor; access is decided
    # by TicketPolicy here instead.
    def unscoped(&)
      Escalated::TicketAccess.with_actor(nil, &)
    end

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
