# frozen_string_literal: true

module Escalated
  # Serializes ticket payloads shared by agent, admin, and API surfaces.
  class TicketSerializer
    class << self
      def subjects_for(ticket)
        ticket.ticket_subjects.order(:position).map { |link| serialize_subject_link(link) }
      end

      def serialize_subject_link(link)
        subject = link.subject
        presents = subject.respond_to?(:ticket_subject_title)
        missing = subject.nil?

        {
          type: link.subject_type,
          id: link.subject_id,
          role: link.role,
          title: subject_title(link, subject, presents),
          subtitle: presents ? subject.ticket_subject_subtitle : nil,
          url: presents ? subject.ticket_subject_url : nil,
          color: presents ? subject.ticket_subject_color : nil,
          icon: presents ? subject.ticket_subject_icon : nil,
          missing: missing
        }
      end

      private

      def subject_title(link, subject, presents)
        if presents
          subject.ticket_subject_title
        elsif subject
          subject.try(:name) || subject.try(:title) || "#{demodulize_type(link.subject_type)} ##{link.subject_id}"
        else
          "#{demodulize_type(link.subject_type)} ##{link.subject_id}"
        end
      end

      def demodulize_type(type)
        type.to_s.demodulize
      end
    end
  end
end
