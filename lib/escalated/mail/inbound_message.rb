module Escalated
  module Mail
    class InboundMessage
      attr_accessor :from_email, :from_name, :to_email, :subject,
                    :body_text, :body_html, :message_id, :in_reply_to,
                    :references, :headers, :attachments

      def initialize(**attrs)
        @from_email = attrs[:from_email]
        @from_name = attrs[:from_name]
        @to_email = attrs[:to_email]
        @subject = attrs[:subject]
        @body_text = attrs[:body_text]
        @body_html = attrs[:body_html]
        @message_id = attrs[:message_id]
        @in_reply_to = attrs[:in_reply_to]
        @references = attrs[:references] || []
        @headers = attrs[:headers] || {}
        @attachments = attrs[:attachments] || []
      end

      # Extract ticket reference from subject line (e.g., "Re: [ESC-2602-ABC123] Original subject")
      def ticket_reference
        match = subject&.match(/\[([A-Z0-9]+-\d{4}-[A-Z0-9]+)\]/)
        match ? match[1] : nil
      end

      # Strip the ticket reference tag from the subject for display
      def clean_subject
        return subject unless subject

        subject.gsub(/\s*\[[A-Z0-9]+-\d{4}-[A-Z0-9]+\]\s*/, "")
          .gsub(/\A\s*(Re|Fwd|Fw):\s*/i, "")
          .strip
      end

      # Determine the best body content to use as reply/description text
      def body
        if body_text.present?
          body_text.strip
        elsif body_html.present?
          strip_html(body_html).strip
        else
          ""
        end
      end

      def valid?
        from_email.present? && to_email.present? && subject.present?
      end

      def reply?
        in_reply_to.present? || ticket_reference.present?
      end

      def raw_headers_string
        return "" if headers.blank?

        headers.map { |k, v| "#{k}: #{v}" }.join("\n")
      end

      private

      def strip_html(html)
        # Basic HTML tag stripping — production systems may want a proper sanitizer
        text = html.gsub(/<br\s*\/?>|<\/p>|<\/div>|<\/li>/i, "\n")
        text = text.gsub(/<[^>]+>/, "")
        text = text.gsub(/&nbsp;/i, " ")
        text = text.gsub(/&amp;/i, "&")
        text = text.gsub(/&lt;/i, "<")
        text = text.gsub(/&gt;/i, ">")
        text = text.gsub(/&quot;/i, '"')
        text = text.gsub(/&#39;/i, "'")
        text.gsub(/\n{3,}/, "\n\n")
      end
    end
  end
end
