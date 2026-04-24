# frozen_string_literal: true

require 'escalated/mail/message_id_util'

module Escalated
  class TicketMailer < ApplicationMailer
    def new_ticket(ticket)
      @ticket = ticket
      @requester = ticket.requester
      load_branding

      headers['Message-ID'] = ticket_message_id(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: @requester.email,
        subject: I18n.t('escalated.mailer.new_ticket', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def reply_received(ticket, reply)
      @ticket = ticket
      @reply = reply
      load_branding

      # Notify the requester if an agent replied, or notify the assignee if the customer replied
      recipient = if reply.author == ticket.requester
                    ticket.assignee&.email
                  else
                    ticket.requester.email
                  end

      return unless recipient

      # Own Message-ID includes the reply id so clients can deduplicate
      # across send/receive legs.
      headers['Message-ID'] = reply_message_id(ticket, reply)
      set_threading_headers(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: recipient,
        subject: I18n.t('escalated.mailer.reply', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def ticket_assigned(ticket)
      @ticket = ticket
      @assignee = ticket.assignee
      load_branding

      return unless @assignee&.email

      set_threading_headers(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: @assignee.email,
        subject: I18n.t('escalated.mailer.assigned', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def status_changed(ticket)
      @ticket = ticket
      load_branding

      set_threading_headers(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: ticket.requester.email,
        subject: I18n.t('escalated.mailer.status_updated', reference: ticket.reference, status: ticket.status.humanize)
      )
    end

    def sla_breach(ticket)
      @ticket = ticket
      load_branding

      recipients = []
      recipients << ticket.assignee.email if ticket.assignee&.email
      recipients << ticket.department&.email if ticket.department&.email

      return if recipients.empty?

      set_threading_headers(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: recipients.compact.uniq,
        subject: I18n.t('escalated.mailer.sla_breach', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def ticket_escalated(ticket, rule)
      @ticket = ticket
      @rule = rule
      load_branding

      recipients = Array(rule.actions['notification_recipients'])
      recipients << ticket.assignee&.email if ticket.assignee
      recipients << ticket.department&.email if ticket.department

      return if recipients.compact.empty?

      set_threading_headers(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: recipients.compact.uniq,
        subject: I18n.t('escalated.mailer.escalated', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def ticket_resolved(ticket)
      @ticket = ticket
      load_branding

      set_threading_headers(ticket)
      apply_signed_reply_to(ticket)

      mail(
        to: ticket.requester.email,
        subject: I18n.t('escalated.mailer.resolved', reference: ticket.reference, subject: ticket.subject)
      )
    end

    private

    # RFC 5322 Message-ID for the ticket root (the thread anchor).
    def ticket_message_id(ticket)
      Escalated::Mail::MessageIdUtil.build_message_id(ticket.id, nil, mail_domain)
    end

    # RFC 5322 Message-ID for a specific reply, referencing the root.
    def reply_message_id(ticket, reply)
      Escalated::Mail::MessageIdUtil.build_message_id(ticket.id, reply.id, mail_domain)
    end

    def set_threading_headers(ticket)
      original_message_id = ticket_message_id(ticket)
      headers['In-Reply-To'] = original_message_id
      headers['References'] = original_message_id
    end

    # Signed Reply-To so the inbound provider webhook can verify
    # ticket identity even when clients strip the Message-ID chain.
    # Skipped when email_inbound_secret is blank.
    def apply_signed_reply_to(ticket)
      secret = Escalated.configuration.email_inbound_secret.to_s
      return if secret.empty?

      headers['Reply-To'] = Escalated::Mail::MessageIdUtil.build_reply_to(ticket.id, secret, mail_domain)
    end

    def mail_domain
      configured = Escalated.configuration.email_domain.to_s
      return configured unless configured.empty?

      from_address = Escalated.configuration.respond_to?(:mailer_from) ? Escalated.configuration.mailer_from : nil
      if from_address.present? && from_address.include?('@')
        from_address.split('@').last
      else
        'escalated.localhost'
      end
    end

    def load_branding
      @email_logo_url = Escalated::EscalatedSetting.get('email_logo_url')
      @email_accent_color = Escalated::EscalatedSetting.get('email_accent_color', '#4F46E5')
      @email_footer_text = Escalated::EscalatedSetting.get('email_footer_text')
    end
  end
end
