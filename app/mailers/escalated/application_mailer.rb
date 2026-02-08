module Escalated
  class ApplicationMailer < ActionMailer::Base
    default from: -> { Escalated.configuration.respond_to?(:mailer_from) ? Escalated.configuration.mailer_from : "support@example.com" }
    layout "mailer"
  end
end
