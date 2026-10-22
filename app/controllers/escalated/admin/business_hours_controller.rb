# frozen_string_literal: true

module Escalated
  module Admin
    class BusinessHoursController < Escalated::ApplicationController
      include Escalated::InertiaForms

      FIELDS = %i[name timezone is_default schedule].freeze

      before_action :require_admin!
      before_action :set_schedule, only: %i[edit update destroy]

      def index
        schedules = Escalated::BusinessSchedule.includes(:holidays).order(:name)

        render_page 'Escalated/Admin/BusinessHours/Index', {
          schedules: schedules.map { |s| schedule_json(s) }
        }
      end

      def new
        render_page 'Escalated/Admin/BusinessHours/Form', { schedule: nil, timezones: timezones }
      end

      def edit
        render_page 'Escalated/Admin/BusinessHours/Form', { schedule: schedule_json(@schedule), timezones: timezones }
      end

      def create
        attributes = schedule_params
        holidays = holidays_param
        errors = validate(attributes, holidays)
        return redirect_back_with_form_errors(errors, escalated.new_admin_business_hour_path) if errors.any?

        schedule = Escalated::BusinessSchedule.new(attributes)
        Escalated::BusinessSchedule.transaction do
          clear_other_defaults(schedule) if schedule.is_default
          schedule.save!
          sync_holidays(schedule, holidays)
        end

        redirect_to escalated.admin_business_hours_path,
                    notice: I18n.t('escalated.admin.business_hours.created')
      end

      def update
        attributes = schedule_params
        holidays = holidays_param
        errors = validate(attributes, holidays)
        return redirect_back_with_form_errors(errors, escalated.edit_admin_business_hour_path(@schedule)) if errors.any?

        Escalated::BusinessSchedule.transaction do
          @schedule.assign_attributes(attributes)
          clear_other_defaults(@schedule) if @schedule.is_default
          @schedule.save!
          sync_holidays(@schedule, holidays)
        end

        redirect_to escalated.admin_business_hours_path,
                    notice: I18n.t('escalated.admin.business_hours.updated')
      end

      def destroy
        @schedule.destroy!
        redirect_to escalated.admin_business_hours_path, notice: I18n.t('escalated.admin.business_hours.deleted')
      end

      private

      def set_schedule
        @schedule = Escalated::BusinessSchedule.find(params[:id])
      end

      def schedule_params
        source = form_source(:business_schedule, FIELDS)
        attributes = source.permit(:name, :timezone, :is_default).to_h.symbolize_keys
        attributes[:is_default] = boolean_param(attributes[:is_default]) if attributes.key?(:is_default)
        schedule = source[:schedule]
        attributes[:schedule] = schedule.permit!.to_h if schedule.is_a?(ActionController::Parameters)
        attributes
      end

      # nil when the body sends no list, so an update without one keeps them.
      def holidays_param
        return nil unless params.key?(:holidays)

        Array(params[:holidays]).map do |holiday|
          holiday = holiday.respond_to?(:permit) ? holiday.permit(:name, :date, :recurring).to_h : {}
          { name: holiday['name'], date: holiday['date'], recurring: boolean_param(holiday['recurring']) }
        end
      end

      # The rules escalated-laravel's BusinessHoursController validates with.
      def validate(attributes, holidays)
        errors = {}
        errors['name'] = 'The name field is required.' if attributes[:name].blank?
        errors['timezone'] = 'The timezone must be a valid zone.' unless timezones.include?(attributes[:timezone].to_s)
        errors['schedule'] = 'The schedule field is required.' unless attributes[:schedule].is_a?(Hash)
        Array(holidays).each_with_index do |holiday, index|
          errors["holidays.#{index}.name"] = 'The holiday name is required.' if holiday[:name].blank?
          errors["holidays.#{index}.date"] = 'The holiday date must be a date.' unless valid_date?(holiday[:date])
        end
        errors
      end

      def valid_date?(value)
        Date.iso8601(value.to_s)
        true
      rescue ArgumentError
        false
      end

      def clear_other_defaults(schedule)
        Escalated::BusinessSchedule.where(is_default: true).where.not(id: schedule.id).update_all(is_default: false)
      end

      def sync_holidays(schedule, holidays)
        return if holidays.nil?

        schedule.holidays.destroy_all
        holidays.each { |holiday| schedule.holidays.create!(holiday) }
      end

      def timezones
        @timezones ||= TZInfo::Timezone.all_identifiers
      end

      def schedule_json(schedule)
        {
          id: schedule.id,
          name: schedule.name,
          timezone: schedule.timezone,
          is_default: schedule.is_default,
          schedule: schedule.schedule,
          holidays: schedule.holidays.sort_by(&:date).map { |h| holiday_json(h) },
          created_at: schedule.created_at&.iso8601,
          updated_at: schedule.updated_at&.iso8601
        }
      end

      def holiday_json(holiday)
        {
          id: holiday.id,
          name: holiday.name,
          date: holiday.date&.iso8601,
          recurring: holiday.recurring
        }
      end
    end
  end
end
