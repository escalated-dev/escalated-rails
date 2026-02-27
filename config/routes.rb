Escalated::Engine.routes.draw do
  # Customer-facing routes
  namespace :customer do
    resources :tickets, only: [:index, :create, :show] do
      member do
        post :reply
        post :close
        post :reopen
        post :rate, to: "satisfaction_ratings#create"
      end
      collection do
        get :new, action: :create, as: :new
      end
    end
  end

  # Agent routes
  namespace :agent do
    get "/", to: "dashboard#index", as: :dashboard
    post "tickets/bulk", to: "bulk_actions#create", as: :tickets_bulk
    resources :tickets, only: [:index, :show, :update] do
      member do
        post :reply
        post :note
        post :assign
        post :status
        post :priority
        post :tags
        post :department
        post :macro, action: :apply_macro
        post :follow
        post :presence
        post "replies/:reply_id/pin", action: :pin, as: :reply_pin
      end
    end
  end

  # Admin routes
  namespace :admin do
    post "tickets/bulk", to: "bulk_actions#create", as: :tickets_bulk
    resources :tickets, only: [:index, :show] do
      member do
        post :reply
        post :note
        post :assign
        post :status
        post :priority
        post :tags
        post :department
        post :macro, action: :apply_macro
        post :follow
        post :presence
        post "replies/:reply_id/pin", action: :pin, as: :reply_pin
      end
    end
    resources :departments
    resources :sla_policies
    resources :escalation_rules
    resources :tags, only: [:index, :create, :update, :destroy]
    resources :canned_responses, only: [:index, :create, :update, :destroy]
    resources :macros, only: [:index, :create, :update, :destroy]
    resources :api_tokens, only: [:index, :create, :update, :destroy]
    resources :plugins, only: [:index, :destroy] do
      member do
        post :activate
        post :deactivate
      end
      collection do
        post :upload
      end
    end
    get :reports, to: "reports#index"
    get "reports/dashboard", to: "reports#dashboard", as: :reports_dashboard
    get :settings, to: "settings#index"
    post :settings, to: "settings#update"

    # Phase 1
    resources :statuses, only: [:index, :create, :update, :destroy]
    resources :business_hours, only: [:index, :create, :update, :destroy]
    resources :roles, only: [:index, :create, :update, :destroy]
    resources :audit_logs, only: [:index]

    # Phase 2
    resources :custom_fields, only: [:index, :create, :update, :destroy] do
      collection do
        post :reorder
      end
    end
    resources :tickets, only: [] do
      member do
        get :links, to: "ticket_links#index"
        post :store_link, to: "ticket_links#store"
        delete "links/:link_id", to: "ticket_links#destroy", as: :destroy_link
        get :merge_search, to: "ticket_merges#search"
        post :merge, to: "ticket_merges#merge"
        get :side_conversations, to: "side_conversations#index"
        post :store_side_conversation, to: "side_conversations#store"
        post "side_conversations/:conversation_id/reply", to: "side_conversations#reply", as: :side_conversation_reply
        post "side_conversations/:conversation_id/close", to: "side_conversations#close", as: :side_conversation_close
      end
    end
    resources :articles, only: [:index, :create, :update, :destroy]
    resources :kb_categories, only: [:index, :create, :update, :destroy]

    # Phase 3
    resources :skills, only: [:index, :create, :update, :destroy]
    resources :capacity, only: [:index, :update]

    # Phase 4
    resources :webhooks, only: [:index, :create, :update, :destroy] do
      member do
        get :deliveries
      end
      collection do
        post "deliveries/:delivery_id/retry", action: :retry_delivery, as: :retry_delivery
      end
    end
    resources :automations, only: [:index, :create, :update, :destroy]

    # Phase 5
    get "settings/two_factor", to: "settings#two_factor", as: :settings_two_factor
    post "settings/two_factor/setup", to: "settings#two_factor_setup", as: :settings_two_factor_setup
    post "settings/two_factor/confirm", to: "settings#two_factor_confirm", as: :settings_two_factor_confirm
    post "settings/two_factor/disable", to: "settings#two_factor_disable", as: :settings_two_factor_disable
    get "settings/sso", to: "settings#sso", as: :settings_sso
    post "settings/sso", to: "settings#update_sso", as: :settings_update_sso
    get "settings/csat", to: "settings#csat", as: :settings_csat
    post "settings/csat", to: "settings#update_csat", as: :settings_update_csat
    resources :custom_objects, only: [:index, :create, :update, :destroy] do
      member do
        get :records
        post :store_record
        put "records/:record_id", action: :update_record, as: :update_record
        delete "records/:record_id", action: :destroy_record, as: :destroy_record
      end
    end
  end

  # Guest routes (no authentication required)
  namespace :guest do
    get "create", to: "tickets#create"
    post "/", to: "tickets#store", as: :tickets
    get ":token", to: "tickets#show", as: :ticket
    post ":token/reply", to: "tickets#reply", as: :ticket_reply
    post ":token/rate", to: "tickets#rate", as: :ticket_rate
  end

  # Inbound email webhook (no authentication -- verified by adapter)
  post "inbound/:adapter", to: "inbound#webhook", as: :inbound_webhook

  # Root redirect to customer tickets
  root to: "customer/tickets#index"
end
