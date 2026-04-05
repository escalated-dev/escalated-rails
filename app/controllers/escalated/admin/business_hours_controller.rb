module Escalated
  module Admin
    class BusinessHoursController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_schedule, only: [:update, :destroy]

      def index
        schedules = Escalated::BusinessSchedule.includes(:holidays).ordered

        render_page "Escalated/Admin/BusinessHours/Index", {
          schedules: schedules.map { |s| schedule_json(s) }
        }
      end

      def create
        schedule = Escalated::BusinessSchedule.new(schedule_params)

        if schedule.save
          sync_holidays(schedule, holidays_param)
          redirect_to escalated.admin_business_hours_index_path, notice: I18n.t('escalated.admin.business_hours.created')
        else
          redirect_back fallback_location: escalated.admin_business_hours_index_path,
                        alert: schedule.errors.full_messages.join(", ")
        end
      end

      def update
        if @schedule.update(schedule_params)
          sync_holidays(@schedule, holidays_param)
          redirect_to escalated.admin_business_hours_index_path, notice: I18n.t('escalated.admin.business_hours.updated')
        else
          redirect_back fallback_location: escalated.admin_business_hours_index_path,
                        alert: @schedule.errors.full_messages.join(", ")
        end
      end

      def destroy
        @schedule.destroy!
        redirect_to escalated.admin_business_hours_index_path, notice: I18n.t('escalated.admin.business_hours.deleted')
      end

      private

      def set_schedule
        @schedule = Escalated::BusinessSchedule.find(params[:id])
      end

      def schedule_params
        params.require(:business_schedule).permit(:name, :timezone, schedule: {})
      end

      def holidays_param
        params[:holidays].is_a?(Array) ? params[:holidays] : []
      end

      def sync_holidays(schedule, holidays_data)
        schedule.holidays.destroy_all

        holidays_data.each do |holiday|
          schedule.holidays.create!(
            name: holiday[:name] || holiday["name"],
            date: holiday[:date] || holiday["date"]
          )
        end
      end

      def schedule_json(schedule)
        {
          id: schedule.id,
          name: schedule.name,
          timezone: schedule.timezone,
          schedule: schedule.schedule,
          holidays: schedule.holidays.map { |h| holiday_json(h) },
          created_at: schedule.created_at&.iso8601,
          updated_at: schedule.updated_at&.iso8601
        }
      end

      def holiday_json(holiday)
        {
          id: holiday.id,
          name: holiday.name,
          date: holiday.date&.iso8601
        }
      end
    end
  end
end
