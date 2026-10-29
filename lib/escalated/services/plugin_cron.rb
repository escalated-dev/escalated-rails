# frozen_string_literal: true

module Escalated
  module Services
    # Five-field cron expressions (`minute hour day-of-month month
    # day-of-week`), as the plugin SDK's `cron` keys are written, evaluated in
    # UTC. Supports `*`, numbers, `a-b` ranges, `/step`, comma lists, month
    # and weekday names, 7 as Sunday, and the `@hourly`-style shorthands. When
    # both day fields are restricted, either one matching is enough, as cron
    # does.
    module PluginCron
      SHORTHANDS = {
        '@yearly' => '0 0 1 1 *', '@annually' => '0 0 1 1 *', '@monthly' => '0 0 1 * *',
        '@weekly' => '0 0 * * 0', '@daily' => '0 0 * * *', '@midnight' => '0 0 * * *',
        '@hourly' => '0 * * * *'
      }.freeze

      MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
      DAYS = %w[sun mon tue wed thu fri sat].freeze

      # [min, max, names, offset of names[0]]
      FIELDS = [[0, 59, [], 0], [0, 23, [], 0], [1, 31, [], 0], [1, 12, MONTHS, 1], [0, 7, DAYS, 0]].freeze

      module_function

      # Sends `cron {plugin, schedule}` to the plugin runtime for every
      # schedule of every SDK plugin that is due in the minute of +at+ (UTC),
      # one after another, each as no user within the action timeout. An
      # unreadable schedule is logged and skipped; a failing one is logged by
      # the bridge and never stops the others. Returns how many were sent.
      def run_due(at = Time.now.utc, bridge: Escalated.plugin_bridge)
        bridge.boot unless bridge.booted?
        return 0 unless bridge.booted?

        sent = 0
        (bridge.manifests || {}).each do |name, manifest|
          Array(manifest['cronSchedules']).grep(String).each do |schedule|
            next unless due_or_skip?(name, schedule, at)

            bridge.cron(name, schedule)
            sent += 1
          end
        end
        sent
      end

      def due_or_skip?(plugin, schedule, at)
        due?(schedule, at)
      rescue ArgumentError => e
        Rails.logger.warn("[Escalated::Plugins] #{plugin} cron \"#{schedule}\" skipped: #{e.message}")
        false
      end

      # Whether +expression+ is due in the minute containing +at+ (UTC).
      #
      # @raise [ArgumentError] when the expression cannot be read
      def due?(expression, at)
        text = expression.to_s.strip
        text = SHORTHANDS.fetch(text.downcase, text)
        parts = text.split(/\s+/)
        raise invalid(expression) unless parts.size == 5

        fields = parts.each_with_index.map { |part, i| parse(part, FIELDS[i], expression) }
        values = fields.map(&:first)
        any = fields.map(&:last)
        values[4] << 0 if values[4].include?(7)

        utc = at.utc
        return false unless values[0].include?(utc.min) && values[1].include?(utc.hour) && values[3].include?(utc.month)

        dom = values[2].include?(utc.day)
        dow = values[4].include?(utc.wday)
        !any[2] && !any[4] ? dom || dow : dom && dow
      end

      def parse(text, field, expression)
        min, max = field
        values = Set.new
        any = false
        text.split(',', -1).each do |part|
          pieces = part.split('/', -1)
          raise invalid(expression) if pieces.size > 2

          step = pieces.size == 2 ? number(pieces[1], 1, 1_000_000, expression) : 1
          range = pieces[0]
          if range == '*'
            from = min
            to = max
            any = pieces.size == 1
          elsif range.include?('-')
            ends = range.split('-', -1)
            raise invalid(expression) unless ends.size == 2

            from = value(ends[0], field, expression)
            to = value(ends[1], field, expression)
            raise invalid(expression) if from > to
          else
            from = value(range, field, expression)
            to = pieces.size == 2 ? max : from
          end
          from.step(to, step) { |n| values << n }
        end
        [values, any]
      end

      def value(token, field, expression)
        index = field[2].index(token.downcase)
        return index + field[3] if index

        number(token, field[0], field[1], expression)
      end

      def number(token, min, max, expression)
        raise invalid(expression) unless token.match?(/\A\d{1,9}\z/)

        n = token.to_i
        raise invalid(expression) if n < min || n > max

        n
      end

      def invalid(expression)
        ArgumentError.new("Invalid cron expression \"#{expression}\".")
      end
    end
  end
end
