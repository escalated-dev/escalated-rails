# frozen_string_literal: true

module Escalated
  module Services
    # Customer online status (ADR 2026-11-05-agent-panel-data, section 2).
    #
    # Requests the customer already makes (the customer portal, widget chat,
    # the widget's ticket lookup) record when they were last seen, at most once
    # per customer every THROTTLE_SECONDS. A customer is online while that is
    # within config.presence_online_window_seconds (default 120). Only staff
    # pages read it.
    module CustomerPresenceTracker
      THROTTLE_SECONDS = 30

      class << self
        # A signed-in customer-portal user. Staff are not customers.
        def see_user(user)
          return if user.nil? || TicketReads.staff?(user)

          see(user.class.name, user.id)
        end

        # The customer of a ticket the widget just served.
        def see_ticket_customer(ticket)
          subject = subject_of(ticket)
          see(*subject) if subject
        end

        # Presence is a hint: it never fails the request it rides on.
        def quietly
          yield
        rescue StandardError => e
          Rails.logger.warn("[Escalated::CustomerPresence] #{e.message}")
        end

        # { ticket_id => { requester_online:, requester_last_seen_at: } }, from
        # one query. For staff pages only.
        def lookup(tickets)
          tickets = Array(tickets)
          subjects = tickets.filter_map { |ticket| subject_of(ticket) }.uniq
          seen = {}
          if subjects.any?
            clause = subjects.map { '(subject_type = ? AND subject_id = ?)' }.join(' OR ')
            Escalated::CustomerPresence.where(clause, *subjects.flatten)
                                       .pluck(:subject_type, :subject_id, :last_seen_at)
                                       .each { |type, id, at| seen[[type, id]] = at }
          end

          since = window.seconds.ago
          tickets.to_h do |ticket|
            last = (subject = subject_of(ticket)) ? seen[subject] : nil
            [ticket.id, { requester_online: !last.nil? && last >= since, requester_last_seen_at: last&.iso8601 }]
          end
        end

        def window
          seconds = Escalated.configuration.presence_online_window_seconds.to_i
          seconds.positive? ? seconds : 120
        end

        # A ticket's customer: its requester, or its contact for a guest, or
        # the ticket itself for a guest with neither.
        def subject_of(ticket)
          return [ticket.requester_type, ticket.requester_id.to_s] if ticket.requester_type && ticket.requester_id
          return ['Escalated::Contact', ticket.contact_id.to_s] if ticket.respond_to?(:contact_id) && ticket.contact_id
          # A guest known by nothing but the ticket.
          return ['Escalated::Ticket', ticket.id.to_s] if ticket.id

          nil
        end

        private

        # Throttled in the database, so it holds across processes and with any
        # cache store: the row is only written once its last write is 30
        # seconds old.
        def see(type, id)
          id = id.to_s
          now = Time.current
          rows = Escalated::CustomerPresence.where(subject_type: type, subject_id: id)
          return if rows.where(last_seen_at: ..(now - THROTTLE_SECONDS.seconds))
                        .update_all(last_seen_at: now, updated_at: now).positive?
          return if rows.exists?

          Escalated::CustomerPresence.create!(subject_type: type, subject_id: id, last_seen_at: now)
        rescue ActiveRecord::RecordNotUnique
          nil # Another request recorded them first.
        end
      end
    end
  end
end
