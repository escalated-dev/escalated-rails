# frozen_string_literal: true

Escalated::Engine.routes.draw do
  # ── Core routes (always registered) ──────────────────────────────────
  # These work without the Inertia UI: inbound email webhooks and
  # SDK plugin endpoints/webhooks (registered dynamically at boot by
  # Escalated::Bridge::RouteRegistrar).

  # Inbound email webhook (no authentication -- verified by adapter)
  post 'inbound/:adapter', to: 'inbound#webhook', as: :inbound_webhook

  # Signed ticket webhooks from cloud.escalated.dev (Synced mode). Verified by
  # X-Escalated-Signature, not by a session, so no host auth filters apply.
  post 'cloud/webhook', to: 'cloud_webhook#receive', as: :cloud_webhook

  # Attachment downloads: a signed, expiring link plus a ticket-access check
  # (Escalated::AttachmentAccess). Core, so API-only hosts can download too.
  get 'attachments/:id', to: 'attachments#show', as: :attachment_download

  # SDK plugin routes are registered dynamically at boot time by
  # Escalated::Bridge::RouteRegistrar based on each plugin's manifest.
  # They appear as:
  #   GET/POST /support/plugins/:plugin/api/:path   → plugins/endpoints#handle
  #   POST     /support/plugins/:plugin/webhooks/:path → plugins/webhooks#handle

  # ── UI routes (only when ui_enabled is true) ─────────────────────────
  # Agent, admin, customer, and guest routes depend on Inertia and the
  # configured UI renderer.  Skipped when the host app sets
  # Escalated.configuration.ui_enabled = false.

  return unless Escalated.configuration.ui_enabled?

  # Customer-facing routes
  namespace :customer do
    # The knowledge base reader (published articles only).
    get 'kb', to: 'knowledge_base#index', as: :kb
    get 'kb/:slug', to: 'knowledge_base#show', as: :kb_article
    post 'kb/:slug/feedback', to: 'knowledge_base#feedback', as: :kb_feedback

    # The controller's `create` renders the form and `store` saves it (the
    # Laravel names). `resources ... only: :create` sent POST /tickets to the
    # form action, and `get :new, action: :create` was drawn at /tickets
    # itself, ahead of index: the list was unreachable and nothing was saved.
    resources :tickets, only: %i[index show] do
      member do
        post :reply
        post :close
        post :reopen
        post :rate, to: 'satisfaction_ratings#create'
      end
      collection do
        get 'new', action: :create, as: :new
        get 'create', action: :create
        post '/', action: :store, as: :store
      end
    end
  end

  # Agent routes
  namespace :agent do
    get '/', to: 'dashboard#index', as: :dashboard
    post 'tickets/bulk', to: 'bulk_actions#create', as: :tickets_bulk
    resources :tickets, only: %i[index show update] do
      member do
        post :reply
        post :note
        post :assign
        post :status
        post :priority
        post :tags
        post :department
        post :macro, action: :apply_macro
        post 'actions/:action_key', action: :custom_action, as: :custom_action
        post :follow
        post :presence
        post 'replies/:reply_id/pin', action: :pin, as: :reply_pin
        post :subjects, to: 'ticket_subjects#create'
        delete 'subjects/:subject_id', to: 'ticket_subjects#destroy', as: :destroy_subject
      end
    end

    # Mentions
    scope 'mentions', controller: :mentions do
      get '/', action: :index, as: :mentions
      post :mark_read, as: :mentions_mark_read
      get :search_agents, as: :mentions_search_agents
    end
  end

  # Admin routes
  namespace :admin do
    post 'tickets/bulk', to: 'bulk_actions#create', as: :tickets_bulk
    resources :tickets, only: %i[index show] do
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
        post :snooze
        post :unsnooze
        post :presence
        post 'replies/:reply_id/pin', action: :pin, as: :reply_pin
        post :subjects, to: 'ticket_subjects#create'
        delete 'subjects/:subject_id', to: 'ticket_subjects#destroy', as: :destroy_subject
      end
    end
    resources :departments
    resources :sla_policies
    resources :escalation_rules
    resources :tags, only: %i[index create update destroy]
    resources :canned_responses, only: %i[index create update destroy]
    resources :macros, only: %i[index create update destroy]
    resources :api_tokens, only: %i[index create update destroy]
    resources :plugins, only: %i[index destroy] do
      member do
        post :activate
        post :deactivate
      end
      collection do
        post :upload
      end
    end
    get :reports, to: 'reports#index'
    get 'reports/dashboard', to: 'reports#dashboard', as: :reports_dashboard
    get 'reports/agents', to: 'reports#agents', as: :reports_agents
    get 'reports/sla', to: 'reports#sla', as: :reports_sla
    get 'reports/csat', to: 'reports#csat', as: :reports_csat
    get 'reports/agent/:id/detail', to: 'reports#agent_detail', as: :reports_agent_detail

    # Advanced reporting endpoints
    scope 'reports/advanced', controller: :advanced_reports do
      get :sla_trends, as: :reports_sla_trends
      get :response_times, as: :reports_response_times
      get :resolution_times, as: :reports_resolution_times
      get :agent_ranking, as: :reports_agent_ranking
      get :cohorts, as: :reports_cohorts

      # The frontend has one first-response screen and one resolution screen;
      # these five paths served what are now two. They redirect rather than
      # 404, having been in the routes long enough to be linked.
      get :frt_distribution, as: :reports_frt_distribution
      get :frt_trends, as: :reports_frt_trends
      get :frt_by_agent, as: :reports_frt_by_agent
      get :resolution_distribution, as: :reports_resolution_distribution
      get :resolution_trends, as: :reports_resolution_trends
      get :cohort, as: :reports_cohort
      get :comparison, as: :reports_comparison
      get :export, as: :reports_export
    end

    get :settings, to: 'settings#index'
    post :settings, to: 'settings#update'

    # Phase 1
    resources :statuses, only: %i[index new create edit update destroy]
    resources :business_hours, only: %i[index new create edit update destroy]
    resources :roles, only: %i[index new create edit update destroy]
    resources :audit_logs, only: [:index]

    # Users (host User model: list + grant/revoke admin/agent flags)
    get 'users', to: 'users#index', as: :users
    patch 'users/:user_id/role', to: 'users#update_role', as: :user_role

    # Phase 2
    resources :custom_fields, only: %i[index new create edit update destroy] do
      collection do
        post :reorder
      end
    end
    resources :tickets, only: [] do
      member do
        get :links, to: 'ticket_links#index'
        post :store_link, to: 'ticket_links#store'
        delete 'links/:link_id', to: 'ticket_links#destroy', as: :destroy_link
        get :merge_search, to: 'ticket_merges#search'
        post :merge, to: 'ticket_merges#merge'
        get :side_conversations, to: 'side_conversations#index'
        post :store_side_conversation, to: 'side_conversations#store'
        post 'side_conversations/:conversation_id/reply', to: 'side_conversations#reply', as: :side_conversation_reply
        post 'side_conversations/:conversation_id/close', to: 'side_conversations#close', as: :side_conversation_close
        post 'replies/:reply_id/split', action: :split, as: :split_reply
      end
    end
    resources :saved_views, only: %i[index create update destroy] do
      collection do
        post :reorder
      end
    end
    resources :articles, only: %i[index new create edit update destroy]
    resources :kb_categories, only: %i[index create update destroy]

    # Phase 3
    resources :skills, only: %i[index new create edit update destroy]
    resources :capacity, only: %i[index update]

    # Phase 4
    resources :webhooks, only: %i[index new create edit update destroy] do
      member do
        get :deliveries
      end
      collection do
        post 'deliveries/:delivery_id/retry', action: :retry_delivery, as: :retry_delivery
      end
    end
    resources :automations, only: %i[index new create edit update destroy]

    # Newsletters
    scope 'newsletters', as: :newsletters do
      get '/', to: 'newsletters#index'
      get 'new', to: 'newsletters#create', as: :new
      post '/', to: 'newsletters#store'
      post 'preview', to: 'newsletters#preview', as: :preview
      post 'test', to: 'newsletters#test', as: :test

      get 'lists', to: 'newsletter_lists#index', as: :lists
      get 'lists/new', to: 'newsletter_lists#create', as: :new_list
      post 'lists', to: 'newsletter_lists#store'
      get 'lists/:id', to: 'newsletter_lists#show', as: :list
      put 'lists/:id', to: 'newsletter_lists#update'
      delete 'lists/:id', to: 'newsletter_lists#destroy'
      post 'lists/:id/members', to: 'newsletter_lists#add_member', as: :list_members
      delete 'lists/:id/members/:contact_id', to: 'newsletter_lists#remove_member', as: :list_member
      post 'lists/:id/import', to: 'newsletter_lists#import', as: :list_import

      get 'templates', to: 'newsletter_templates#index', as: :templates
      get 'templates/new', to: 'newsletter_templates#create', as: :new_template
      post 'templates', to: 'newsletter_templates#store'
      get 'templates/:id', to: 'newsletter_templates#show', as: :template
      put 'templates/:id', to: 'newsletter_templates#update'
      delete 'templates/:id', to: 'newsletter_templates#destroy'

      get 'settings', to: 'newsletter_settings#show', as: :settings
      put 'settings', to: 'newsletter_settings#update'

      get ':id', to: 'newsletters#show', as: :show
      get ':id/edit', to: 'newsletters#edit', as: :edit
      put ':id', to: 'newsletters#update'
      delete ':id', to: 'newsletters#destroy'
    end

    # Workflow automation engine
    resources :workflows, only: %i[index show new create edit update destroy] do
      member do
        post :toggle
        get :logs
        post :dry_run
      end
      collection do
        post :reorder
      end
    end

    # Phase 5
    # Two-factor enrolment, for every staff user (ADR 2026-10-29). 404 while
    # two-factor is off. Laravel's hyphenated paths are accepted as well.
    get 'settings/two_factor', to: 'two_factor#show', as: :settings_two_factor
    post 'settings/two_factor/setup', to: 'two_factor#setup', as: :settings_two_factor_setup
    post 'settings/two_factor/confirm', to: 'two_factor#confirm', as: :settings_two_factor_confirm
    post 'settings/two_factor/disable', to: 'two_factor#disable', as: :settings_two_factor_disable
    get 'settings/two-factor', to: 'two_factor#show'
    post 'settings/two-factor/setup', to: 'two_factor#setup'
    post 'settings/two-factor/confirm', to: 'two_factor#confirm'
    post 'settings/two-factor/disable', to: 'two_factor#disable'
    get 'settings/sso', to: 'settings#sso', as: :settings_sso
    post 'settings/sso', to: 'settings#update_sso', as: :settings_update_sso
    # Settings sub-pages, at escalated-laravel's paths.
    get 'settings/csat', to: 'csat_settings#show', as: :settings_csat
    post 'settings/csat', to: 'csat_settings#update', as: :settings_update_csat
    get 'settings/data-retention', to: 'data_retention#show', as: :settings_data_retention
    post 'settings/data-retention', to: 'data_retention#update', as: :settings_update_data_retention
    get 'settings/email', to: 'email_settings#show', as: :settings_email
    post 'settings/email', to: 'email_settings#update', as: :settings_update_email
    # The page posts; Laravel registers PUT. Both are accepted.
    get 'settings/public-tickets', to: 'public_tickets_settings#show', as: :settings_public_tickets
    match 'settings/public-tickets', to: 'public_tickets_settings#update', via: %i[post put],
                                     as: :settings_update_public_tickets
    # The older underscore paths, kept for existing links.
    get 'settings/public_tickets', to: 'public_tickets_settings#show'
    put 'settings/public_tickets', to: 'public_tickets_settings#update'
    # Which database Escalated's tables live on (read-only: set in config).
    get 'settings/database', to: 'database_connection#show', as: :settings_database
    post 'settings/database/test', to: 'database_connection#check', as: :settings_database_test
    post 'settings/database', to: 'database_connection#update', as: :settings_database_update
    resources :custom_objects, only: %i[index new create edit update destroy] do
      member do
        get :records
        # The Records page posts new records here (Laravel's path); the older
        # store_record path stays for existing callers.
        post :records, action: :store_record, as: :create_record
        post :store_record
        put 'records/:record_id', action: :update_record, as: :update_record
        delete 'records/:record_id', action: :destroy_record, as: :destroy_record
      end
    end

    # Live Chat
    scope 'chat', controller: :chat do
      get '/', action: :index, as: :chat
      get :queue, as: :chat_queue
      post :update_status, as: :chat_update_status
      post ':id/accept', action: :accept, as: :chat_accept
      post ':id/end', action: :end_chat, as: :chat_end
      post ':id/transfer', action: :transfer, as: :chat_transfer
      post ':id/message', action: :message, as: :chat_message
      post ':id/typing', action: :typing, as: :chat_typing
    end

    # Import wizard, on escalated-laravel's paths (escalated.admin.import.*):
    # Index -> Connect -> Mapping -> Review -> Progress.
    scope 'import', controller: :imports, as: :import do
      get '/', action: :index, as: :index
      get 'progress/:job_id', action: :progress, as: :progress
      get 'status/:job_id', action: :status, as: :status
      post 'pause/:job_id', action: :pause, as: :pause
      post 'resume/:job_id', action: :resume, as: :resume
      post 'cancel/:job_id', action: :cancel, as: :cancel
      get ':platform/connect', action: :connect, as: :connect
      post ':platform/test-connection', action: :test_connection, as: :test_connection
      get ':platform/mapping', action: :mapping, as: :mapping
      post ':platform/review', action: :review, as: :review
      post ':platform/start', action: :launch, as: :start
    end

    # Import framework (the earlier REST surface, kept for existing callers)
    resources :imports, only: %i[index show create destroy] do
      member do
        post :start
        post :pause
        post :resume
        get  :source_maps
      end
    end
  end

  # The standalone widget bundle, loaded with a <script> tag on any site.
  if Escalated.configuration.widget_serve_script
    get 'widget/embed.js', to: 'widget_script#show', format: false, as: :widget_script
  end

  # CORS preflights for every widget route, answered by Escalated::WidgetCors.
  match 'widget/*path', to: 'widget#preflight', via: :options, format: false, as: :widget_preflight

  # Widget routes (public, no authentication required)
  scope 'widget', controller: :widget do
    get :config, action: :widget_config, as: :widget_config
    get :articles, as: :widget_articles
    get 'articles/:slug', action: :article, as: :widget_article
    post :tickets, action: :create_ticket, as: :widget_create_ticket
    # A reference with the grant as a bearer token, or a legacy guest_token.
    get 'tickets/:token', action: :lookup_ticket, as: :widget_lookup_ticket
    post :verification, action: :request_verification, as: :widget_verification
    post :lookup, action: :lookup, as: :widget_lookup
  end

  # Widget chat routes (public, rate limited)
  scope 'widget/chat', controller: :widget_chat do
    get :availability, as: :widget_chat_availability
    post :start, as: :widget_chat_start
    post ':session_id/message', action: :message, as: :widget_chat_message
    # The shared widget's paths: list and send on `messages`.
    get ':session_id/messages', action: :messages, as: :widget_chat_messages
    post ':session_id/messages', action: :message
    post ':session_id/typing', action: :typing, as: :widget_chat_typing
    post ':session_id/end', action: :end_chat, as: :widget_chat_end
    post ':session_id/rate', action: :rate, as: :widget_chat_rate
  end

  # Guest routes (no authentication required)
  namespace :guest do
    post 'verification', to: 'verifications#request_verification', as: :verification
    post 'lookup', to: 'verifications#lookup', as: :lookup
    get 'create', to: 'tickets#create'
    post '/', to: 'tickets#store', as: :tickets
    get ':token', to: 'tickets#show', as: :ticket
    post ':token/reply', to: 'tickets#reply', as: :ticket_reply
    post ':token/rate', to: 'tickets#rate', as: :ticket_rate
  end

  # The two-factor challenge after the host's login (ADR 2026-10-29); 404
  # while two-factor is off.
  get 'two-factor/challenge', to: 'two_factor_challenges#show', as: :two_factor_challenge
  post 'two-factor/challenge', to: 'two_factor_challenges#create', as: :two_factor_verify

  # Root redirect to customer tickets
  root to: 'customer/tickets#index'
end
