# frozen_string_literal: true

module Escalated
  class WidgetController < PublicController
    include Escalated::ApiRateLimiting
    include Escalated::GuestThrottling
    include Escalated::WidgetCors
    include Escalated::WidgetDepartments
    include Escalated::GuestVerificationEndpoints

    # CSRF is skipped only for a request WidgetCors accepted from an allowed
    # embedding site: it runs as a guest with no session to protect. Every
    # other POST (same-origin, or from any other site) needs a valid token, as
    # with Laravel's WidgetCsrf. WidgetCors is prepended, so the origin is
    # known before verification runs.
    protect_from_forgery with: :exception
    skip_forgery_protection if: -> { widget_cross_origin.present? }
    before_action :enforce_rate_limit!
    before_action :ensure_widget_enabled!
    before_action :ensure_knowledge_base_available!, only: %i[articles article]
    before_action :throttle_guest_tickets!, only: :create_ticket
    after_action :set_guest_privacy_headers, only: %i[create_ticket lookup_ticket]

    # GET /support/widget/config
    #
    # Not named `config`: that is ActionController's configuration reader, so an
    # action of that name was called again from inside its own render and
    # recursed until the stack ran out.
    def widget_config
      render json: {
        enabled: widget_enabled?,
        color: Escalated::EscalatedSetting.get('widget_color', '#4F46E5'),
        position: Escalated::EscalatedSetting.get('widget_position', 'bottom-right'),
        greeting: Escalated::EscalatedSetting.get('widget_greeting', 'How can we help you?'),
        departments: Escalated::Department.active.ordered.map { |d| { id: d.id, name: d.name } },
        kb_enabled: knowledge_base_available?,
        guest_tickets_enabled: Escalated::EscalatedSetting.guest_tickets_enabled?,
        # Tickets and chats keep host parameters sent as `metadata`.
        accepts_metadata: true,
        # Tickets, chats and status lookups need an emailed code
        # (POST verification, then the proof with the request).
        guest_verification_required: true,
        status_lookup_enabled: true
      }
    end

    # GET /support/widget/articles?q=search_term
    def articles
      scope = Escalated::Article.published.recent

      scope = scope.search(params[:q]) if params[:q].present?

      articles = scope.limit(10)

      render json: {
        articles: articles.map do |a|
          {
            id: a.id,
            title: a.title,
            slug: a.slug,
            excerpt: a.body&.truncate(200)
          }
        end
      }
    end

    # GET /support/widget/articles/:slug
    def article
      article = Escalated::Article.published.find_by!(slug: params[:slug])
      article.increment_views!

      render json: {
        id: article.id,
        title: article.title,
        slug: article.slug,
        body: article.body,
        category: article.category ? { id: article.category.id, name: article.category.name } : nil
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Article not found' }, status: :not_found
    end

    # POST /support/widget/tickets
    #
    # Needs a ticket-purpose proof for the email (POST verification first).
    # Answers with an expiring grant for the status lookup.
    def create_ticket
      return render json: { message: 'Guest tickets are disabled.' }, status: :forbidden unless guest_tickets_allowed?
      return render_invalid_metadata if Escalated::Support::WidgetMetadata.invalid?(params[:metadata])
      return render_unknown_department unless widget_department_valid?(params[:department_id])

      host_metadata = Escalated::Support::WidgetMetadata.sanitize(params[:metadata], origin: widget_cross_origin)
      attrs = {
        subject: params[:subject],
        description: params[:description],
        priority: Escalated.configuration.default_priority,
        department_id: params[:department_id].presence,
        metadata: (host_metadata || {}).merge('source' => 'widget')
      }

      # Apply the admin-configured guest policy. Persisted by
      # Admin::SettingsController under three keys in
      # escalated_escalated_settings. Modes:
      #   - unassigned (default): guest_name / guest_email set,
      #     requester_type / requester_id left nil.
      #   - guest_user: route to a pre-created host-app user via
      #     requester_type + requester_id. Still records the guest
      #     email so agents see who submitted.
      #   - prompt_signup: same ticket-create path as unassigned;
      #     signup invite is a separate follow-up.
      mode = Escalated::EscalatedSetting.get('guest_policy_mode').presence || 'unassigned'

      # Misconfigured guest_user (zero / missing id) falls through to
      # unassigned behavior so bad admin input doesn't 500 the public
      # endpoint.
      if mode == 'guest_user'
        guest_user_id = Escalated::EscalatedSetting.get('guest_policy_user_id')
        if guest_user_id.present?
          attrs[:requester_type] = Escalated.configuration.user_class
          attrs[:requester_id] = guest_user_id
        end
      end
      email = Escalated::Services::GuestEmailVerification.normalize(params[:email])
      attrs[:guest_name] = params[:name]
      attrs[:guest_email] = email

      ticket, token = with_guest_proof('ticket', email) do
        created = Escalated::Services::TicketService.create_local(attrs, announce: false)
        [created, Escalated::GuestAccess.issue(created, email: email)]
      end
      return if performed?

      Escalated::Services::TicketService.announce_created(ticket)
      render json: {
        message: 'Ticket created.',
        reference: ticket.reference,
        guest_access_token: token,
        expires_at: ticket.guest_access_expires_at.iso8601
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: {
        error: e.record.errors.full_messages.join(', '),
        message: e.record.errors.full_messages.join(', '),
        errors: e.record.errors.to_hash(true)
      }, status: :unprocessable_content
    end

    # GET /support/widget/tickets/:reference with `Authorization: Bearer
    # <grant>`, the grant from create or lookup. An email query parameter
    # never authorizes it. Without a bearer token the path segment is read as
    # a legacy guest_token while those are accepted.
    def lookup_ticket
      ticket = widget_ticket
      return render json: { error: 'Ticket not found', message: 'Ticket not found' }, status: :not_found unless ticket

      render json: {
        reference: ticket.reference,
        subject: ticket.subject,
        status: ticket.status,
        status_label: ticket.status.to_s.humanize,
        created_at: ticket.created_at&.iso8601,
        department: ticket.department&.name,
        replies: ticket.replies.public_replies.chronological.includes(:author).last(20).map do |r|
          {
            body: r.body,
            author: r.author ? display_name(r.author) : (ticket.guest_name.presence || 'Guest'),
            is_agent: r.author.respond_to?(:escalated_agent?) ? r.author.escalated_agent? : false,
            created_at: r.created_at&.iso8601
          }
        end
      }
    end

    private

    def widget_ticket
      bearer = request.headers['Authorization'].to_s[/\ABearer (.+)\z/, 1]
      return Escalated::GuestAccess.legacy_ticket(params[:token]) if bearer.nil?

      ticket = Escalated::GuestAccess.resolve(bearer)
      ticket if ticket && ActiveSupport::SecurityUtils.secure_compare(ticket.reference, params[:token].to_s)
    end

    def display_name(user)
      user.respond_to?(:name) && user.name.present? ? user.name : 'Support'
    end

    def widget_enabled?
      Escalated::EscalatedSetting.get_bool('widget_enabled', default: false)
    end

    def ensure_widget_enabled!
      return if widget_enabled?

      render json: { enabled: false, error: 'Widget is disabled', message: 'Widget is disabled' }, status: :forbidden
    end

    # A widget visitor is always a guest (WidgetCors drops the host user for
    # cross-origin requests), so a private knowledge base is only offered to
    # a signed-in, same-origin visitor.
    def knowledge_base_available?
      Escalated::EscalatedSetting.knowledge_base_enabled? &&
        (Escalated::EscalatedSetting.knowledge_base_public? || escalated_current_user.present?)
    end

    def ensure_knowledge_base_available!
      unless Escalated::EscalatedSetting.knowledge_base_enabled?
        return render json: { error: 'Not found', message: 'Not found' }, status: :not_found
      end
      return if Escalated::EscalatedSetting.knowledge_base_public? || escalated_current_user.present?

      render json: { error: 'Forbidden', message: 'Forbidden' }, status: :forbidden
    end

    def render_invalid_metadata
      render json: { error: 'metadata must be an object with at most 50 keys' }, status: :unprocessable_content
    end

    def rate_limit_key
      "widget:ip:#{request.remote_ip}"
    end

    def guest_throttle_json?
      true
    end
  end
end
