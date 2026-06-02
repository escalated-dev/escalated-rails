# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'escalated:newsletters:dispatch' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('escalated:newsletters:dispatch')
  end

  before do
    Rake::Task['escalated:newsletters:dispatch'].reenable
    ActionMailer::Base.deliveries.clear
  end

  it 'exits without sending when newsletters are disabled mid-flight' do
    allow(Escalated.configuration).to receive(:enable_newsletters?).and_return(false)
    newsletter = create(:escalated_newsletter, status: 'sending', summary_sent: 0)
    create_list(:escalated_newsletter_delivery, 5, newsletter: newsletter, status: 'pending')

    expect do
      Rake::Task['escalated:newsletters:dispatch'].invoke
    end.not_to raise_error

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(newsletter.deliveries.pluck(:status)).to all(eq('pending'))
    expect(newsletter.reload.summary_sent).to eq(0)
  end
end
