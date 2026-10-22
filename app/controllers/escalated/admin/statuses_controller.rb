# frozen_string_literal: true

module Escalated
  module Admin
    class StatusesController < Escalated::ApplicationController
      include Escalated::InertiaForms

      FIELDS = %i[label category color description position is_default].freeze

      before_action :require_admin!
      before_action :set_status, only: %i[edit update destroy]

      def index
        statuses = Escalated::TicketStatus.ordered

        render_page 'Escalated/Admin/Statuses/Index', {
          statuses: statuses.map { |s| status_json(s) },
          categories: Escalated::TicketStatus::CATEGORIES
        }
      end

      def new
        render_page 'Escalated/Admin/Statuses/Form', {
          status: nil,
          categories: Escalated::TicketStatus::CATEGORIES
        }
      end

      def edit
        render_page 'Escalated/Admin/Statuses/Form', {
          status: status_json(@status),
          categories: Escalated::TicketStatus::CATEGORIES
        }
      end

      def create
        attributes = status_params
        errors = validate(attributes)
        return redirect_back_with_form_errors(errors, escalated.new_admin_status_path) if errors.any?

        status = Escalated::TicketStatus.new(attributes)
        Escalated::TicketStatus.transaction do
          clear_other_defaults(status) if status.is_default
          status.save!
        end

        redirect_to escalated.admin_statuses_path, notice: I18n.t('escalated.admin.status.created')
      rescue ActiveRecord::RecordInvalid
        redirect_back_with_form_errors(record_errors(status), escalated.new_admin_status_path)
      end

      def update
        attributes = status_params
        errors = validate(attributes)
        return redirect_back_with_form_errors(errors, escalated.edit_admin_status_path(@status)) if errors.any?

        Escalated::TicketStatus.transaction do
          @status.assign_attributes(attributes)
          clear_other_defaults(@status) if @status.is_default
          @status.save!
        end

        redirect_to escalated.admin_statuses_path, notice: I18n.t('escalated.admin.status.updated')
      rescue ActiveRecord::RecordInvalid
        redirect_back_with_form_errors(record_errors(@status), escalated.edit_admin_status_path(@status))
      end

      def destroy
        @status.destroy!
        redirect_to escalated.admin_statuses_path, notice: I18n.t('escalated.admin.status.deleted')
      end

      private

      def set_status
        @status = Escalated::TicketStatus.find(params[:id])
      end

      def status_params
        attributes = form_source(:ticket_status, FIELDS).permit(*FIELDS).to_h.symbolize_keys
        attributes[:is_default] = boolean_param(attributes[:is_default]) if attributes.key?(:is_default)
        attributes
      end

      # The rules escalated-laravel's StatusController validates with.
      def validate(attributes)
        errors = {}
        errors['label'] = 'The label field is required.' if attributes[:label].blank?
        unless Escalated::TicketStatus::CATEGORIES.include?(attributes[:category].to_s)
          errors['category'] = "The category must be one of: #{Escalated::TicketStatus::CATEGORIES.join(', ')}."
        end
        errors['color'] = 'The color field is required.' if attributes.key?(:color) && attributes[:color].blank?
        errors
      end

      def clear_other_defaults(status)
        Escalated::TicketStatus.where(category: status.category, is_default: true)
                               .where.not(id: status.id)
                               .update_all(is_default: false)
      end

      def status_json(status)
        {
          id: status.id,
          label: status.label,
          slug: status.slug,
          category: status.category,
          color: status.color,
          description: status.description,
          position: status.position,
          is_default: status.is_default,
          created_at: status.created_at&.iso8601,
          updated_at: status.updated_at&.iso8601
        }
      end
    end
  end
end
