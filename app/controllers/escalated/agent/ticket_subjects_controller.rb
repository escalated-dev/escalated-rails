# frozen_string_literal: true

module Escalated
  module Agent
    class TicketSubjectsController < Escalated::ApplicationController
      include Escalated::TicketSubjectsActions

      before_action :require_agent!
      before_action :set_ticket
    end
  end
end
