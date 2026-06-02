# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Newsletter::Tracker do
  subject(:tracker) { described_class.new }

  let(:newsletter) { create(:escalated_newsletter, status: 'sending') }
  let(:delivery) { create(:escalated_newsletter_delivery, newsletter: newsletter, status: 'sent') }

  it 'records the first open only' do
    tracker.record_open(delivery.tracking_token)
    tracker.record_open(delivery.tracking_token)

    expect(delivery.reload.opened_at).to be_present
    expect(newsletter.reload.summary_opened).to eq(1)
  end

  it 'records clicks and increments the newsletter click summary once' do
    2.times { tracker.record_click(delivery.tracking_token, 'https://example.com') }

    expect(delivery.reload.clicks_count).to eq(2)
    expect(delivery.last_clicked_at).to be_present
    expect(newsletter.reload.summary_clicked).to eq(1)
  end

  it 'records hard bounces and adds the email to the suppression store' do
    tracker.record_bounce(delivery.tracking_token, 'hard', 'Bad mailbox')

    expect(delivery.reload.status).to eq('bounced')
    expect(delivery.bounce_reason).to eq('Bad mailbox')
    expect(newsletter.reload.summary_bounced).to eq(1)
    expect(Escalated::Newsletter::BounceSuppressionStore.new.bounced?(delivery.email_at_send)).to be true
  end

  it 'records complaints and ignores unknown tokens' do
    expect { tracker.record_open('missing') }.not_to raise_error

    tracker.record_complaint(delivery.tracking_token)

    expect(delivery.reload.status).to eq('complained')
    expect(newsletter.reload.summary_complained).to eq(1)
    expect(Escalated::Newsletter::BounceSuppressionStore.new.bounced?(delivery.email_at_send)).to be true
  end

  it 'ignores opens after a bounce' do
    delivery.update!(status: 'bounced')

    tracker.record_open(delivery.tracking_token)

    expect(delivery.reload.opened_at).to be_nil
  end
end
