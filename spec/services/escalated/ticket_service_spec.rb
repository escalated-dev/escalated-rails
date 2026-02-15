require "rails_helper"

RSpec.describe Escalated::Services::TicketService do
  let(:user) { create(:user) }
  let(:agent) { create(:user, :agent) }
  let(:admin) { create(:user, :admin) }

  # Disable email notifications and webhooks for service tests
  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  # ------------------------------------------------------------------ #
  # .create
  # ------------------------------------------------------------------ #
  describe ".create" do
    let(:valid_params) do
      {
        subject: "Cannot login to my account",
        description: "I get an error when trying to login with my email.",
        requester: user,
        priority: :high
      }
    end

    it "creates a new ticket" do
      expect { described_class.create(valid_params) }
        .to change(Escalated::Ticket, :count).by(1)
    end

    it "returns the created ticket" do
      ticket = described_class.create(valid_params)
      expect(ticket).to be_a(Escalated::Ticket)
      expect(ticket).to be_persisted
    end

    it "sets the subject and description" do
      ticket = described_class.create(valid_params)
      expect(ticket.subject).to eq("Cannot login to my account")
      expect(ticket.description).to eq("I get an error when trying to login with my email.")
    end

    it "sets the requester" do
      ticket = described_class.create(valid_params)
      expect(ticket.requester).to eq(user)
    end

    it "sets the priority" do
      ticket = described_class.create(valid_params)
      expect(ticket.priority).to eq("high")
    end

    it "defaults to open status" do
      ticket = described_class.create(valid_params)
      expect(ticket.status).to eq("open")
    end

    it "generates a reference" do
      ticket = described_class.create(valid_params)
      expect(ticket.reference).to be_present
    end

    it "creates a ticket_created activity" do
      ticket = described_class.create(valid_params)
      activity = ticket.activities.last
      expect(activity.action).to eq("ticket_created")
    end

    context "with tags" do
      it "assigns tags to the ticket" do
        tag1 = create(:escalated_tag)
        tag2 = create(:escalated_tag)
        params = valid_params.merge(tag_ids: [tag1.id, tag2.id])

        ticket = described_class.create(params)
        expect(ticket.tags).to include(tag1, tag2)
      end
    end

    context "with department" do
      it "sets the department" do
        dept = create(:escalated_department)
        params = valid_params.merge(department_id: dept.id)

        ticket = described_class.create(params)
        expect(ticket.department_id).to eq(dept.id)
      end
    end

    context "with assignee" do
      it "sets the assigned agent" do
        params = valid_params.merge(assigned_to: agent.id)

        ticket = described_class.create(params)
        expect(ticket.assigned_to).to eq(agent.id)
      end
    end

    context "with default SLA policy" do
      it "attaches the default SLA policy when SLA is enabled" do
        policy = create(:escalated_sla_policy, :default)

        ticket = described_class.create(valid_params)
        ticket.reload

        expect(ticket.sla_policy_id).to eq(policy.id)
        expect(ticket.sla_first_response_due_at).to be_present
        expect(ticket.sla_resolution_due_at).to be_present
      end
    end
  end

  # ------------------------------------------------------------------ #
  # .update
  # ------------------------------------------------------------------ #
  describe ".update" do
    let(:ticket) { create(:escalated_ticket) }

    it "updates the ticket subject" do
      described_class.update(ticket, { subject: "Updated subject" }, actor: agent)
      ticket.reload
      expect(ticket.subject).to eq("Updated subject")
    end

    it "updates the ticket description" do
      described_class.update(ticket, { description: "Updated description" }, actor: agent)
      ticket.reload
      expect(ticket.description).to eq("Updated description")
    end

    it "logs an activity when changes are made" do
      described_class.update(ticket, { subject: "Updated subject" }, actor: agent)
      activity = ticket.activities.find_by(action: "ticket_updated")
      expect(activity).to be_present
    end

    it "does not log activity when no changes made" do
      original_subject = ticket.subject
      expect {
        described_class.update(ticket, { subject: original_subject }, actor: agent)
      }.not_to change { ticket.activities.where(action: "ticket_updated").count }
    end

    it "merges metadata" do
      ticket.update!(metadata: { "source" => "web" })
      described_class.update(ticket, { metadata: { "browser" => "chrome" } }, actor: agent)
      ticket.reload
      expect(ticket.metadata).to include("source" => "web", "browser" => "chrome")
    end
  end

  # ------------------------------------------------------------------ #
  # .reply
  # ------------------------------------------------------------------ #
  describe ".reply" do
    let(:ticket) { create(:escalated_ticket) }

    it "creates a reply on the ticket" do
      reply = described_class.reply(ticket, {
        body: "Thank you for your report.",
        author: agent,
        is_internal: false
      })

      expect(reply).to be_a(Escalated::Reply)
      expect(reply).to be_persisted
      expect(reply.body).to eq("Thank you for your report.")
    end

    it "creates a public reply by default" do
      reply = described_class.reply(ticket, {
        body: "Public response",
        author: agent
      })

      expect(reply.is_internal).to be(false)
    end

    it "creates an internal note when specified" do
      reply = described_class.reply(ticket, {
        body: "Internal note for team",
        author: agent,
        is_internal: true
      })

      expect(reply.is_internal).to be(true)
    end

    it "logs a reply_added activity for public replies" do
      described_class.reply(ticket, { body: "Reply", author: agent, is_internal: false })
      activity = ticket.activities.find_by(action: "reply_added")
      expect(activity).to be_present
    end

    it "logs an internal_note_added activity for internal notes" do
      described_class.reply(ticket, { body: "Note", author: agent, is_internal: true })
      activity = ticket.activities.find_by(action: "internal_note_added")
      expect(activity).to be_present
    end
  end

  # ------------------------------------------------------------------ #
  # .close
  # ------------------------------------------------------------------ #
  describe ".close" do
    let(:ticket) { create(:escalated_ticket, status: :open) }

    it "transitions ticket to closed status" do
      described_class.close(ticket, actor: agent)
      ticket.reload
      expect(ticket.status).to eq("closed")
    end

    it "sets the closed_at timestamp" do
      described_class.close(ticket, actor: agent)
      ticket.reload
      expect(ticket.closed_at).to be_present
    end

    it "logs a status_changed activity" do
      described_class.close(ticket, actor: agent)
      activity = ticket.activities.find_by(action: "status_changed")
      expect(activity).to be_present
      expect(activity.details["to"]).to eq("closed")
    end
  end

  # ------------------------------------------------------------------ #
  # .resolve
  # ------------------------------------------------------------------ #
  describe ".resolve" do
    let(:ticket) { create(:escalated_ticket, status: :in_progress) }

    it "transitions ticket to resolved status" do
      described_class.resolve(ticket, actor: agent)
      ticket.reload
      expect(ticket.status).to eq("resolved")
    end

    it "sets the resolved_at timestamp" do
      described_class.resolve(ticket, actor: agent)
      ticket.reload
      expect(ticket.resolved_at).to be_present
    end
  end

  # ------------------------------------------------------------------ #
  # .reopen
  # ------------------------------------------------------------------ #
  describe ".reopen" do
    let(:ticket) { create(:escalated_ticket, :closed) }

    it "transitions ticket to reopened status" do
      described_class.reopen(ticket, actor: agent)
      ticket.reload
      expect(ticket.status).to eq("reopened")
    end

    it "clears resolved_at and closed_at timestamps" do
      described_class.reopen(ticket, actor: agent)
      ticket.reload
      expect(ticket.resolved_at).to be_nil
      expect(ticket.closed_at).to be_nil
    end
  end

  # ------------------------------------------------------------------ #
  # .change_priority
  # ------------------------------------------------------------------ #
  describe ".change_priority" do
    let(:ticket) { create(:escalated_ticket, priority: :medium) }

    it "changes the ticket priority" do
      described_class.change_priority(ticket, :urgent, actor: agent)
      ticket.reload
      expect(ticket.priority).to eq("urgent")
    end

    it "logs a priority_changed activity" do
      described_class.change_priority(ticket, :urgent, actor: agent)
      activity = ticket.activities.find_by(action: "priority_changed")
      expect(activity).to be_present
      expect(activity.details["from"]).to eq("medium")
      expect(activity.details["to"]).to eq("urgent")
    end
  end

  # ------------------------------------------------------------------ #
  # .change_department
  # ------------------------------------------------------------------ #
  describe ".change_department" do
    let(:ticket) { create(:escalated_ticket) }
    let(:new_dept) { create(:escalated_department) }

    it "changes the ticket department" do
      described_class.change_department(ticket, new_dept, actor: agent)
      ticket.reload
      expect(ticket.department_id).to eq(new_dept.id)
    end

    it "logs a department_changed activity" do
      described_class.change_department(ticket, new_dept, actor: agent)
      activity = ticket.activities.find_by(action: "department_changed")
      expect(activity).to be_present
    end
  end

  # ------------------------------------------------------------------ #
  # .add_tags / .remove_tags
  # ------------------------------------------------------------------ #
  describe ".add_tags" do
    let(:ticket) { create(:escalated_ticket) }
    let(:tag1) { create(:escalated_tag) }
    let(:tag2) { create(:escalated_tag) }

    it "adds tags to the ticket" do
      described_class.add_tags(ticket, [tag1.id, tag2.id], actor: agent)
      expect(ticket.tags.reload).to include(tag1, tag2)
    end

    it "does not add duplicate tags" do
      ticket.tags << tag1
      described_class.add_tags(ticket, [tag1.id, tag2.id], actor: agent)
      expect(ticket.tags.where(id: tag1.id).count).to eq(1)
    end

    it "logs a tags_added activity" do
      described_class.add_tags(ticket, [tag1.id], actor: agent)
      activity = ticket.activities.find_by(action: "tags_added")
      expect(activity).to be_present
    end
  end

  describe ".remove_tags" do
    let(:ticket) { create(:escalated_ticket) }
    let(:tag1) { create(:escalated_tag) }
    let(:tag2) { create(:escalated_tag) }

    before do
      ticket.tags << tag1
      ticket.tags << tag2
    end

    it "removes specified tags from the ticket" do
      described_class.remove_tags(ticket, [tag1.id], actor: agent)
      expect(ticket.tags.reload).not_to include(tag1)
      expect(ticket.tags.reload).to include(tag2)
    end

    it "logs a tags_removed activity" do
      described_class.remove_tags(ticket, [tag1.id], actor: agent)
      activity = ticket.activities.find_by(action: "tags_removed")
      expect(activity).to be_present
    end
  end

  # ------------------------------------------------------------------ #
  # .find / .list
  # ------------------------------------------------------------------ #
  describe ".find" do
    it "returns the ticket by ID" do
      ticket = create(:escalated_ticket)
      found = described_class.find(ticket.id)
      expect(found).to eq(ticket)
    end

    it "raises ActiveRecord::RecordNotFound for non-existent ID" do
      expect { described_class.find(999999) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".list" do
    let!(:open_ticket) { create(:escalated_ticket, status: :open, priority: :high) }
    let!(:closed_ticket) { create(:escalated_ticket, status: :closed, priority: :low) }

    it "returns all tickets without filters" do
      result = described_class.list
      expect(result).to include(open_ticket, closed_ticket)
    end

    it "filters by status" do
      result = described_class.list(status: :open)
      expect(result).to include(open_ticket)
      expect(result).not_to include(closed_ticket)
    end

    it "filters by priority" do
      result = described_class.list(priority: :high)
      expect(result).to include(open_ticket)
      expect(result).not_to include(closed_ticket)
    end

    it "searches by term" do
      result = described_class.list(search: open_ticket.subject[0..10])
      expect(result).to include(open_ticket)
    end

    it "orders by created_at descending by default" do
      result = described_class.list
      expect(result.first).to eq(closed_ticket) # created second, so more recent
    end
  end
end
