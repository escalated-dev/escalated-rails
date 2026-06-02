# frozen_string_literal: true

namespace :escalated do
  namespace :newsletters do
    unless Rake::Task.task_defined?('escalated:newsletters:dispatch')
      desc 'Plan scheduled newsletters whose time has come and dispatch a batch of pending deliveries.'
      task dispatch: :environment do
        unless Escalated.configuration.enable_newsletters?
          puts 'Newsletter feature disabled - skipping.'
          next
        end

        Escalated::Newsletter.due.find_each do |newsletter|
          puts "Planning newsletter ##{newsletter.id}"
          Escalated::Newsletter::Planner.new.plan(newsletter)
        end

        puts 'Dispatching batch...'
        Escalated::Newsletter::Dispatcher.new.dispatch_batch
        puts 'Done.'
      end
    end
  end
end
