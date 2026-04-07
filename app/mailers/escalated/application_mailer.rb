# frozen_string_literal: true

module Escalated
  class ApplicationMailer < ActionMailer::Base
    default from: lambda {
      Escalated.configuration.respond_to?(:mailer_from) ? Escalated.configuration.mailer_from : 'support@example.com'
    }
    layout 'mailer'
  end
end
