Rails.application.routes.draw do
  mount Escalated::Engine, at: "/support"
end
