# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# domain-model/plugin-contract.md (Cron): once a minute the host sends
# `cron {plugin, schedule}` for each due schedule of each SDK plugin.
RSpec.describe 'escalated:plugins:cron' do # rubocop:disable RSpec/DescribeClass
  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    example.run
  ensure
    Rake.application = original
    ENV.delete('AT')
  end

  let(:sent) { [] }
  let(:bridge) do
    instance_double(Escalated::Bridge::PluginBridge, booted?: true, manifests: {
                      '@acme/plugin-crm' => { 'cronSchedules' => ['* * * * *', '0 9 * * *', 'not a schedule'] },
                      '@acme/plugin-quiet' => { 'cronSchedules' => ['30 2 * * *'] },
                      '@acme/plugin-none' => {}
                    })
  end

  before do
    allow(bridge).to receive(:cron) { |plugin, schedule| sent << [plugin, schedule] }
    allow(Escalated).to receive(:plugin_bridge).and_return(bridge)
    activate_sdk_plugins('@acme/plugin-crm', '@acme/plugin-quiet', '@acme/plugin-none')
  end

  def run_task(at)
    ENV['AT'] = at
    task = Rake::Task['escalated:plugins:cron']
    task.reenable
    expect { task.invoke }.to output(/plugin cron schedule/).to_stdout
  end

  it 'sends each due schedule once and skips the undue and the unreadable' do
    run_task('2026-10-29T09:00:20Z')
    expect(sent).to contain_exactly(['@acme/plugin-crm', '* * * * *'], ['@acme/plugin-crm', '0 9 * * *'])

    run_task('2026-10-29T09:01:00Z')
    expect(sent.size).to eq(3)
    expect(sent.last).to eq(['@acme/plugin-crm', '* * * * *'])
  end

  it 'keeps going when one schedule fails' do
    allow(bridge).to receive(:cron).and_return(false)
    run_task('2026-10-29T09:00:00Z')
    expect(bridge).to have_received(:cron).twice
  end

  it 'boots the bridge first and sends nothing when it cannot' do
    idle = instance_double(Escalated::Bridge::PluginBridge, booted?: false, manifests: {}, boot: nil)
    allow(Escalated).to receive(:plugin_bridge).and_return(idle)
    allow(idle).to receive(:cron)
    run_task('2026-10-29T09:00:00Z')
    expect(idle).to have_received(:boot)
    expect(idle).not_to have_received(:cron)
  end
end
