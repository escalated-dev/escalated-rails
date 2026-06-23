# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Newsletter::Dispatcher do
  subject(:dispatcher) { described_class.new(renderer: renderer) }

  let(:renderer) { instance_double(Escalated::Newsletter::Renderer, render: '<p>Hello</p>', unsubscribe_url: 'https://app.test/u') }
  let(:newsletter) { create(:escalated_newsletter, status: 'sending') }

  before do
    Rails.cache.clear
    described_class.rate_counters.clear
    ActionMailer::Base.deliveries.clear
    allow(Escalated.configuration).to receive_messages(
      enable_newsletters?: true,
      newsletter_batch_size: 50,
      newsletter_rate_limit_per_minute: 60,
      newsletter_claim_timeout_minutes: 10,
      newsletter_auto_pause_threshold: 100,
      newsletter_auto_pause_bounce_rate: 0.05,
      app_url: 'https://app.test'
    )
  end

  it 'claims pending rows, sends mail, and marks deliveries sent' do
    create_list(:escalated_newsletter_delivery, 2, newsletter: newsletter, status: 'pending')

    dispatcher.dispatch_batch

    expect(newsletter.deliveries.pluck(:status)).to all(eq('sent'))
    expect(newsletter.deliveries.where.not(sent_at: nil).count).to eq(2)
    expect(ActionMailer::Base.deliveries.size).to eq(2)
  end

  it 'respects batch size and finalizes completed newsletters' do
    allow(Escalated.configuration).to receive(:newsletter_batch_size).and_return(2)
    create_list(:escalated_newsletter_delivery, 5, newsletter: newsletter, status: 'pending')

    dispatcher.dispatch_batch

    expect(newsletter.deliveries.where(status: 'sent').count).to eq(2)
    expect(newsletter.reload.status).to eq('sending')

    3.times { dispatcher.dispatch_batch }
    expect(newsletter.reload.status).to eq('sent')
  end

  it 'does nothing when newsletters are disabled' do
    allow(Escalated.configuration).to receive(:enable_newsletters?).and_return(false)
    create_list(:escalated_newsletter_delivery, 5, newsletter: newsletter, status: 'pending')

    dispatcher.dispatch_batch

    expect(newsletter.deliveries.pluck(:status)).to all(eq('pending'))
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'enforces the per-minute rate limit across ticks' do
    allow(Escalated.configuration).to receive(:newsletter_rate_limit_per_minute).and_return(2)
    create_list(:escalated_newsletter_delivery, 5, newsletter: newsletter, status: 'pending')

    dispatcher.dispatch_batch
    dispatcher.dispatch_batch

    expect(newsletter.deliveries.where(status: 'sent').count).to eq(2)
  end

  it 'does not claim deliveries whose next_attempt_at is in the future' do
    create(:escalated_newsletter_delivery, newsletter: newsletter, status: 'pending',
                                           next_attempt_at: 5.minutes.from_now)

    dispatcher.dispatch_batch

    expect(newsletter.deliveries.first.reload.status).to eq('pending')
  end

  it 'auto-pauses a campaign when first terminal deliveries exceed the bounce threshold' do
    allow(Escalated.configuration).to receive_messages(newsletter_auto_pause_threshold: 4,
                                                       newsletter_auto_pause_bounce_rate: 0.05)
    create(:escalated_newsletter_delivery, newsletter: newsletter, status: 'bounced')
    create_list(:escalated_newsletter_delivery, 3, newsletter: newsletter, status: 'sent')

    dispatcher.dispatch_batch

    expect(newsletter.reload.status).to eq('paused')
  end
end
