# frozen_string_literal: true

module Escalated
  class ApplicationMailer < ActionMailer::Base
    default from: -> { Escalated.configuration.mailer_from.presence || 'support@example.com' }
    layout 'mailer'
  end
end
