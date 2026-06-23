# frozen_string_literal: true

require 'securerandom'

module Escalated
  module Admin
    class NewslettersController < Escalated::ApplicationController
      include Escalated::NewsletterAccess

      before_action :require_admin!
      before_action :ensure_newsletters_enabled!
      before_action -> { require_newsletter_permission!('newsletters.manage') }
      before_action :set_newsletter, only: %i[show edit update destroy]
      before_action :require_newsletter_send_permission!, only: :test

      def index
        tab = params[:tab].presence || 'drafts'
        statuses = case tab
                   when 'scheduled' then %w[scheduled sending paused]
                   when 'sent' then %w[sent failed]
                   else %w[draft]
                   end
        scope = Escalated::Newsletter.includes(:target_list).where(status: statuses).order(created_at: :desc)
        result = paginate(scope, per_page: 50)

        render_page 'Escalated/Admin/Newsletters/Index', {
          newsletters: result[:data],
          meta: result[:meta],
          tab: tab
        }
      end

      def show
        tab = params[:tab].presence || 'overview'
        deliveries = @newsletter.deliveries
                                .includes(:contact)
                                .where(is_test: false)
        deliveries = deliveries.where(status: params[:status]) if params[:status].present?
        result = paginate(deliveries.order(id: :desc), per_page: 100)

        render_page 'Escalated/Admin/Newsletters/Show', {
          newsletter: @newsletter.tap { |n| n.association(:target_list).load_target },
          deliveries: result[:data],
          meta: result[:meta],
          topClicks: [],
          tab: tab
        }
      end

      def edit
        unless %w[draft scheduled].include?(@newsletter.status)
          return render plain: 'Only drafts and scheduled newsletters can be edited', status: :unprocessable_content
        end

        render_page 'Escalated/Admin/Newsletters/Edit', compose_props.merge(newsletter: @newsletter)
      end

      def create
        render_page 'Escalated/Admin/Newsletters/Compose', compose_props
      end

      def store
        data = newsletter_params
        return unless data
        return unless authorize_send_status!(data)

        newsletter = Escalated::Newsletter.create!(data.merge(created_by: escalated_current_user&.id))
        Escalated::Newsletter::Planner.new.plan(newsletter) if data[:status] == 'sending'

        redirect_to admin_newsletters_show_path(newsletter)
      end

      def preview
        data = preview_params
        return unless data

        newsletter = Escalated::Newsletter.new(data.merge(
                                                 subject: data[:subject].presence || '',
                                                 theme: data[:theme].presence || 'default',
                                                 from_email: data[:from_email].presence || 'preview@example.test'
                                               ))
        newsletter.id = 0
        contact = Escalated::Contact.new(email: 'preview@example.test', name: 'Preview User')
        contact.id = 0
        delivery = Escalated::NewsletterDelivery.new(
          newsletter_id: 0,
          contact_id: 0,
          email_at_send: contact.email,
          tracking_token: 'preview',
          status: 'pending'
        )
        delivery.association(:newsletter).target = newsletter
        delivery.association(:contact).target = contact

        render json: { html: Escalated::Newsletter::Renderer.new.render(delivery) }
      end

      def test
        data = newsletter_params
        return unless data

        user = escalated_current_user
        newsletter = Escalated::Newsletter.new(data)
        newsletter.id = 0
        contact = Escalated::Contact.new(email: user.email, name: user.respond_to?(:name) ? user.name : 'Tester')
        contact.id = user.id
        delivery = Escalated::NewsletterDelivery.new(
          newsletter_id: 0,
          contact_id: contact.id,
          email_at_send: contact.email,
          tracking_token: SecureRandom.alphanumeric(40),
          status: 'pending',
          is_test: true
        )
        delivery.association(:newsletter).target = newsletter
        delivery.association(:contact).target = contact

        html = Escalated::Newsletter::Renderer.new.render(delivery)
        ActionMailer::Base.mail(
          to: user.email,
          from: formatted_from(data),
          reply_to: data[:reply_to].presence,
          subject: "[TEST] #{data[:subject]}",
          body: html,
          content_type: 'text/html'
        ).deliver

        render json: { ok: true }
      end

      def update
        data = newsletter_params
        return unless data
        return unless authorize_send_status!(data)

        @newsletter.update!(data)
        Escalated::Newsletter::Planner.new.plan(@newsletter) if data[:status] == 'sending'

        redirect_to admin_newsletters_show_path(@newsletter)
      end

      def destroy
        unless @newsletter.status == 'draft'
          return render plain: 'Only drafts can be deleted', status: :unprocessable_content
        end

        @newsletter.destroy!
        redirect_to admin_newsletters_path
      end

      private

      def set_newsletter
        @newsletter = Escalated::Newsletter.find(params[:id])
      end

      def authorize_send_status!(data)
        return true unless %w[scheduled sending].include?(data[:status].to_s)

        require_newsletter_send_permission!
        return false if performed?

        if mail_configured?
          true
        else
          redirect_back_or_to(admin_newsletters_path, alert: 'Outbound mail is not configured.')
          false
        end
      end

      def newsletter_params
        data = params.permit(:subject, :from_email, :from_name, :reply_to, :target_list_id, :template_id,
                             :theme, :body_markdown, :status, :scheduled_at).to_h.symbolize_keys
        validate_newsletter_params(data)
      end

      def preview_params
        data = params.permit(:subject, :body_markdown, :theme, :target_list_id, :from_email).to_h.symbolize_keys
        errors = []
        errors << 'subject is too long' if data[:subject].present? && data[:subject].length > 998
        errors << 'from_email is invalid' if data[:from_email].present? && !valid_email?(data[:from_email])
        return data if errors.empty?

        render json: { errors: errors }, status: :unprocessable_content
        nil
      end

      def validate_newsletter_params(data)
        errors = []
        errors << 'subject is required' if data[:subject].blank?
        errors << 'subject is too long' if data[:subject].to_s.length > 998
        errors << 'from_email is required' if data[:from_email].blank?
        errors << 'from_email is invalid' if data[:from_email].present? && !valid_email?(data[:from_email])
        errors << 'from_email is too long' if data[:from_email].to_s.length > 320
        errors << 'from_name is too long' if data[:from_name].to_s.length > 255
        errors << 'reply_to is invalid' if data[:reply_to].present? && !valid_email?(data[:reply_to])
        errors << 'reply_to is too long' if data[:reply_to].to_s.length > 320
        errors << 'target_list_id is required' if data[:target_list_id].blank?
        unless data[:target_list_id].blank? || Escalated::NewsletterList.exists?(data[:target_list_id])
          errors << 'target_list_id does not exist'
        end
        unless data[:template_id].blank? || Escalated::NewsletterTemplate.exists?(data[:template_id])
          errors << 'template_id does not exist'
        end
        errors << 'theme is too long' if data[:theme].to_s.length > 64
        status = data[:status].presence || 'draft'
        errors << 'status is invalid' unless %w[draft scheduled sending].include?(status)
        if data[:scheduled_at].present?
          begin
            scheduled_at = Time.zone.parse(data[:scheduled_at].to_s)
            errors << 'scheduled_at must be after now' if scheduled_at <= Time.current
            data[:scheduled_at] = scheduled_at
          rescue ArgumentError
            errors << 'scheduled_at is invalid'
          end
        end
        return validation_failed(errors) if errors.any?

        data[:status] = status
        data[:target_list_id] = data[:target_list_id].to_i
        data[:template_id] = data[:template_id].presence&.to_i
        data
      end

      def validation_failed(errors)
        render plain: errors.join(', '), status: :unprocessable_content
        nil
      end

      def compose_props
        {
          lists: Escalated::NewsletterList
                 .left_joins(:members)
                 .select("#{Escalated::NewsletterList.table_name}.id, #{Escalated::NewsletterList.table_name}.name, COUNT(#{Escalated::NewsletterListMember.table_name}.id) AS member_count") # rubocop:disable Layout/LineLength
                 .group("#{Escalated::NewsletterList.table_name}.id", "#{Escalated::NewsletterList.table_name}.name"),
          templates: Escalated::NewsletterTemplate.select(:id, :name),
          themes: discover_themes,
          mailConfigured: mail_configured?,
          canSend: true,
          defaultFromEmail: Escalated.configuration.newsletter_default_from,
          defaultReplyTo: Escalated.configuration.newsletter_default_reply_to,
          defaultTheme: Escalated.configuration.newsletter_default_theme
        }
      end

      def discover_themes
        roots = [
          Escalated.configuration.newsletter_themes_dir,
          File.expand_path('../../../views/escalated/newsletter_themes', __dir__)
        ].compact
        themes = roots.flat_map do |root|
          next [] unless File.directory?(root)

          Dir[File.join(root, '*.html.erb')].map { |path| File.basename(path, '.html.erb') }
        end.uniq
        themes.presence || %w[default branded]
      end

      def mail_configured?
        ActionMailer::Base.delivery_method.present? && ActionMailer::Base.delivery_method != :test
      end

      def valid_email?(email)
        email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
      end

      def formatted_from(data)
        return data[:from_email] if data[:from_name].blank?

        %("#{data[:from_name]}" <#{data[:from_email]}>)
      end
    end
  end
end
