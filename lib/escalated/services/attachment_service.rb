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

        def url_for(attachment, expires_in: 5.minutes)
          return nil unless attachment.file.attached?

          if Escalated.configuration.storage_service == :local
            Rails.application.routes.url_helpers.rails_blob_path(
              attachment.file,
              only_path: true
            )
          else
            attachment.file.url(expires_in: expires_in)
          end
        end

        private

        def validate_count(attachable, new_count)
          existing_count = attachable.attachments.count
          max = Escalated.configuration.max_attachments

          if existing_count + new_count > max
            raise TooManyAttachmentsError,
                  "Maximum #{max} attachments allowed. Currently has #{existing_count}, " \
                  "trying to add #{new_count}."
          end
        end

        def validate_size(file)
          max_bytes = Escalated.configuration.max_attachment_size_kb * 1024

          if file.size > max_bytes
            raise FileTooLargeError,
                  "File '#{file.original_filename}' is #{(file.size / 1024.0).round(1)} KB. " \
                  "Maximum allowed is #{Escalated.configuration.max_attachment_size_kb} KB."
          end
        end

        def validate_type(file)
          unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
            raise InvalidFileTypeError,
                  "File type '#{file.content_type}' is not allowed. " \
                  "Allowed types: #{ALLOWED_CONTENT_TYPES.join(', ')}"
          end
        end
      end
    end
  end
end
