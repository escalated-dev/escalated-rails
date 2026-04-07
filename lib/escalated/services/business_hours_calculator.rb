# frozen_string_literal: true

module Escalated
  module Services
    class BusinessHoursCalculator
      def within_business_hours?(dt, schedule)
        tz = ActiveSupport::TimeZone[schedule.timezone]
        dt_local = dt.in_time_zone(tz)
        return false if holiday?(dt_local, schedule)

        day_schedule = get_day_schedule(dt_local, schedule)
        return false unless day_schedule&.dig('start') && day_schedule['end']

        time_str = dt_local.strftime('%H:%M')
        day_schedule['start'] <= time_str && time_str < day_schedule['end']
      end

      def add_business_hours(start, hours, schedule)
        tz = ActiveSupport::TimeZone[schedule.timezone]
        current = start.in_time_zone(tz)
        remaining_minutes = hours * 60
        max_iterations = 365

        while remaining_minutes.positive? && max_iterations.positive?
          max_iterations -= 1

          if holiday?(current, schedule)
            current = (current + 1.day).beginning_of_day
            next
          end

          day_schedule = get_day_schedule(current, schedule)

          unless day_schedule&.dig('start') && day_schedule['end']
            current = (current + 1.day).beginning_of_day
            next
          end

          start_parts = day_schedule['start'].split(':')
          end_parts = day_schedule['end'].split(':')
          day_start = current.change(hour: start_parts[0].to_i, min: start_parts[1].to_i)
          day_end = current.change(hour: end_parts[0].to_i, min: end_parts[1].to_i)

          current = day_start if current < day_start

          if current >= day_end
            current = (current + 1.day).beginning_of_day
            next
          end

          available_minutes = (day_end - current) / 60

          if remaining_minutes <= available_minutes
            current += remaining_minutes.minutes
            remaining_minutes = 0
          else
            remaining_minutes -= available_minutes
            current = (current + 1.day).beginning_of_day
          end
        end

        current.utc
      end

      private

      def get_day_schedule(dt_local, schedule)
        day_name = dt_local.strftime('%A').downcase
        (schedule.schedule || {})[day_name]
      end

      def holiday?(dt_local, schedule)
        schedule.holidays.each do |holiday|
          if holiday.recurring
            return true if dt_local.month == holiday.date.month && dt_local.day == holiday.date.day
          elsif dt_local.to_date == holiday.date
            return true
          end
        end

        false
      end
    end
  end
end
