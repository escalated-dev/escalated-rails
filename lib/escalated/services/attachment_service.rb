# frozen_string_literal: true

module Escalated
  module Services
    class AttachmentService
      class TooManyAttachmentsError < StandardError; end
      class FileTooLargeError < StandardError; end
      class InvalidFileTypeError < StandardError; end

      ALLOWED_CONTENT_TYPES = %w[
        image/jpeg
        image/png
        image/gif
        image/webp
        image/svg+xml
        application/pdf
        application/msword
        application/vnd.openxmlformats-officedocument.wordprocessingml.document
        application/vnd.ms-excel
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
        text/plain
        text/csv
        application/zip
        application/x-zip-compressed
      ].freeze

      class << self
        def attach(attachable, files)
          files = Array(files)

          validate_count(attachable, files.size)

          attachments = []

          files.each do |file|
            validate_size(file)
            validate_type(file)

            attachment = attachable.attachments.create!(
              filename: file.original_filename,
              content_type: file.content_type,
              byte_size: file.size
            )

            attachment.file.attach(file)
            attachments << attachment
          end

          attachments
        end

        def detach(attachment)
          attachment.file.purge if attachment.file.attached?
          attachment.destroy!
        end

        def purge_orphaned
          # Remove attachments whose attachable has been deleted
          Escalated::Attachment.where(attachable_type: nil).or(
            Escalated::Attachment.where(attachable_id: nil)
          ).find_each do |attachment|
            detach(attachment)
          end
        end

        # The signed, expiring download route (Escalated::AttachmentAccess),
        # never a storage URL: those skip the ticket-access check.
        def url_for(attachment, guest_ticket: nil)
          return nil unless attachment.file.attached?

          Escalated::AttachmentAccess.url(attachment, guest_ticket: guest_ticket)
        end

        private

        def validate_count(attachable, new_count)
          existing_count = attachable.attachments.count
          max = Escalated.configuration.max_attachments

          return unless existing_count + new_count > max

          raise TooManyAttachmentsError,
                "Maximum #{max} attachments allowed. Currently has #{existing_count}, " \
                "trying to add #{new_count}."
        end

        def validate_size(file)
          max_bytes = Escalated.configuration.max_attachment_size_kb * 1024

          return unless file.size > max_bytes

          raise FileTooLargeError,
                "File '#{file.original_filename}' is #{(file.size / 1024.0).round(1)} KB. " \
                "Maximum allowed is #{Escalated.configuration.max_attachment_size_kb} KB."
        end

        def validate_type(file)
          return if ALLOWED_CONTENT_TYPES.include?(file.content_type)

          raise InvalidFileTypeError,
                "File type '#{file.content_type}' is not allowed. " \
                "Allowed types: #{ALLOWED_CONTENT_TYPES.join(', ')}"
        end
      end
    end
  end
end
