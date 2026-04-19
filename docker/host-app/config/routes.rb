Rails.application.routes.draw do
  mount Escalated::Engine => '/support', as: :escalated_engine

  if Rails.env.demo? || ENV['APP_ENV'] == 'demo'
    get '/demo', to: 'demo#picker', as: :demo_picker
    post '/demo/login/:id', to: 'demo#login_as', as: :demo_login
    post '/demo/logout', to: 'demo#logout', as: :demo_logout
    root to: 'demo#picker'
  else
    root to: proc { [200, {}, ['Escalated Rails demo host. Set APP_ENV=demo to enable /demo routes.']] }
  end
end
