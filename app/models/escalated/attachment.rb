module Escalated
  class Attachment < ApplicationRecord
    self.table_name = Escalated.table_name("attachments")

    belongs_to :attachable, polymorphic: true

    has_one_attached :file

    validates :filename, presence: true
    validates :content_type, presence: true
    validates :byte_size, presence: true,
              numericality: {
                less_than_or_equal_to: -> { Escalated.configuration.max_attachment_size_kb * 1024 }
              }

    before_validation :set_metadata_from_file, if: -> { file.attached? && filename.blank? }

    scope :images, -> { where("content_type LIKE ?", "image/%") }
    scope :documents, -> { where.not("content_type LIKE ?", "image/%") }
    scope :recent, -> { order(created_at: :desc) }

    def image?
      content_type&.start_with?("image/")
    end

    def human_size
      if byte_size < 1024
        "#{byte_size} B"
      elsif byte_size < 1_048_576
        "#{(byte_size / 1024.0).round(1)} KB"
      else
        "#{(byte_size / 1_048_576.0).round(1)} MB"
      end
    end

    private

    def set_metadata_from_file
      return unless file.attached?

      self.filename = file.filename.to_s
      self.content_type = file.content_type
      self.byte_size = file.byte_size
    end
  end
end
