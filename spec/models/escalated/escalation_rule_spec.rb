require "rails_helper"

RSpec.describe Escalated::EscalationRule, type: :model do
  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:conditions) }
    it { is_expected.to validate_presence_of(:actions) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    describe ".active" do
      it "returns only active rules" do
        active = create(:escalated_escalation_rule, is_active: true)
        _inactive = create(:escalated_escalation_rule, :inactive)

        result = described_class.active
        expect(result).to include(active)
        expect(result).not_to include(_inactive)
      end
    end

    describe ".ordered" do
      it "returns rules ordered by priority ascending" do
        low_priority = create(:escalated_escalation_rule, priority: 10)
        high_priority = create(:escalated_escalation_rule, priority: 1)

        result = described_class.ordered
        expect(result.first).to eq(high_priority)
        expect(result.last).to eq(low_priority)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#active?" do
    it "returns true when active" do
      rule = build(:escalated_escalation_rule, is_active: true)
      expect(rule.active?).to be(true)
    end

    it "returns false when inactive" do
      rule = build(:escalated_escalation_rule, is_active: false)
      expect(rule.active?).to be(false)
    end
  end

  # ------------------------------------------------------------------ #
  # #matches?
  # ------------------------------------------------------------------ #
  describe "#matches?" do
    let(:ticket) { create(:escalated_ticket, status: :open, priority: :high) }

    it "returns false when the rule is inactive" do
      rule = build(:escalated_escalation_rule, :inactive)
      expect(rule.matches?(ticket)).to be(false)
    end

    context "status conditions" do
      it "matches when ticket status is in the conditions list" do
        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "status" => ["open", "in_progress"] },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(true)
      end

      it "does not match when ticket status is not in the conditions list" do
        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "status" => ["resolved", "closed"] },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(false)
      end

      it "matches when no status condition is specified" do
        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: {},
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(true)
      end
    end

    context "priority conditions" do
      it "matches when ticket priority is in the conditions list" do
        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "priority" => ["high", "urgent", "critical"] },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(true)
      end

      it "does not match when ticket priority is not in the conditions list" do
        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "priority" => ["low"] },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(false)
      end
    end

    context "SLA breach conditions" do
      it "matches when sla_breached is true and ticket has breached first response SLA" do
        breached_ticket = build(:escalated_ticket,
                                status: :open,
                                priority: :high,
                                sla_first_response_due_at: 2.hours.ago,
                                first_response_at: nil)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "sla_breached" => true },
                     actions: { "send_notification" => true })

        expect(rule.matches?(breached_ticket)).to be(true)
      end

      it "matches when sla_breached is true and ticket has breached resolution SLA" do
        breached_ticket = build(:escalated_ticket,
                                status: :open,
                                priority: :high,
                                sla_resolution_due_at: 2.hours.ago,
                                resolved_at: nil)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "sla_breached" => true },
                     actions: { "send_notification" => true })

        expect(rule.matches?(breached_ticket)).to be(true)
      end

      it "does not match when sla_breached is true but ticket has not breached SLA" do
        non_breached = build(:escalated_ticket,
                             status: :open,
                             priority: :high,
                             sla_first_response_due_at: 4.hours.from_now,
                             first_response_at: nil)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "sla_breached" => true },
                     actions: { "send_notification" => true })

        expect(rule.matches?(non_breached)).to be(false)
      end
    end

    context "unassigned_for_minutes conditions" do
      it "matches when ticket is unassigned for longer than threshold" do
        old_ticket = create(:escalated_ticket,
                            status: :open,
                            priority: :high,
                            assigned_to: nil,
                            created_at: 45.minutes.ago)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "unassigned_for_minutes" => 30 },
                     actions: { "send_notification" => true })

        expect(rule.matches?(old_ticket)).to be(true)
      end

      it "does not match when ticket is assigned" do
        agent = create(:user, :agent)
        assigned_ticket = create(:escalated_ticket,
                                 status: :open,
                                 priority: :high,
                                 assigned_to: agent.id,
                                 created_at: 45.minutes.ago)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "unassigned_for_minutes" => 30 },
                     actions: { "send_notification" => true })

        expect(rule.matches?(assigned_ticket)).to be(false)
      end

      it "does not match when ticket was created less than threshold minutes ago" do
        recent_ticket = create(:escalated_ticket,
                               status: :open,
                               priority: :high,
                               assigned_to: nil,
                               created_at: 10.minutes.ago)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "unassigned_for_minutes" => 30 },
                     actions: { "send_notification" => true })

        expect(rule.matches?(recent_ticket)).to be(false)
      end
    end

    context "no_response_for_minutes conditions" do
      it "matches when no reply exists and ticket is older than threshold" do
        old_ticket = create(:escalated_ticket,
                            status: :open,
                            priority: :high,
                            created_at: 90.minutes.ago)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "no_response_for_minutes" => 60 },
                     actions: { "send_notification" => true })

        expect(rule.matches?(old_ticket)).to be(true)
      end

      it "matches when last public reply is older than threshold" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        priority: :high,
                        created_at: 2.hours.ago)
        author = create(:user)
        create(:escalated_reply,
               ticket: ticket,
               author: author,
               is_internal: false,
               created_at: 90.minutes.ago)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "no_response_for_minutes" => 60 },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(true)
      end

      it "does not match when a recent public reply exists" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        priority: :high,
                        created_at: 2.hours.ago)
        author = create(:user)
        create(:escalated_reply,
               ticket: ticket,
               author: author,
               is_internal: false,
               created_at: 10.minutes.ago)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "no_response_for_minutes" => 60 },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(false)
      end
    end

    context "department conditions" do
      it "matches when ticket is in one of the specified departments" do
        dept = create(:escalated_department)
        dept_ticket = create(:escalated_ticket,
                             status: :open,
                             priority: :high,
                             department: dept)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "department_ids" => [dept.id] },
                     actions: { "send_notification" => true })

        expect(rule.matches?(dept_ticket)).to be(true)
      end

      it "does not match when ticket is in a different department" do
        dept1 = create(:escalated_department)
        dept2 = create(:escalated_department)
        ticket = create(:escalated_ticket,
                        status: :open,
                        priority: :high,
                        department: dept1)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: { "department_ids" => [dept2.id] },
                     actions: { "send_notification" => true })

        expect(rule.matches?(ticket)).to be(false)
      end
    end

    context "combined conditions" do
      it "matches only when all conditions are met" do
        dept = create(:escalated_department)
        ticket = create(:escalated_ticket,
                        status: :open,
                        priority: :high,
                        department: dept,
                        sla_first_response_due_at: 2.hours.ago,
                        first_response_at: nil)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: {
                       "status" => ["open"],
                       "priority" => ["high", "urgent", "critical"],
                       "sla_breached" => true,
                       "department_ids" => [dept.id]
                     },
                     actions: { "change_status" => "escalated" })

        expect(rule.matches?(ticket)).to be(true)
      end

      it "does not match when one condition fails" do
        dept = create(:escalated_department)
        ticket = create(:escalated_ticket,
                        status: :open,
                        priority: :low, # Does not match priority condition
                        department: dept,
                        sla_first_response_due_at: 2.hours.ago,
                        first_response_at: nil)

        rule = build(:escalated_escalation_rule,
                     is_active: true,
                     conditions: {
                       "status" => ["open"],
                       "priority" => ["high", "urgent", "critical"],
                       "sla_breached" => true
                     },
                     actions: { "change_status" => "escalated" })

        expect(rule.matches?(ticket)).to be(false)
      end
    end
  end
end
