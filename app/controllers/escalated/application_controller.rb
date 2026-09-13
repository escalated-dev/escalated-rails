# frozen_string_literal: true

module Escalated
  class ApplicationController < ActionController::Base
    include Pundit::Authorization
    include Escalated::Renderable

    protect_from_forgery with: :exception

    before_action :apply_middleware
    before_action :set_inertia_shared_data, if: -> { Escalated.configuration.ui_enabled? }

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

    private

    def apply_middleware
      Escalated.configuration.middleware.each do |middleware_method|
        send(middleware_method) if respond_to?(middleware_method, true)
      end
    end

    def set_inertia_shared_data
      user_data = current_user_data
      shared = {
        auth: {
          user: user_data
        },
        current_user: user_data,
        escalated: {
          route_prefix: Escalated.configuration.route_prefix,
          allow_customer_close: Escalated.configuration.allow_customer_close,
          max_attachments: Escalated.configuration.max_attachments,
          max_attachment_size_kb: Escalated.configuration.max_attachment_size_kb,
          guest_tickets_enabled: Escalated::EscalatedSetting.guest_tickets_enabled?,
          show_powered_by: Escalated::EscalatedSetting.get_bool('show_powered_by', default: true),
          plugins_enabled: Escalated.configuration.plugins_enabled?,
          knowledge_base_enabled: Escalated::EscalatedSetting.knowledge_base_enabled?,
          knowledge_base_public: Escalated::EscalatedSetting.knowledge_base_public?,
          knowledge_base_feedback_enabled: Escalated::EscalatedSetting.knowledge_base_feedback_enabled?,
          features: {
            newsletters: Escalated.configuration.enable_newsletters?
          },
          permissions: user_permission_slugs(escalated_current_user&.id)
        },
        flash: {
          success: flash[:success],
          error: flash[:error],
          notice: flash[:notice],
          alert: flash[:alert],
          # Admin/Settings/TwoFactor reads its enrolment steps from here.
          two_factor_setup: flash[:two_factor_setup],
          two_factor_confirmed: flash[:two_factor_confirmed]
        }
      }

      # Share plugin UI data when plugin system is enabled
      shared[:plugin_ui] = Escalated.plugin_ui.to_shared_data if Escalated.configuration.plugins_enabled?

      inertia_share(**shared)
    end

    def user_permission_slugs(user_id)
      return [] if user_id.blank?

      Escalated::Permission.joins(roles: :users)
                           .where(escalated_role_users: { user_id: user_id })
                           .distinct
                           .pluck(:slug)
    end

    def current_user_data
      user = escalated_current_user
      return nil unless user

      {
        id: user.id,
        name: user.respond_to?(:name) ? user.name : user.email,
        email: user.email,
        is_agent: user.respond_to?(:escalated_agent?) ? user.escalated_agent? : false,
        is_admin: user.respond_to?(:escalated_admin?) ? user.escalated_admin? : false
      }
    end

    # The host's signed-in user, or nil when the host defines no current_user
    # because it authenticates some other way. Devise's helper is public; a
    # host's own may be private, so both count.
    def escalated_current_user
      return nil unless respond_to?(:current_user, true)

      current_user
    end

    def require_agent!
      return if current_user_data&.dig(:is_agent) || current_user_data&.dig(:is_admin)

      redirect_to main_app.root_path, alert: I18n.t('escalated.middleware.not_agent')
    end

    def require_admin!
      return if current_user_data&.dig(:is_admin)

      redirect_to main_app.root_path, alert: I18n.t('escalated.middleware.not_admin')
    end

    def user_not_authorized
      render_page 'Escalated/Error', {
        status: 403,
        message: I18n.t('escalated.middleware.not_authorized')
      }, status: :forbidden
    end

    def not_found
      render_page 'Escalated/Error', {
        status: 404,
        message: I18n.t('escalated.middleware.not_found')
      }, status: :not_found
    end

    def unprocessable_entity(exception)
      redirect_back_or_to(
        main_app.root_path, alert: exception.record.errors.full_messages.join(', ')
      )
    end

    def paginate(scope, per_page: 25)
      page = (params[:page] || 1).to_i
      per = (params[:per_page] || per_page).to_i

      total = scope.count
      records = scope.offset((page - 1) * per).limit(per)

      {
        data: records,
        meta: {
          current_page: page,
          per_page: per,
          total: total,
          total_pages: (total.to_f / per).ceil
        }
      }
    end

    # The same page of records, shaped the way the frontend list components read
    # it.
    #
    # They were written against a paginator that carries its own links -- they
    # iterate `records.links` for { url, label, active } and gate the control on
    # `records.last_page`. Handed our `{ data:, meta: }` instead, they render
    # the rows and no way to reach page two, and `meta` goes unread. So the page
    # payload is built here rather than at each call site.
    def paginated_page(result, rows)
      meta = result[:meta]

      {
        data: rows,
        current_page: meta[:current_page],
        last_page: meta[:total_pages],
        per_page: meta[:per_page],
        total: meta[:total],
        links: pagination_links(meta[:current_page], meta[:total_pages])
      }
    end

    # Previous / page numbers / Next, with a nil url on the ones that lead
    # nowhere -- the component styles those as inert rather than hiding them.
    def pagination_links(current, last)
      return [] if last.to_i < 2

      page_url = ->(n) { url_for(request.query_parameters.merge(page: n, only_path: true)) }

      links = [{ url: current > 1 ? page_url.call(current - 1) : nil, label: '&laquo; Previous', active: false }]

      (1..last).each do |n|
        links << { url: page_url.call(n), label: n.to_s, active: n == current }
      end

      links << { url: current < last ? page_url.call(current + 1) : nil, label: 'Next &raquo;', active: false }
      links
    end
  end
end
