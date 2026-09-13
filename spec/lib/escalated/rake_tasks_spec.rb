# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# A host runs `rails escalated:...` through Rails.application.load_tasks, which
# already loads every lib/tasks/**/*.rake file of every engine. Anything that
# loads one of those files a second time appends a second copy of each task's
# body, and Rake runs both: the import runs twice and then aborts, the chat
# cleanup sweeps twice.
RSpec.describe 'Escalated rake tasks' do # rubocop:disable RSpec/DescribeClass
  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    example.run
  ensure
    Rake.application = original
  end

  it 'defines each escalated task body once', :aggregate_failures do
    names = Rake.application.tasks.map(&:name).grep(/\Aescalated:/)

    expect(names).to include('escalated:import:run', 'escalated:close_idle_chats',
                             'escalated:cleanup_abandoned_chats', 'escalated:newsletters:dispatch')

    names.each do |name|
      count = Rake::Task[name].actions.size
      expect(count).to eq(1), "#{name} has #{count} actions"
    end
  end
end
