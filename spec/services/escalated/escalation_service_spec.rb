require "rails_helper"

RSpec.describe Escalated::Services::EscalationService do
  let(:user) { create(:user) }
  let(:agent) { create(:user, :agent) }

  # Disable email notifications for tests
  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  # ------------------------------------------------------------------ #
  # .evaluate_ticket
  # ------------------------------------------------------------------ #
  describe ".evaluate_ticket" do
    it "returns nil when no rules match" do
      ticket = create(:escalated_ticket, status: :open, priority: :low)
      create(:escalated_escalation_rule,
             conditions: { "priority" => ["critical"] },
             actions: { "change_status" => "escalated" })

      result = described_class.evaluate_ticket(ticket)
      expect(result).to be_nil
    end

    it "returns the matching rule" do
      ticket = create(:escalated_ticket, status: :open, priority: :high,
                       sla_first_response_due_at: 2.hours.ago,
                       first_response_at: nil)
      rule = create(:escalated_escalation_rule,
                    conditions: {
                      "status" => ["open"],
                      "priority" => ["high", "urgent", "critical"],
                      "sla_breached" => true
                    },
                    actions: { "change_status" => "escalated" })

      result = described_class.evaluate_ticket(ticket)
      expect(result).to eq(rule)
    end

    it "applies only the first matching rule" do
      ticket = create(:escalated_ticket, status: :open, priority: :high,
                       sla_first_response_due_at: 2.hours.ago,
                       first_response_at: nil)

      rule1 = create(:escalated_escalation_rule,
                     name: "First Rule",
                     priority: 1,
                     conditions: { "status" => ["open"], "sla_breached" => true },
                     actions: { "change_priority" => "urgent" })
      _rule2 = create(:escalated_escalation_rule,
                      name: "Second Rule",
                      priority: 2,
                      conditions: { "status" => ["open"], "sla_breached" => true },
                      actions: { "change_priority" => "critical" })

      result = described_class.evaluate_ticket(ticket)
      expect(result).to eq(rule1)

      # Ticket should have priority from first rule, not second
      ticket.reload
      expect(ticket.priority).to eq("urgent")
    end

    it "skips inactive rules" do
      ticket = create(:escalated_ticket, status: :open, priority: :high)
      create(:escalated_escalation_rule,
             :inactive,
             conditions: { "status" => ["open"] },
             actions: { "change_status" => "escalated" })

      result = described_class.evaluate_ticket(ticket)
      expect(result).to be_nil
    end

    context "with change_priority action" do
      it "changes the ticket priority" do
        ticket = create(:escalated_ticket, status: :open, priority: :medium)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "change_priority" => "critical" })

        described_class.evaluate_ticket(ticket)
        ticket.reload
        expect(ticket.priority).to eq("critical")
      end

      it "creates a priority_changed activity" do
        ticket = create(:escalated_ticket, status: :open, priority: :medium)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "change_priority" => "critical" })

        described_class.evaluate_ticket(ticket)

        activity = ticket.activities.find_by(action: "priority_changed")
        expect(activity).to be_present
        expect(activity.details["reason"]).to eq("escalation_rule")
      end
    end

    context "with change_status action" do
      it "changes the ticket status" do
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "change_status" => "escalated" })

        described_class.evaluate_ticket(ticket)
        ticket.reload
        expect(ticket.status).to eq("escalated")
      end

      it "creates a status_changed activity" do
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "change_status" => "escalated" })

        described_class.evaluate_ticket(ticket)

        activity = ticket.activities.find_by(action: "status_changed")
        expect(activity).to be_present
        expect(activity.details["to"]).to eq("escalated")
        expect(activity.details["reason"]).to eq("escalation_rule")
      end
    end

    context "with assign_to_agent_id action" do
      it "assigns the ticket to the specified agent" do
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "assign_to_agent_id" => agent.id })

        described_class.evaluate_ticket(ticket)
        ticket.reload
        expect(ticket.assigned_to).to eq(agent.id)
      end

      it "creates a ticket_assigned activity" do
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "assign_to_agent_id" => agent.id })

        described_class.evaluate_ticket(ticket)

        activity = ticket.activities.find_by(action: "ticket_assigned")
        expect(activity).to be_present
        expect(activity.details["to_agent_id"]).to eq(agent.id)
      end

      it "does nothing if agent does not exist" do
        ticket = create(:escalated_ticket, status: :open, priority: :high, assigned_to: nil)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "assign_to_agent_id" => 999999 })

        described_class.evaluate_ticket(ticket)
        ticket.reload
        expect(ticket.assigned_to).to be_nil
      end
    end

    context "with assign_to_department_id action" do
      it "assigns the ticket to the specified department" do
        dept = create(:escalated_department)
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "assign_to_department_id" => dept.id })

        described_class.evaluate_ticket(ticket)
        ticket.reload
        expect(ticket.department_id).to eq(dept.id)
      end

      it "does nothing if department does not exist" do
        ticket = create(:escalated_ticket, status: :open, priority: :high, department: nil)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "assign_to_department_id" => 999999 })

        described_class.evaluate_ticket(ticket)
        ticket.reload
        expect(ticket.department_id).to be_nil
      end
    end

    context "with add_tags action" do
      it "adds tags to the ticket (creates tags if needed)" do
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "add_tags" => ["escalated", "urgent-review"] })

        described_class.evaluate_ticket(ticket)
        ticket.reload

        tag_names = ticket.tags.map(&:name)
        expect(tag_names).to include("escalated", "urgent-review")
      end

      it "does not duplicate existing tags" do
        tag = create(:escalated_tag, name: "escalated", slug: "escalated")
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        ticket.tags << tag

        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "add_tags" => ["escalated"] })

        described_class.evaluate_ticket(ticket)
        ticket.reload

        expect(ticket.tags.where(name: "escalated").count).to eq(1)
      end
    end

    context "with add_internal_note action" do
      it "creates an internal system note" do
        ticket = create(:escalated_ticket, status: :open, priority: :high)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: { "add_internal_note" => "Auto-escalated due to SLA breach" })

        described_class.evaluate_ticket(ticket)

        note = ticket.replies.internal_notes.last
        expect(note).to be_present
        expect(note.body).to eq("Auto-escalated due to SLA breach")
        expect(note.is_internal).to be(true)
        expect(note.is_system).to be(true)
      end
    end

    context "with multiple actions" do
      it "executes all actions in a single transaction" do
        dept = create(:escalated_department)
        ticket = create(:escalated_ticket, status: :open, priority: :medium)
        create(:escalated_escalation_rule,
               conditions: { "status" => ["open"] },
               actions: {
                 "change_priority" => "critical",
                 "change_status" => "escalated",
                 "assign_to_agent_id" => agent.id,
                 "assign_to_department_id" => dept.id,
                 "add_tags" => ["escalated"],
                 "add_internal_note" => "Auto-escalated"
               })

        described_class.evaluate_ticket(ticket)
        ticket.reload

        expect(ticket.priority).to eq("critical")
        expect(ticket.status).to eq("escalated")
        expect(ticket.assigned_to).to eq(agent.id)
        expect(ticket.department_id).to eq(dept.id)
        expect(ticket.tags.map(&:name)).to include("escalated")
        expect(ticket.replies.internal_notes.last.body).to eq("Auto-escalated")
      end
    end

    it "logs a ticket_escalated activity" do
      ticket = create(:escalated_ticket, status: :open, priority: :high)
      rule = create(:escalated_escalation_rule,
                    conditions: { "status" => ["open"] },
                    actions: { "change_status" => "escalated" })

      described_class.evaluate_ticket(ticket)

      activity = ticket.activities.find_by(action: "ticket_escalated")
      expect(activity).to be_present
      expect(activity.details["rule_id"]).to eq(rule.id)
      expect(activity.details["rule_name"]).to eq(rule.name)
    end

    it "instruments an ActiveSupport notification" do
      ticket = create(:escalated_ticket, status: :open, priority: :high)
      create(:escalated_escalation_rule,
             conditions: { "status" => ["open"] },
             actions: { "change_status" => "escalated" })

      events = []
      ActiveSupport::Notifications.subscribe("escalated.ticket.escalated") do |event|
        events << event
      end

      described_class.evaluate_ticket(ticket)

      expect(events).not_to be_empty

      ActiveSupport::Notifications.unsubscribe("escalated.ticket.escalated")
    end
  end

  # ------------------------------------------------------------------ #
  # .evaluate_all
  # ------------------------------------------------------------------ #
  describe ".evaluate_all" do
    it "evaluates all open tickets against active rules" do
      create(:escalated_escalation_rule,
             conditions: { "status" => ["open"] },
             actions: { "change_status" => "escalated" })
      ticket1 = create(:escalated_ticket, status: :open, priority: :high)
      ticket2 = create(:escalated_ticket, status: :open, priority: :medium)
      _closed = create(:escalated_ticket, status: :closed)

      result = described_class.evaluate_all
      escalated_tickets = result.map { |r| r[:ticket] }

      expect(escalated_tickets).to include(ticket1, ticket2)
    end

    it "returns a list of escalated ticket-rule pairs" do
      rule = create(:escalated_escalation_rule,
                    conditions: { "status" => ["open"] },
                    actions: { "change_status" => "escalated" })
      create(:escalated_ticket, status: :open)

      result = described_class.evaluate_all

      expect(result.first[:ticket]).to be_a(Escalated::Ticket)
      expect(result.first[:rule]).to eq(rule)
    end

    it "applies only the first matching rule per ticket" do
      create(:escalated_escalation_rule,
             name: "Rule A",
             priority: 1,
             conditions: { "status" => ["open"] },
             actions: { "change_priority" => "high" })
      create(:escalated_escalation_rule,
             name: "Rule B",
             priority: 2,
             conditions: { "status" => ["open"] },
             actions: { "change_priority" => "critical" })
      ticket = create(:escalated_ticket, status: :open, priority: :low)

      described_class.evaluate_all
      ticket.reload

      # Should be "high" from Rule A, not "critical" from Rule B
      expect(ticket.priority).to eq("high")
    end
  end
end
