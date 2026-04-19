Rails.application.config.to_prepare do
  Escalated::ApplicationController.include(DemoAuth)
  Escalated::ApplicationController.layout('application')
end

InertiaRails.configure do |config|
  config.layout = 'application'
end

Escalated.configure do |config|
  config.user_class = 'User'
end
