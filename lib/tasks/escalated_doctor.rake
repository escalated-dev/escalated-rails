# frozen_string_literal: true

namespace :escalated do
  desc "Check Escalated's setup: the user model's staff gates and the recurring jobs"
  task doctor: :environment do
    results = Escalated::SetupCheck.run
    labels = { ok: 'OK', warning: 'WARN', error: 'FAIL' }
    results.each { |result| puts "[#{labels[result[:level]]}] #{result[:message]}" }

    if results.any? { |result| result[:level] == :error }
      warn 'Escalated is not set up correctly.'
      exit 1
    end
  end
end
