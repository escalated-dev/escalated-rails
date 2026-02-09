Escalated::Engine.routes.draw do
  # Customer-facing routes
  namespace :customer do
    resources :tickets, only: [:index, :create, :show] do
      member do
        post :reply
        post :close
        post :reopen
      end
      collection do
        get :new, action: :create, as: :new
      end
    end
  end

  # Agent routes
  namespace :agent do
    get "/", to: "dashboard#index", as: :dashboard
    resources :tickets, only: [:index, :show, :update] do
      member do
        post :reply
        post :note
        post :assign
        post :status
        post :priority
        post :tags
        post :department
      end
    end
  end

  # Admin routes
  namespace :admin do
    resources :tickets, only: [:index, :show] do
      member do
        post :reply
        post :note
        post :assign
        post :status
        post :priority
        post :tags
        post :department
      end
    end
    resources :departments
    resources :sla_policies
    resources :escalation_rules
    resources :tags, only: [:index, :create, :update, :destroy]
    resources :canned_responses, only: [:index, :create, :update, :destroy]
    get :reports, to: "reports#index"
    get :settings, to: "settings#index"
    post :settings, to: "settings#update"
  end

  # Guest routes (no authentication required)
  namespace :guest do
    get "create", to: "tickets#create"
    post "/", to: "tickets#store", as: :tickets
    get ":token", to: "tickets#show", as: :ticket
    post ":token/reply", to: "tickets#reply", as: :ticket_reply
  end

  # Inbound email webhook (no authentication — verified by adapter)
  post "inbound/:adapter", to: "inbound#webhook", as: :inbound_webhook

  # Root redirect to customer tickets
  root to: "customer/tickets#index"
end
