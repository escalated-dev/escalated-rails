# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Newsletter::Planner do
  subject(:planner) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:enable_newsletters?).and_return(true)
  end

  it 'creates one pending delivery per sendable contact and marks the newsletter sending' do
    list = create(:escalated_newsletter_list)
    contacts = create_list(:escalated_contact, 2)
    contacts.each { |contact| create(:escalated_newsletter_list_member, list: list, contact: contact) }
    newsletter = create(:escalated_newsletter, target_list: list, status: 'scheduled')

    expect { planner.plan(newsletter) }.to change(Escalated::NewsletterDelivery, :count).by(2)

    newsletter.reload
    expect(newsletter.status).to eq('sending')
    expect(newsletter.summary_total).to eq(2)
    expect(newsletter.deliveries.pluck(:status)).to all(eq('pending'))
  end

  it 'skips opted-out and suppressed contacts' do
    list = create(:escalated_newsletter_list)
    opted_in = create(:escalated_contact, email: 'in@example.com')
    opted_out = create(:escalated_contact, email: 'out@example.com', marketing_opt_out_at: Time.current)
    suppressed = create(:escalated_contact, email: 'blocked@example.com')
    [opted_in, opted_out, suppressed].each do |contact|
      create(:escalated_newsletter_list_member, list: list, contact: contact)
    end
    Escalated::Newsletter::BounceSuppressionStore.new.mark_bounced(suppressed.email)

    newsletter = create(:escalated_newsletter, target_list: list, status: 'scheduled')
    planner.plan(newsletter)

    expect(newsletter.deliveries.pluck(:email_at_send)).to eq(['in@example.com'])
  end

  it 'snapshots email_at_send and generates unique tracking tokens' do
    list = create(:escalated_newsletter_list)
    contact = create(:escalated_contact, email: 'before@example.com')
    create(:escalated_newsletter_list_member, list: list, contact: contact)
    newsletter = create(:escalated_newsletter, target_list: list)

    planner.plan(newsletter)
    contact.update!(email: 'after@example.com')

    delivery = newsletter.deliveries.first
    expect(delivery.email_at_send).to eq('before@example.com')
    expect(newsletter.deliveries.pluck(:tracking_token).uniq.size).to eq(newsletter.deliveries.count)
  end
end
