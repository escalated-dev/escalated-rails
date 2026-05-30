# frozen_string_literal: true

module Escalated
  module TicketSubjectsActions
    extend ActiveSupport::Concern

    def create
      payload = params[:subject].present? ? params.require(:subject) : params
      type = payload.require(:type)
      # Route :id is the ticket; subject primary key is subject_id (or subject[id] when nested).
      subject_id = payload[:subject_id].presence || payload[:id]
      role = payload[:role]

      return render json: { errors: { id: ['is required'] } }, status: :unprocessable_content if subject_id.blank?

      unless Escalated::TicketSubjectTypes.allowlist_enforced?
        return render json: { error: 'Ticket subject types are not configured.' }, status: :unprocessable_content
      end

      model_class = Escalated::TicketSubjectTypes.resolve_model_class!(type)
      subject = model_class.find_by(model_class.primary_key => subject_id.to_s)

      unless subject
        return render json: { errors: { id: ['No matching subject was found.'] } },
                      status: :unprocessable_content
      end

      link = @ticket.attach_subject(subject, role: role)

      render json: { subject: Escalated::TicketSerializer.serialize_subject_link(link) }, status: :created
    rescue ArgumentError => e
      render json: { errors: { type: [e.message] } }, status: :unprocessable_content
    end

    def destroy
      link = @ticket.ticket_subjects.find(params[:subject_id])
      link.destroy!

      render json: { success: true }
    end

    private

    def set_ticket
      ticket_key = params[:ticket_id] || params[:id]
      @ticket = Escalated::Ticket.find_by(reference: ticket_key) ||
                Escalated::Ticket.find(ticket_key)
    end
  end
end
