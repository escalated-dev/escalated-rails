# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# The retention settings saved on Admin/Settings/DataRetention, applied
# (escalated-laravel's `escalated:purge-expired`). Rails tickets have no soft
# delete, so a closed ticket past its retention is destroyed outright, with the
# rows that hang off it.
RSpec.describe Escalated::PurgeExpiredDataJob do
  let!(:old_closed) { create(:escalated_ticket, status: :closed, closed_at: 2.years.ago) }
  let!(:recent_closed) { create(:escalated_ticket, status: :closed, closed_at: 2.months.ago) }
  let!(:old_open) { create(:escalated_ticket, status: :open, created_at: 3.years.ago) }

  let!(:old_attachment) do
    Escalated::Attachment.create!(attachable: old_open, filename: 'old.txt', content_type: 'text/plain',
                                  byte_size: 1, created_at: 4.years.ago)
  end
  let!(:new_attachment) do
    Escalated::Attachment.create!(attachable: old_open, filename: 'new.txt', content_type: 'text/plain', byte_size: 1)
  end
  let!(:old_log) { create(:escalated_audit_log, auditable: old_open, created_at: 100.days.ago) }
  let!(:new_log) { create(:escalated_audit_log, auditable: old_open) }

  def retain(closed_tickets: 'never', attachments: 'never', audit_logs: 'never')
    Escalated::EscalatedSetting.set('retention_closed_tickets', closed_tickets)
    Escalated::EscalatedSetting.set('retention_attachments', attachments)
    Escalated::EscalatedSetting.set('retention_audit_logs', audit_logs)
  end

  def expired_proof
    Escalated::GuestVerification.create!(id: SecureRandom.uuid, email_digest: 'a' * 64, purpose: 'ticket',
                                         code_hash: 'b' * 64, expires_at: 1.minute.ago)
  end

  it 'purges nothing while every retention is never (the default)' do
    expect { described_class.perform_now }
      .not_to(change { [Escalated::Ticket.count, Escalated::Attachment.count, Escalated::AuditLog.count] })
  end

  it 'destroys closed tickets past their retention, with their replies, and keeps the rest' do
    create(:escalated_reply, ticket: old_closed)
    Escalated::Attachment.create!(attachable: old_closed, filename: 'x.txt', content_type: 'text/plain',
                                  byte_size: 1)
    retain(closed_tickets: '1_year')

    result = described_class.perform_now

    expect(result).to include(tickets: 1)
    expect(Escalated::Ticket.exists?(old_closed.id)).to be(false)
    expect(Escalated::Reply.where(ticket_id: old_closed.id)).to be_empty
    expect(Escalated::Attachment.where(attachable: old_closed)).to be_empty
    expect(Escalated::Ticket.where(id: [recent_closed.id, old_open.id]).count).to eq(2)
  end

  it 'removes a closed ticket that workflows have logged against' do
    create(:escalated_workflow_log, ticket: old_closed)
    create(:escalated_delayed_action, ticket: old_closed)
    retain(closed_tickets: '1_year')

    described_class.perform_now

    expect(Escalated::Ticket.exists?(old_closed.id)).to be(false)
  end

  it 'deletes attachments past their retention' do
    retain(attachments: '3_years')

    expect(described_class.perform_now).to include(attachments: 1)
    expect(Escalated::Attachment.exists?(old_attachment.id)).to be(false)
    expect(Escalated::Attachment.exists?(new_attachment.id)).to be(true)
  end

  it 'deletes audit logs past their retention' do
    retain(audit_logs: '90_days')

    expect(described_class.perform_now).to include(audit_logs: 1)
    expect(Escalated::AuditLog.exists?(old_log.id)).to be(false)
    expect(Escalated::AuditLog.exists?(new_log.id)).to be(true)
  end

  it 'deletes expired guest verification codes' do
    proof = expired_proof

    expect(described_class.perform_now).to include(guest_verifications: 1)
    expect(Escalated::GuestVerification.exists?(proof.id)).to be(false)
  end

  it 'counts without deleting on a dry run' do
    retain(closed_tickets: '1_year', attachments: '3_years', audit_logs: '90_days')
    expired_proof

    result = described_class.perform_now(dry_run: true)

    expect(result).to eq(tickets: 1, attachments: 1, audit_logs: 1, guest_verifications: 1)
    expect([Escalated::Ticket.count, Escalated::Attachment.count, Escalated::AuditLog.count,
            Escalated::GuestVerification.count]).to eq([3, 2, 2, 1])
  end

  describe 'rake escalated:purge_expired' do
    around do |example|
      original = Rake.application
      Rake.application = Rake::Application.new
      Rails.application.load_tasks
      example.run
    ensure
      Rake.application = original
    end

    it 'runs the purge, and only counts with DRY_RUN=1' do
      retain(closed_tickets: '1_year')

      ENV['DRY_RUN'] = '1'
      expect { Rake::Task['escalated:purge_expired'].invoke }.to output(/Closed tickets: 1/).to_stdout
      expect(Escalated::Ticket.exists?(old_closed.id)).to be(true)

      ENV.delete('DRY_RUN')
      Rake::Task['escalated:purge_expired'].reenable
      expect { Rake::Task['escalated:purge_expired'].invoke }.to output(/Closed tickets: 1/).to_stdout
      expect(Escalated::Ticket.exists?(old_closed.id)).to be(false)
    ensure
      ENV.delete('DRY_RUN')
    end
  end
end
