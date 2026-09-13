# frozen_string_literal: true

require 'rails_helper'

# ApplicationMailer and TicketMailer both read configuration.mailer_from, but
# Configuration never defined it: `respond_to?(:mailer_from)` was always false,
# so every email went out from support@example.com and a host setting it in an
# initializer got NoMethodError.
RSpec.describe 'Escalated mail sender address' do # rubocop:disable RSpec/DescribeClass
  let(:ticket) { create(:escalated_ticket, requester: create(:user)) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [:email], webhook_url: nil,
                                                       email_domain: nil)
  end

  after do
    Escalated.configuration.instance_variable_set(:@mailer_from, nil)
  end

  it 'sends from the configured address' do
    Escalated.configure { |config| config.mailer_from = 'help@host.test' }

    expect(Escalated::TicketMailer.new_ticket(ticket).from).to eq(['help@host.test'])
  end

  it 'takes the Message-ID domain from the configured address when email_domain is unset' do
    Escalated.configure { |config| config.mailer_from = 'Help Desk <help@host.test>' }

    mail = Escalated::TicketMailer.new_ticket(ticket)

    expect(mail.from).to eq(['help@host.test'])
    expect(mail['Message-ID'].to_s).to match(/ticket-#{ticket.id}@host\.test>?\z/)
  end

  it 'still has a sender when nothing is configured' do
    expect(Escalated::TicketMailer.new_ticket(ticket).from).to eq(['support@example.com'])
  end
end
