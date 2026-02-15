require "rails_helper"

RSpec.describe Escalated::Ticket, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe "associations" do
    it { is_expected.to belong_to(:requester).optional }
    it { is_expected.to belong_to(:assignee).class_name("User").with_foreign_key(:assigned_to).optional }
    it { is_expected.to belong_to(:department).optional }
    it { is_expected.to belong_to(:sla_policy).optional }
    it { is_expected.to have_many(:replies).dependent(:destroy) }
    it { is_expected.to have_many(:attachments) }
    it { is_expected.to have_many(:activities).class_name("Escalated::TicketActivity").dependent(:destroy) }
    it { is_expected.to have_one(:satisfaction_rating).class_name("Escalated::SatisfactionRating").dependent(:destroy) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:subject) }
    it { is_expected.to validate_length_of(:subject).is_at_most(255) }
    it { is_expected.to validate_presence_of(:description) }

    context "reference uniqueness" do
      subject { create(:escalated_ticket) }

      it { is_expected.to validate_uniqueness_of(:reference) }
    end
  end

  # ------------------------------------------------------------------ #
  # Enums
  # ------------------------------------------------------------------ #
  describe "enums" do
    it "defines status enum with correct values" do
      expect(described_class.statuses).to eq(
        "open" => 0,
        "in_progress" => 1,
        "waiting_on_customer" => 2,
        "waiting_on_agent" => 3,
        "escalated" => 4,
        "resolved" => 5,
        "closed" => 6,
        "reopened" => 7
      )
    end

    it "defines priority enum with correct values" do
      expect(described_class.priorities).to eq(
        "low" => 0,
        "medium" => 1,
        "high" => 2,
        "urgent" => 3,
        "critical" => 4
      )
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe "callbacks" do
    describe "#set_reference" do
      it "automatically sets a reference before creation when blank" do
        ticket = build(:escalated_ticket, reference: nil)
        ticket.save!

        expect(ticket.reference).to be_present
        expect(ticket.reference).to match(/\A[A-Z]+-\d{4}-[A-Z0-9]{6}\z/)
      end

      it "does not override an existing reference" do
        ticket = build(:escalated_ticket, reference: "CUSTOM-2601-ABCDEF")
        ticket.save!

        expect(ticket.reference).to eq("CUSTOM-2601-ABCDEF")
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Class methods
  # ------------------------------------------------------------------ #
  describe ".generate_reference" do
    it "returns a formatted reference string" do
      ref = described_class.generate_reference
      expect(ref).to match(/\A[A-Z]+-\d{4}-[A-Z0-9]{6}\z/)
    end

    it "uses the configured prefix from EscalatedSetting" do
      allow(Escalated::EscalatedSetting).to receive(:get).with("ticket_reference_prefix", "ESC").and_return("TKT")
      ref = described_class.generate_reference
      expect(ref).to start_with("TKT-")
    end

    it "generates unique references" do
      refs = Array.new(20) { described_class.generate_reference }
      expect(refs.uniq.length).to eq(20)
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    let!(:user) { create(:user) }
    let!(:agent) { create(:user, :agent) }

    describe ".by_open" do
      it "returns tickets with open-like statuses" do
        open_ticket = create(:escalated_ticket, :open)
        in_progress = create(:escalated_ticket, :in_progress)
        waiting_cust = create(:escalated_ticket, :waiting_on_customer)
        waiting_agent = create(:escalated_ticket, :waiting_on_agent)
        escalated = create(:escalated_ticket, :escalated)
        reopened = create(:escalated_ticket, status: :reopened)
        _resolved = create(:escalated_ticket, :resolved)
        _closed = create(:escalated_ticket, :closed)

        result = described_class.by_open
        expect(result).to include(open_ticket, in_progress, waiting_cust, waiting_agent, escalated, reopened)
        expect(result).not_to include(_resolved, _closed)
      end
    end

    describe ".unassigned" do
      it "returns tickets with no assignee" do
        unassigned = create(:escalated_ticket, assigned_to: nil)
        _assigned = create(:escalated_ticket, assigned_to: agent.id)

        result = described_class.unassigned
        expect(result).to include(unassigned)
        expect(result).not_to include(_assigned)
      end
    end

    describe ".assigned_to" do
      it "returns tickets assigned to a specific agent" do
        assigned = create(:escalated_ticket, assigned_to: agent.id)
        _other = create(:escalated_ticket, assigned_to: nil)

        result = described_class.assigned_to(agent.id)
        expect(result).to include(assigned)
        expect(result).not_to include(_other)
      end
    end

    describe ".breached_sla" do
      it "returns tickets marked as SLA breached" do
        breached = create(:escalated_ticket, :sla_breached)
        _normal = create(:escalated_ticket)

        result = described_class.breached_sla
        expect(result).to include(breached)
      end

      it "returns tickets with overdue first response" do
        overdue = create(:escalated_ticket,
                         sla_first_response_due_at: 2.hours.ago,
                         first_response_at: nil,
                         sla_breached: false)

        result = described_class.breached_sla
        expect(result).to include(overdue)
      end

      it "returns tickets with overdue resolution" do
        overdue = create(:escalated_ticket,
                         sla_resolution_due_at: 2.hours.ago,
                         resolved_at: nil,
                         status: :open,
                         sla_breached: false)

        result = described_class.breached_sla
        expect(result).to include(overdue)
      end
    end

    describe ".search" do
      it "searches by subject" do
        ticket = create(:escalated_ticket, subject: "Password reset issue")
        _other = create(:escalated_ticket, subject: "Billing question")

        result = described_class.search("Password")
        expect(result).to include(ticket)
        expect(result).not_to include(_other)
      end

      it "searches by description" do
        ticket = create(:escalated_ticket, description: "Cannot login to dashboard")
        _other = create(:escalated_ticket, description: "Payment failed")

        result = described_class.search("login")
        expect(result).to include(ticket)
        expect(result).not_to include(_other)
      end

      it "searches by reference" do
        ticket = create(:escalated_ticket)
        _other = create(:escalated_ticket)

        result = described_class.search(ticket.reference)
        expect(result).to include(ticket)
      end
    end

    describe ".by_priority" do
      it "returns tickets of a specific priority" do
        high = create(:escalated_ticket, :high_priority)
        _low = create(:escalated_ticket, :low_priority)

        result = described_class.by_priority(:high)
        expect(result).to include(high)
        expect(result).not_to include(_low)
      end
    end

    describe ".by_department" do
      it "returns tickets in a specific department" do
        dept = create(:escalated_department)
        ticket = create(:escalated_ticket, department: dept)
        _other = create(:escalated_ticket)

        result = described_class.by_department(dept.id)
        expect(result).to include(ticket)
        expect(result).not_to include(_other)
      end
    end

    describe ".created_between" do
      it "returns tickets created within a date range" do
        old_ticket = create(:escalated_ticket, created_at: 10.days.ago)
        recent = create(:escalated_ticket, created_at: 2.days.ago)

        result = described_class.created_between(5.days.ago, Time.current)
        expect(result).to include(recent)
        expect(result).not_to include(old_ticket)
      end
    end

    describe ".recent" do
      it "returns tickets ordered by created_at descending" do
        old = create(:escalated_ticket, created_at: 3.days.ago)
        newer = create(:escalated_ticket, created_at: 1.day.ago)

        result = described_class.recent
        expect(result.first).to eq(newer)
        expect(result.last).to eq(old)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#open?" do
    it "returns true for open-like statuses" do
      %w[open in_progress waiting_on_customer waiting_on_agent escalated reopened].each do |status|
        ticket = build(:escalated_ticket, status: status)
        expect(ticket.open?).to be(true), "Expected #{status} to be open"
      end
    end

    it "returns false for resolved and closed" do
      %w[resolved closed].each do |status|
        ticket = build(:escalated_ticket, status: status)
        expect(ticket.open?).to be(false), "Expected #{status} to not be open"
      end
    end
  end

  describe "#sla_first_response_breached?" do
    it "returns false when no due date is set" do
      ticket = build(:escalated_ticket, sla_first_response_due_at: nil)
      expect(ticket.sla_first_response_breached?).to be(false)
    end

    it "returns false when first response was already made" do
      ticket = build(:escalated_ticket,
                     sla_first_response_due_at: 1.hour.ago,
                     first_response_at: 2.hours.ago)
      expect(ticket.sla_first_response_breached?).to be(false)
    end

    it "returns true when due date has passed and no response" do
      ticket = build(:escalated_ticket,
                     sla_first_response_due_at: 1.hour.ago,
                     first_response_at: nil)
      expect(ticket.sla_first_response_breached?).to be(true)
    end

    it "returns false when due date has not passed" do
      ticket = build(:escalated_ticket,
                     sla_first_response_due_at: 1.hour.from_now,
                     first_response_at: nil)
      expect(ticket.sla_first_response_breached?).to be(false)
    end
  end

  describe "#sla_resolution_breached?" do
    it "returns false when no due date is set" do
      ticket = build(:escalated_ticket, sla_resolution_due_at: nil)
      expect(ticket.sla_resolution_breached?).to be(false)
    end

    it "returns false when already resolved" do
      ticket = build(:escalated_ticket,
                     sla_resolution_due_at: 1.hour.ago,
                     resolved_at: 2.hours.ago)
      expect(ticket.sla_resolution_breached?).to be(false)
    end

    it "returns true when due date passed and not resolved" do
      ticket = build(:escalated_ticket,
                     sla_resolution_due_at: 1.hour.ago,
                     resolved_at: nil)
      expect(ticket.sla_resolution_breached?).to be(true)
    end
  end

  describe "#sla_first_response_warning?" do
    it "returns true when within 1 hour of breach and no response" do
      ticket = build(:escalated_ticket,
                     sla_first_response_due_at: 30.minutes.from_now,
                     first_response_at: nil)
      expect(ticket.sla_first_response_warning?).to be(true)
    end

    it "returns false when more than 1 hour from breach" do
      ticket = build(:escalated_ticket,
                     sla_first_response_due_at: 2.hours.from_now,
                     first_response_at: nil)
      expect(ticket.sla_first_response_warning?).to be(false)
    end

    it "returns false when already responded" do
      ticket = build(:escalated_ticket,
                     sla_first_response_due_at: 30.minutes.from_now,
                     first_response_at: Time.current)
      expect(ticket.sla_first_response_warning?).to be(false)
    end
  end

  describe "#sla_resolution_warning?" do
    it "returns true when within 2 hours of breach and not resolved" do
      ticket = build(:escalated_ticket,
                     sla_resolution_due_at: 1.hour.from_now,
                     resolved_at: nil)
      expect(ticket.sla_resolution_warning?).to be(true)
    end

    it "returns false when more than 2 hours from breach" do
      ticket = build(:escalated_ticket,
                     sla_resolution_due_at: 5.hours.from_now,
                     resolved_at: nil)
      expect(ticket.sla_resolution_warning?).to be(false)
    end
  end

  describe "#time_to_first_response" do
    it "returns nil when no first response" do
      ticket = build(:escalated_ticket, first_response_at: nil)
      expect(ticket.time_to_first_response).to be_nil
    end

    it "returns the time difference in seconds" do
      created = 3.hours.ago
      responded = 1.hour.ago
      ticket = build(:escalated_ticket, created_at: created, first_response_at: responded)
      expect(ticket.time_to_first_response).to be_within(1).of(2.hours.to_i)
    end
  end

  describe "#time_to_resolution" do
    it "returns nil when not resolved" do
      ticket = build(:escalated_ticket, resolved_at: nil)
      expect(ticket.time_to_resolution).to be_nil
    end

    it "returns the time difference in seconds" do
      created = 5.hours.ago
      resolved = 1.hour.ago
      ticket = build(:escalated_ticket, created_at: created, resolved_at: resolved)
      expect(ticket.time_to_resolution).to be_within(1).of(4.hours.to_i)
    end
  end

  describe "#guest?" do
    it "returns true when requester_type is nil and guest_token present" do
      ticket = build(:escalated_ticket,
                     requester_type: nil,
                     requester_id: nil,
                     guest_token: "abc123",
                     guest_name: "John")
      expect(ticket.guest?).to be(true)
    end

    it "returns false when requester_type is present" do
      ticket = build(:escalated_ticket)
      expect(ticket.guest?).to be(false)
    end
  end

  describe "#requester_name" do
    it "returns the guest name for guest tickets" do
      ticket = build(:escalated_ticket,
                     requester_type: nil,
                     requester_id: nil,
                     guest_token: "abc123",
                     guest_name: "Jane Doe")
      expect(ticket.requester_name).to eq("Jane Doe")
    end

    it "returns 'Guest' when guest has no name" do
      ticket = build(:escalated_ticket,
                     requester_type: nil,
                     requester_id: nil,
                     guest_token: "abc123",
                     guest_name: nil)
      expect(ticket.requester_name).to eq("Guest")
    end

    it "returns the user name for authenticated requesters" do
      user = create(:user, name: "Alice Smith")
      ticket = create(:escalated_ticket, requester: user)
      expect(ticket.requester_name).to eq("Alice Smith")
    end
  end

  describe "follower methods" do
    let(:ticket) { create(:escalated_ticket) }
    let(:user) { create(:user) }

    describe "#followed_by?" do
      it "returns false when user is not following" do
        expect(ticket.followed_by?(user.id)).to be(false)
      end

      it "returns true when user is following" do
        ticket.followers << user
        expect(ticket.followed_by?(user.id)).to be(true)
      end
    end

    describe "#follow" do
      it "adds the user as a follower" do
        ticket.follow(user.id)
        expect(ticket.followers).to include(user)
      end

      it "does not add duplicate followers" do
        ticket.follow(user.id)
        ticket.follow(user.id)
        expect(ticket.followers.where(id: user.id).count).to eq(1)
      end
    end

    describe "#unfollow" do
      it "removes the user from followers" do
        ticket.followers << user
        ticket.unfollow(user.id)
        expect(ticket.followers).not_to include(user)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Tags association
  # ------------------------------------------------------------------ #
  describe "tags" do
    let(:ticket) { create(:escalated_ticket) }
    let(:tag1) { create(:escalated_tag, name: "Bug") }
    let(:tag2) { create(:escalated_tag, name: "Feature") }

    it "can have multiple tags" do
      ticket.tags << tag1
      ticket.tags << tag2
      expect(ticket.tags.count).to eq(2)
    end

    it "can remove tags" do
      ticket.tags << tag1
      ticket.tags.delete(tag1)
      expect(ticket.tags).to be_empty
    end
  end
end
