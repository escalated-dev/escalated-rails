# frozen_string_literal: true

module Escalated
  # Default presentation for host models attached as ticket subjects.
  #
  #   class Project < ApplicationRecord
  #     include Escalated::PresentsAsTicketSubject
  #
  #     def ticket_subject_subtitle
  #       "Project · #{customer.name}"
  #     end
  #   end
  module PresentsAsTicketSubject
    extend ActiveSupport::Concern

    def ticket_subject_title
      %i[name title label].each do |attribute|
        value = self[attribute] if has_attribute?(attribute)
        value ||= public_send(attribute) if respond_to?(attribute)
        return value if value.is_a?(String) && value.present?
      end

      "#{self.class.name.demodulize} ##{id}"
    end

    def ticket_subject_subtitle
      nil
    end

    def ticket_subject_url
      nil
    end

    def ticket_subject_color
      nil
    end

    def ticket_subject_icon
      nil
    end
  end
end
