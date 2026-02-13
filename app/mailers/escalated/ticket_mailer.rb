module Escalated
  class TicketMailer < ApplicationMailer
    def new_ticket(ticket)
      @ticket = ticket
      @requester = ticket.requester

      mail(
        to: @requester.email,
        subject: I18n.t('escalated.mailer.new_ticket', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def reply_received(ticket, reply)
      @ticket = ticket
      @reply = reply

      # Notify the requester if an agent replied, or notify the assignee if the customer replied
      recipient = if reply.author == ticket.requester
                    ticket.assignee&.email
                  else
                    ticket.requester.email
                  end

      return unless recipient

      mail(
        to: recipient,
        subject: I18n.t('escalated.mailer.reply', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def ticket_assigned(ticket)
      @ticket = ticket
      @assignee = ticket.assignee

      return unless @assignee&.email

      mail(
        to: @assignee.email,
        subject: I18n.t('escalated.mailer.assigned', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def status_changed(ticket)
      @ticket = ticket

      mail(
        to: ticket.requester.email,
        subject: I18n.t('escalated.mailer.status_updated', reference: ticket.reference, status: ticket.status.humanize)
      )
    end

    def sla_breach(ticket)
      @ticket = ticket

      recipients = []
      recipients << ticket.assignee.email if ticket.assignee&.email
      recipients << ticket.department&.email if ticket.department&.email

      return if recipients.empty?

      mail(
        to: recipients.compact.uniq,
        subject: I18n.t('escalated.mailer.sla_breach', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def ticket_escalated(ticket, rule)
      @ticket = ticket
      @rule = rule

      recipients = Array(rule.actions["notification_recipients"])
      recipients << ticket.assignee&.email if ticket.assignee
      recipients << ticket.department&.email if ticket.department

      return if recipients.compact.empty?

      mail(
        to: recipients.compact.uniq,
        subject: I18n.t('escalated.mailer.escalated', reference: ticket.reference, subject: ticket.subject)
      )
    end

    def ticket_resolved(ticket)
      @ticket = ticket

      mail(
        to: ticket.requester.email,
        subject: I18n.t('escalated.mailer.resolved', reference: ticket.reference, subject: ticket.subject)
      )
    end
  end
end
