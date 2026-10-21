# frozen_string_literal: true

module Escalated
  # Serves attachment downloads. The link must be signed and unexpired, and the
  # caller must still have access to the ticket (Escalated::AttachmentAccess).
  # A browser uses the host session; an API client sends its bearer token.
  class AttachmentsController < PublicController
    include Escalated::ApiAuthentication

    skip_before_action :set_inertia_shared_data, raise: false
    skip_forgery_protection

    def show
      attachment = Escalated::Attachment.find_by(id: params[:id])
      link = attachment && Escalated::AttachmentAccess.verify(params[:token], attachment)
      return head(:not_found) unless link

      user = download_user
      return if performed?

      case Escalated::AttachmentAccess.authorize(attachment, link, user)
      when :ok then send_attachment(attachment)
      when :forbidden then head :forbidden
      else head :not_found
      end
    end

    private

    # A supplied bearer token must be valid; it never falls back to the session.
    def download_user
      return escalated_current_user if extract_bearer_token.nil?

      authenticate_api_token!
      current_api_user
    end

    def send_attachment(attachment)
      response.headers['Cache-Control'] = 'private, no-store, max-age=0'
      response.headers['X-Content-Type-Options'] = 'nosniff'
      response.headers['Referrer-Policy'] = 'no-referrer'

      data = attachment.file.download
      send_data data,
                filename: Escalated::AttachmentAccess.safe_filename(attachment),
                type: Escalated::AttachmentAccess.content_type_for(attachment),
                disposition: 'attachment'
    rescue ActiveStorage::FileNotFoundError
      head :not_found
    end
  end
end
