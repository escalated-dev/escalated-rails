# frozen_string_literal: true

module Escalated
  module Admin
    class TicketSubjectsController < Escalated::ApplicationController
      include Escalated::TicketSubjectsActions

      before_action :require_admin!
      before_action :set_ticket
    end
  end
end
