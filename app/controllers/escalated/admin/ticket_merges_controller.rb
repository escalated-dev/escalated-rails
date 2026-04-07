# frozen_string_literal: true

module Escalated
  module Admin
    class TicketMergesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_ticket

      def search
        query = params[:q].to_s.strip

        return render json: [] if query.blank?

        tickets = Escalated::Ticket.search(query)
                                   .where.not(id: @ticket.id)
                                   .limit(10)
                                   .map do |t|
                                     {
                                       id: t.id,
                                       reference: t.reference,
                                       subject: t.subject,
                                       status: t.status,
                                       requester: if t.requester
                                                    {
                                                      id: t.requester.id,
                                                      name: if t.requester.respond_to?(:name)
                                                              t.requester.name
                                                            else
                                                              t.requester.email
                                                            end
                                                    }
                                                  end
                                     }
                                   end

        render json: tickets
      end

      def merge
        target_reference = params[:target_reference].to_s.strip
        target = Escalated::Ticket.find_by(reference: target_reference)

        return render json: { error: 'Target ticket not found' }, status: :not_found unless target
        if target.id == @ticket.id
          return render json: { error: 'Cannot merge a ticket into itself' },
                        status: :unprocessable_content
        end

        Services::TicketMergeService.merge(@ticket, target, merged_by: escalated_current_user)

        render json: { success: true, target_id: target.id, target_reference: target.reference }
      rescue Services::TicketMergeService::Error => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def set_ticket
        @ticket = Escalated::Ticket.find(params[:ticket_id])
      end
    end
  end
end
