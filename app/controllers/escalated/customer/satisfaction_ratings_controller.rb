module Escalated
  module Customer
    class SatisfactionRatingsController < Escalated::ApplicationController
      before_action :set_ticket

      def create
        unless %w[resolved closed].include?(@ticket.status)
          redirect_back fallback_location: escalated.customer_ticket_path(@ticket),
                        alert: I18n.t('escalated.rating.only_resolved_closed')
          return
        end

        if @ticket.satisfaction_rating.present?
          redirect_back fallback_location: escalated.customer_ticket_path(@ticket),
                        alert: I18n.t('escalated.rating.already_rated')
          return
        end

        rating = Escalated::SatisfactionRating.new(
          ticket: @ticket,
          rating: params[:rating].to_i,
          comment: params[:comment],
          rated_by: escalated_current_user
        )

        if rating.save
          redirect_back fallback_location: escalated.customer_ticket_path(@ticket),
                        notice: I18n.t('escalated.rating.thanks')
        else
          redirect_back fallback_location: escalated.customer_ticket_path(@ticket),
                        alert: rating.errors.full_messages.join(", ")
        end
      end

      private

      def set_ticket
        @ticket = Escalated::Ticket.find_by!(reference: params[:id])
      rescue ActiveRecord::RecordNotFound
        @ticket = Escalated::Ticket.find(params[:id])
      end
    end
  end
end
