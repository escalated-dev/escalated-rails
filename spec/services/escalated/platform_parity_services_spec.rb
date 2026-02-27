require "rails_helper"

# ============================================================================ #
# Platform Parity Services — Comprehensive Specs
#
# Covers: BusinessHoursCalculator, TicketMergeService, SkillRoutingService,
#         CapacityService, WebhookDispatcher, AutomationRunner,
#         TwoFactorService, SsoService, ReportingService
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# 1. BusinessHoursCalculator
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::BusinessHoursCalculator do
  subject(:calculator) { described_class.new }

  # Disable notifications for service tests
  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  let(:schedule) do
    create(:escalated_business_schedule, timezone: "UTC", schedule: {
      "monday" => { "start" => "09:00", "end" => "17:00" },
      "tuesday" => { "start" => "09:00", "end" => "17:00" },
      "wednesday" => { "start" => "09:00", "end" => "17:00" },
      "thursday" => { "start" => "09:00", "end" => "17:00" },
      "friday" => { "start" => "09:00", "end" => "17:00" },
      "saturday" => nil,
      "sunday" => nil
    })
  end

  # ------------------------------------------------------------------ #
  # #within_business_hours?
  # ------------------------------------------------------------------ #
  describe "#within_business_hours?" do
    it "returns true during business hours on a working day" do
      # A Monday at 10:00 UTC
      monday_10am = Time.zone.parse("2026-03-02 10:00:00 UTC") # Monday
      expect(calculator.within_business_hours?(monday_10am, schedule)).to be(true)
    end

    it "returns false outside business hours on a working day" do
      monday_7am = Time.zone.parse("2026-03-02 07:00:00 UTC") # Monday 7am
      expect(calculator.within_business_hours?(monday_7am, schedule)).to be(false)
    end

    it "returns false at exactly the end time" do
      monday_5pm = Time.zone.parse("2026-03-02 17:00:00 UTC") # Monday 5pm
      expect(calculator.within_business_hours?(monday_5pm, schedule)).to be(false)
    end

    it "returns true at exactly the start time" do
      monday_9am = Time.zone.parse("2026-03-02 09:00:00 UTC") # Monday 9am
      expect(calculator.within_business_hours?(monday_9am, schedule)).to be(true)
    end

    it "returns false on a non-working day" do
      saturday_noon = Time.zone.parse("2026-02-28 12:00:00 UTC") # Saturday
      expect(calculator.within_business_hours?(saturday_noon, schedule)).to be(false)
    end

    context "with holidays" do
      it "returns false on a non-recurring holiday" do
        create(:escalated_holiday,
               schedule: schedule,
               name: "Company Day",
               date: Date.parse("2026-03-02"),
               recurring: false)

        monday_10am = Time.zone.parse("2026-03-02 10:00:00 UTC")
        expect(calculator.within_business_hours?(monday_10am, schedule.reload)).to be(false)
      end

      it "returns false on a recurring holiday matching month and day" do
        create(:escalated_holiday,
               schedule: schedule,
               name: "New Year",
               date: Date.parse("2025-01-01"),
               recurring: true)

        new_year_2026 = Time.zone.parse("2026-01-01 12:00:00 UTC") # Thursday
        # Need to also have Thursday in the schedule for this to matter
        schedule.update!(schedule: schedule.schedule.merge("thursday" => { "start" => "09:00", "end" => "17:00" }))
        expect(calculator.within_business_hours?(new_year_2026, schedule.reload)).to be(false)
      end
    end

    context "with different timezones" do
      let(:eastern_schedule) do
        create(:escalated_business_schedule, timezone: "America/New_York", schedule: {
          "monday" => { "start" => "09:00", "end" => "17:00" },
          "tuesday" => { "start" => "09:00", "end" => "17:00" },
          "wednesday" => { "start" => "09:00", "end" => "17:00" },
          "thursday" => { "start" => "09:00", "end" => "17:00" },
          "friday" => { "start" => "09:00", "end" => "17:00" },
          "saturday" => nil,
          "sunday" => nil
        })
      end

      it "converts the datetime to the schedule timezone" do
        # 14:00 UTC = 09:00 EST (within business hours)
        utc_2pm = Time.zone.parse("2026-03-02 14:00:00 UTC") # Monday
        expect(calculator.within_business_hours?(utc_2pm, eastern_schedule)).to be(true)
      end

      it "returns false when UTC time is in hours but local time is not" do
        # 12:00 UTC = 07:00 EST (before business hours)
        utc_noon = Time.zone.parse("2026-03-02 12:00:00 UTC") # Monday
        expect(calculator.within_business_hours?(utc_noon, eastern_schedule)).to be(false)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # #add_business_hours
  # ------------------------------------------------------------------ #
  describe "#add_business_hours" do
    it "adds hours within the same business day" do
      monday_10am = Time.zone.parse("2026-03-02 10:00:00 UTC")
      result = calculator.add_business_hours(monday_10am, 2, schedule)

      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-02 12:00:00 UTC"))
    end

    it "rolls over to the next business day when hours exceed remaining time" do
      monday_4pm = Time.zone.parse("2026-03-02 16:00:00 UTC")
      result = calculator.add_business_hours(monday_4pm, 2, schedule)

      # 1 hour left on Monday, 1 hour needed on Tuesday => Tuesday 10:00
      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-03 10:00:00 UTC"))
    end

    it "skips non-working days" do
      friday_4pm = Time.zone.parse("2026-02-27 16:00:00 UTC") # Friday
      result = calculator.add_business_hours(friday_4pm, 2, schedule)

      # 1 hour left on Friday, skip Saturday and Sunday, 1 hour on Monday => Monday 10:00
      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-02 10:00:00 UTC"))
    end

    it "handles starting before business hours" do
      monday_7am = Time.zone.parse("2026-03-02 07:00:00 UTC")
      result = calculator.add_business_hours(monday_7am, 1, schedule)

      # Should start at 09:00 and add 1 hour => 10:00
      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-02 10:00:00 UTC"))
    end

    it "handles starting after business hours" do
      monday_6pm = Time.zone.parse("2026-03-02 18:00:00 UTC")
      result = calculator.add_business_hours(monday_6pm, 1, schedule)

      # Should skip to Tuesday 09:00, add 1 hour => 10:00
      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-03 10:00:00 UTC"))
    end

    it "handles multiple days worth of hours" do
      monday_9am = Time.zone.parse("2026-03-02 09:00:00 UTC")
      result = calculator.add_business_hours(monday_9am, 16, schedule)

      # 8 hours Monday, 8 hours Tuesday => Tuesday 17:00
      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-03 17:00:00 UTC"))
    end

    it "skips holidays" do
      create(:escalated_holiday,
             schedule: schedule,
             name: "Holiday",
             date: Date.parse("2026-03-03"),
             recurring: false)

      monday_4pm = Time.zone.parse("2026-03-02 16:00:00 UTC")
      result = calculator.add_business_hours(monday_4pm, 2, schedule.reload)

      # 1 hour Monday, skip Tuesday (holiday), 1 hour Wednesday => Wednesday 10:00
      expect(result).to be_within(1.minute).of(Time.zone.parse("2026-03-04 10:00:00 UTC"))
    end

    it "returns UTC time" do
      monday_10am = Time.zone.parse("2026-03-02 10:00:00 UTC")
      result = calculator.add_business_hours(monday_10am, 1, schedule)

      expect(result.utc?).to be(true)
    end
  end
end

# ---------------------------------------------------------------------------- #
# 2. TicketMergeService
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::TicketMergeService do
  subject(:service) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  let(:agent) { create(:user, :agent) }
  let(:source) { create(:escalated_ticket, status: :open) }
  let(:target) { create(:escalated_ticket, status: :open) }

  # ------------------------------------------------------------------ #
  # #merge
  # ------------------------------------------------------------------ #
  describe "#merge" do
    it "moves replies from source to target" do
      reply1 = create(:escalated_reply, ticket: source)
      reply2 = create(:escalated_reply, ticket: source)

      service.merge(source, target, merged_by_user_id: agent.id)

      expect(reply1.reload.ticket_id).to eq(target.id)
      expect(reply2.reload.ticket_id).to eq(target.id)
    end

    it "creates a system note on the target ticket" do
      service.merge(source, target, merged_by_user_id: agent.id)

      note = target.replies.find_by("body LIKE ?", "%merged into this ticket%")
      expect(note).to be_present
      expect(note.is_internal).to be(true)
      expect(note.is_system).to be(true)
      expect(note.body).to include(source.reference)
    end

    it "creates a system note on the source ticket" do
      service.merge(source, target, merged_by_user_id: agent.id)

      note = source.replies.find_by("body LIKE ?", "%was merged into%")
      expect(note).to be_present
      expect(note.is_internal).to be(true)
      expect(note.is_system).to be(true)
      expect(note.body).to include(target.reference)
    end

    it "closes the source ticket" do
      service.merge(source, target, merged_by_user_id: agent.id)
      source.reload

      expect(source.status).to eq("closed")
    end

    it "sets merged_into on the source ticket" do
      service.merge(source, target, merged_by_user_id: agent.id)
      source.reload

      expect(source.merged_into_id).to eq(target.id)
    end

    it "wraps everything in a transaction" do
      # If the source.update! fails, replies should not be moved
      allow(source).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        service.merge(source, target, merged_by_user_id: agent.id) rescue nil
      }.not_to change { Escalated::Reply.where(ticket: target).count }
    end

    context "without merged_by_user_id" do
      it "still creates system notes" do
        service.merge(source, target)

        note = target.replies.find_by("body LIKE ?", "%merged into this ticket%")
        expect(note).to be_present
        expect(note.is_system).to be(true)
      end
    end

    context "when source has no replies" do
      it "still creates system notes and closes source" do
        service.merge(source, target, merged_by_user_id: agent.id)

        expect(source.reload.status).to eq("closed")
        expect(target.replies.where("body LIKE ?", "%merged into this ticket%")).to exist
        expect(source.replies.where("body LIKE ?", "%was merged into%")).to exist
      end
    end
  end
end

# ---------------------------------------------------------------------------- #
# 3. SkillRoutingService
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::SkillRoutingService do
  subject(:service) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
    allow(Escalated.configuration).to receive(:user_class).and_return("User")
  end

  # ------------------------------------------------------------------ #
  # #find_matching_agents
  # ------------------------------------------------------------------ #
  describe "#find_matching_agents" do
    context "when ticket has no tags" do
      it "returns an empty relation" do
        ticket = create(:escalated_ticket)

        result = service.find_matching_agents(ticket)

        expect(result).to be_empty
      end
    end

    context "when no skills match the ticket tags" do
      it "returns an empty relation" do
        tag = create(:escalated_tag, name: "billing")
        ticket = create(:escalated_ticket)
        ticket.tags << tag

        # No skill named "billing" exists
        result = service.find_matching_agents(ticket)

        expect(result).to be_empty
      end
    end

    context "when skills exist but no agents have them" do
      it "returns an empty relation" do
        tag = create(:escalated_tag, name: "networking")
        skill = create(:escalated_skill, name: "networking")
        ticket = create(:escalated_ticket)
        ticket.tags << tag

        # Skill exists but no AgentSkill records
        result = service.find_matching_agents(ticket)

        expect(result).to be_empty
      end
    end

    context "when matching agents exist" do
      it "returns agents with matching skills" do
        agent = create(:user, :agent)
        tag = create(:escalated_tag, name: "ruby")
        skill = create(:escalated_skill, name: "ruby")
        Escalated::AgentSkill.create!(user_id: agent.id, skill_id: skill.id)

        ticket = create(:escalated_ticket)
        ticket.tags << tag

        result = service.find_matching_agents(ticket)

        expect(result.map(&:id)).to include(agent.id)
      end
    end
  end
end

# ---------------------------------------------------------------------------- #
# 4. CapacityService
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::CapacityService do
  subject(:service) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  let(:agent) { create(:user, :agent) }

  # ------------------------------------------------------------------ #
  # #can_accept_ticket?
  # ------------------------------------------------------------------ #
  describe "#can_accept_ticket?" do
    it "returns true when agent has no existing capacity record" do
      expect(service.can_accept_ticket?(agent.id)).to be(true)
    end

    it "creates a capacity record with defaults if none exists" do
      expect {
        service.can_accept_ticket?(agent.id)
      }.to change(Escalated::AgentCapacity, :count).by(1)

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id)
      expect(capacity.max_concurrent).to eq(10)
      expect(capacity.current_count).to eq(0)
    end

    it "returns true when agent has capacity" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "default", max_concurrent: 5, current_count: 3)

      expect(service.can_accept_ticket?(agent.id)).to be(true)
    end

    it "returns false when agent is at capacity" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "default", max_concurrent: 5, current_count: 5)

      expect(service.can_accept_ticket?(agent.id)).to be(false)
    end

    it "respects channel parameter" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "email", max_concurrent: 2, current_count: 2)

      expect(service.can_accept_ticket?(agent.id, channel: "email")).to be(false)
      expect(service.can_accept_ticket?(agent.id, channel: "chat")).to be(true)
    end
  end

  # ------------------------------------------------------------------ #
  # #increment_load
  # ------------------------------------------------------------------ #
  describe "#increment_load" do
    it "increments the current_count" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "default", max_concurrent: 10, current_count: 3)

      service.increment_load(agent.id)

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id, channel: "default")
      expect(capacity.current_count).to eq(4)
    end

    it "creates a capacity record if none exists" do
      expect {
        service.increment_load(agent.id)
      }.to change(Escalated::AgentCapacity, :count).by(1)

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id)
      expect(capacity.current_count).to eq(1)
    end

    it "respects channel parameter" do
      service.increment_load(agent.id, channel: "chat")

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id, channel: "chat")
      expect(capacity).to be_present
      expect(capacity.current_count).to eq(1)
    end
  end

  # ------------------------------------------------------------------ #
  # #decrement_load
  # ------------------------------------------------------------------ #
  describe "#decrement_load" do
    it "decrements the current_count" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "default", max_concurrent: 10, current_count: 3)

      service.decrement_load(agent.id)

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id, channel: "default")
      expect(capacity.current_count).to eq(2)
    end

    it "does not decrement below zero" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "default", max_concurrent: 10, current_count: 0)

      service.decrement_load(agent.id)

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id, channel: "default")
      expect(capacity.current_count).to eq(0)
    end

    it "creates a capacity record if none exists and does not decrement" do
      expect {
        service.decrement_load(agent.id)
      }.to change(Escalated::AgentCapacity, :count).by(1)

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id)
      expect(capacity.current_count).to eq(0)
    end

    it "respects channel parameter" do
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "chat", max_concurrent: 10, current_count: 5)

      service.decrement_load(agent.id, channel: "chat")

      capacity = Escalated::AgentCapacity.find_by(user_id: agent.id, channel: "chat")
      expect(capacity.current_count).to eq(4)
    end
  end

  # ------------------------------------------------------------------ #
  # #all_capacities
  # ------------------------------------------------------------------ #
  describe "#all_capacities" do
    it "returns all capacity records" do
      agent2 = create(:user, :agent)
      Escalated::AgentCapacity.create!(user_id: agent.id, channel: "default", max_concurrent: 10, current_count: 0)
      Escalated::AgentCapacity.create!(user_id: agent2.id, channel: "default", max_concurrent: 5, current_count: 3)

      result = service.all_capacities

      expect(result.count).to eq(2)
    end

    it "returns an empty relation when no capacity records exist" do
      result = service.all_capacities

      expect(result).to be_empty
    end
  end
end

# ---------------------------------------------------------------------------- #
# 5. WebhookDispatcher
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::WebhookDispatcher do
  subject(:dispatcher) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)

    # Stub HTTP requests by default
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
  end

  let(:mock_http) do
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(mock_response)
    http
  end

  let(:mock_response) do
    response = instance_double(Net::HTTPResponse)
    allow(response).to receive(:code).and_return("200")
    allow(response).to receive(:body).and_return('{"ok":true}')
    response
  end

  # ------------------------------------------------------------------ #
  # #dispatch
  # ------------------------------------------------------------------ #
  describe "#dispatch" do
    it "sends webhook to active webhooks subscribed to the event" do
      webhook = Escalated::Webhook.create!(url: "https://example.com/hook", events: ["ticket.created"], active: true)

      expect {
        dispatcher.dispatch("ticket.created", { ticket_id: 1 })
      }.to change(Escalated::WebhookDelivery, :count).by(1)
    end

    it "does not send webhook to inactive webhooks" do
      Escalated::Webhook.create!(url: "https://example.com/hook", events: ["ticket.created"], active: false)

      expect {
        dispatcher.dispatch("ticket.created", { ticket_id: 1 })
      }.not_to change(Escalated::WebhookDelivery, :count)
    end

    it "does not send webhook for unsubscribed events" do
      Escalated::Webhook.create!(url: "https://example.com/hook", events: ["ticket.updated"], active: true)

      expect {
        dispatcher.dispatch("ticket.created", { ticket_id: 1 })
      }.not_to change(Escalated::WebhookDelivery, :count)
    end

    it "sends to multiple subscribed webhooks" do
      Escalated::Webhook.create!(url: "https://example.com/hook1", events: ["ticket.created"], active: true)
      Escalated::Webhook.create!(url: "https://example.com/hook2", events: ["ticket.created"], active: true)

      expect {
        dispatcher.dispatch("ticket.created", { ticket_id: 1 })
      }.to change(Escalated::WebhookDelivery, :count).by(2)
    end
  end

  # ------------------------------------------------------------------ #
  # #send_webhook
  # ------------------------------------------------------------------ #
  describe "#send_webhook" do
    let(:webhook) { Escalated::Webhook.create!(url: "https://example.com/hook", events: ["ticket.created"], active: true, secret: "test-secret") }

    it "creates a WebhookDelivery record" do
      expect {
        dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })
      }.to change(Escalated::WebhookDelivery, :count).by(1)
    end

    it "records the response code on success" do
      dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })

      delivery = Escalated::WebhookDelivery.last
      expect(delivery.response_code).to eq(200)
    end

    it "records the delivered_at timestamp on success" do
      dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })

      delivery = Escalated::WebhookDelivery.last
      expect(delivery.delivered_at).to be_present
    end

    it "records the response body" do
      dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })

      delivery = Escalated::WebhookDelivery.last
      expect(delivery.response_body).to eq('{"ok":true}')
    end

    it "includes HMAC signature when secret is present" do
      expect(mock_http).to receive(:request) do |request|
        expect(request["X-Escalated-Signature"]).to be_present
        mock_response
      end

      dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })
    end

    it "includes the event header" do
      expect(mock_http).to receive(:request) do |request|
        expect(request["X-Escalated-Event"]).to eq("ticket.created")
        mock_response
      end

      dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })
    end

    context "without a secret" do
      let(:webhook_no_secret) { Escalated::Webhook.create!(url: "https://example.com/hook", events: ["ticket.created"], active: true, secret: nil) }

      it "does not include signature header" do
        expect(mock_http).to receive(:request) do |request|
          expect(request["X-Escalated-Signature"]).to be_nil
          mock_response
        end

        dispatcher.send_webhook(webhook_no_secret, "ticket.created", { ticket_id: 1 })
      end
    end

    context "when the request fails" do
      before do
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED, "Connection refused")
      end

      it "records the error in response_body" do
        dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })

        delivery = Escalated::WebhookDelivery.first
        expect(delivery.response_code).to eq(0)
        expect(delivery.response_body).to include("Connection refused")
      end

      it "retries up to MAX_ATTEMPTS times" do
        expect {
          dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })
        }.to change(Escalated::WebhookDelivery, :count).by(3)
      end
    end

    context "when response is non-2xx" do
      let(:failed_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("500")
        allow(response).to receive(:body).and_return('{"error":"Internal Server Error"}')
        response
      end

      before do
        allow(mock_http).to receive(:request).and_return(failed_response)
      end

      it "retries on non-2xx responses" do
        expect {
          dispatcher.send_webhook(webhook, "ticket.created", { ticket_id: 1 })
        }.to change(Escalated::WebhookDelivery, :count).by(3)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # #retry_delivery
  # ------------------------------------------------------------------ #
  describe "#retry_delivery" do
    it "re-dispatches the delivery's event and payload" do
      webhook = Escalated::Webhook.create!(url: "https://example.com/hook", events: ["ticket.created"], active: true)
      delivery = Escalated::WebhookDelivery.create!(
        webhook: webhook,
        event: "ticket.created",
        payload: { ticket_id: 42 },
        response_code: 500,
        attempts: 1
      )

      expect {
        dispatcher.retry_delivery(delivery)
      }.to change(Escalated::WebhookDelivery, :count).by(1)
    end

    it "does nothing if the delivery has no webhook" do
      delivery = instance_double(Escalated::WebhookDelivery, webhook: nil)

      expect {
        dispatcher.retry_delivery(delivery)
      }.not_to change(Escalated::WebhookDelivery, :count)
    end
  end
end

# ---------------------------------------------------------------------------- #
# 6. AutomationRunner
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::AutomationRunner do
  subject(:runner) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  # ------------------------------------------------------------------ #
  # #run
  # ------------------------------------------------------------------ #
  describe "#run" do
    it "returns 0 when no active automations exist" do
      expect(runner.run).to eq(0)
    end

    it "skips inactive automations" do
      Escalated::Automation.create!(
        name: "Inactive",
        conditions: [{ "field" => "status", "value" => "open" }],
        actions: [{ "type" => "change_priority", "value" => "high" }],
        active: false
      )
      create(:escalated_ticket, status: :open)

      expect(runner.run).to eq(0)
    end

    context "with status condition" do
      it "matches tickets with the specified status" do
        Escalated::Automation.create!(
          name: "Close stale",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "change_priority", "value" => "high" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("high")
      end

      it "does not match tickets with different status" do
        Escalated::Automation.create!(
          name: "Test",
          conditions: [{ "field" => "status", "value" => "escalated" }],
          actions: [{ "type" => "change_priority", "value" => "high" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("low")
      end
    end

    context "with priority condition" do
      it "matches tickets with the specified priority" do
        Escalated::Automation.create!(
          name: "Escalate urgent",
          conditions: [{ "field" => "priority", "value" => "urgent" }],
          actions: [{ "type" => "change_status", "value" => "escalated" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :urgent)

        runner.run
        ticket.reload

        expect(ticket.status).to eq("escalated")
      end
    end

    context "with hours_since_created condition" do
      it "matches tickets created more than N hours ago" do
        Escalated::Automation.create!(
          name: "Stale tickets",
          conditions: [{ "field" => "hours_since_created", "value" => "24" }],
          actions: [{ "type" => "change_priority", "value" => "high" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low, created_at: 48.hours.ago)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("high")
      end

      it "does not match recent tickets" do
        Escalated::Automation.create!(
          name: "Stale tickets",
          conditions: [{ "field" => "hours_since_created", "value" => "24" }],
          actions: [{ "type" => "change_priority", "value" => "high" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low, created_at: 1.hour.ago)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("low")
      end
    end

    context "with hours_since_updated condition" do
      it "matches tickets not updated for N hours" do
        Escalated::Automation.create!(
          name: "Stale tickets",
          conditions: [{ "field" => "hours_since_updated", "value" => "12" }],
          actions: [{ "type" => "change_priority", "value" => "urgent" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low)
        ticket.update_column(:updated_at, 24.hours.ago)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("urgent")
      end
    end

    context "with assigned condition" do
      it "matches unassigned tickets when value is 'unassigned'" do
        Escalated::Automation.create!(
          name: "Flag unassigned",
          conditions: [{ "field" => "assigned", "value" => "unassigned" }],
          actions: [{ "type" => "change_priority", "value" => "high" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low, assigned_to: nil)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("high")
      end

      it "matches assigned tickets when value is not 'unassigned'" do
        agent = create(:user, :agent)
        Escalated::Automation.create!(
          name: "Flag assigned",
          conditions: [{ "field" => "assigned", "value" => "assigned" }],
          actions: [{ "type" => "change_priority", "value" => "high" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low, assigned_to: agent.id)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("high")
      end
    end

    context "with change_status action" do
      it "changes the ticket status" do
        Escalated::Automation.create!(
          name: "Auto escalate",
          conditions: [{ "field" => "priority", "value" => "critical" }],
          actions: [{ "type" => "change_status", "value" => "escalated" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :critical)

        runner.run
        ticket.reload

        expect(ticket.status).to eq("escalated")
      end
    end

    context "with assign action" do
      it "assigns the ticket to the specified agent" do
        agent = create(:user, :agent)
        Escalated::Automation.create!(
          name: "Auto assign",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "assign", "value" => agent.id.to_s }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, assigned_to: nil)

        runner.run
        ticket.reload

        expect(ticket.assigned_to).to eq(agent.id)
      end
    end

    context "with add_tag action" do
      it "adds the specified tag to the ticket" do
        tag = create(:escalated_tag, name: "auto-tagged")
        Escalated::Automation.create!(
          name: "Auto tag",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "add_tag", "value" => "auto-tagged" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open)

        runner.run

        expect(ticket.tags.reload).to include(tag)
      end

      it "does not duplicate existing tags" do
        tag = create(:escalated_tag, name: "auto-tagged")
        Escalated::Automation.create!(
          name: "Auto tag",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "add_tag", "value" => "auto-tagged" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open)
        ticket.tags << tag

        runner.run

        expect(ticket.tags.where(name: "auto-tagged").count).to eq(1)
      end

      it "does nothing when the tag does not exist" do
        Escalated::Automation.create!(
          name: "Auto tag",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "add_tag", "value" => "nonexistent-tag" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open)

        expect {
          runner.run
        }.not_to change { ticket.tags.count }
      end
    end

    context "with change_priority action" do
      it "changes the ticket priority" do
        Escalated::Automation.create!(
          name: "Bump priority",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "change_priority", "value" => "urgent" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open, priority: :low)

        runner.run
        ticket.reload

        expect(ticket.priority).to eq("urgent")
      end
    end

    context "with add_note action" do
      it "creates an internal note on the ticket" do
        Escalated::Automation.create!(
          name: "Add note",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "add_note", "value" => "Automated note added." }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open)

        runner.run

        note = ticket.replies.find_by(body: "Automated note added.")
        expect(note).to be_present
        expect(note.is_internal).to be(true)
        expect(note.is_system).to be(true)
      end
    end

    it "updates last_run_at on the automation" do
      automation = Escalated::Automation.create!(
        name: "Test",
        conditions: [{ "field" => "status", "value" => "open" }],
        actions: [{ "type" => "change_priority", "value" => "high" }],
        active: true,
        position: 0,
        last_run_at: nil
      )
      create(:escalated_ticket, status: :open)

      runner.run
      automation.reload

      expect(automation.last_run_at).to be_present
    end

    it "returns the total number of affected tickets" do
      Escalated::Automation.create!(
        name: "Test",
        conditions: [{ "field" => "status", "value" => "open" }],
        actions: [{ "type" => "change_priority", "value" => "high" }],
        active: true,
        position: 0
      )
      create(:escalated_ticket, status: :open, priority: :low)
      create(:escalated_ticket, status: :open, priority: :medium)
      create(:escalated_ticket, :closed) # Should not be matched

      expect(runner.run).to eq(2)
    end

    it "excludes closed and resolved tickets from matching" do
      Escalated::Automation.create!(
        name: "Test",
        conditions: [],
        actions: [{ "type" => "change_priority", "value" => "high" }],
        active: true,
        position: 0
      )
      closed = create(:escalated_ticket, :closed)
      resolved = create(:escalated_ticket, :resolved)

      runner.run
      closed.reload
      resolved.reload

      expect(closed.priority).not_to eq("high")
      expect(resolved.priority).not_to eq("high")
    end

    context "when an action raises an error" do
      it "logs the error and continues" do
        Escalated::Automation.create!(
          name: "Bad automation",
          conditions: [{ "field" => "status", "value" => "open" }],
          actions: [{ "type" => "change_status", "value" => "nonexistent_status" }],
          active: true,
          position: 0
        )
        ticket = create(:escalated_ticket, status: :open)

        expect(Rails.logger).to receive(:warn).with(/Escalated automation action failed/)

        runner.run
      end
    end

    context "with multiple conditions" do
      it "applies all conditions with AND logic" do
        Escalated::Automation.create!(
          name: "Multi-condition",
          conditions: [
            { "field" => "status", "value" => "open" },
            { "field" => "priority", "value" => "urgent" }
          ],
          actions: [{ "type" => "change_status", "value" => "escalated" }],
          active: true,
          position: 0
        )
        matching = create(:escalated_ticket, status: :open, priority: :urgent)
        non_matching = create(:escalated_ticket, status: :open, priority: :low)

        runner.run
        matching.reload
        non_matching.reload

        expect(matching.status).to eq("escalated")
        expect(non_matching.status).to eq("open")
      end
    end
  end
end

# ---------------------------------------------------------------------------- #
# 7. TwoFactorService
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::TwoFactorService do
  subject(:service) { described_class.new }

  # ------------------------------------------------------------------ #
  # #generate_secret
  # ------------------------------------------------------------------ #
  describe "#generate_secret" do
    it "returns a 16-character string" do
      secret = service.generate_secret

      expect(secret.length).to eq(16)
    end

    it "only contains valid Base32 characters" do
      secret = service.generate_secret

      expect(secret).to match(/\A[A-Z2-7]+\z/)
    end

    it "generates unique secrets" do
      secrets = 10.times.map { service.generate_secret }

      expect(secrets.uniq.length).to eq(10)
    end
  end

  # ------------------------------------------------------------------ #
  # #generate_qr_uri
  # ------------------------------------------------------------------ #
  describe "#generate_qr_uri" do
    it "returns an otpauth URI" do
      uri = service.generate_qr_uri("JBSWY3DPEHPK3PXP", "user@example.com")

      expect(uri).to start_with("otpauth://totp/")
    end

    it "includes the email in the URI" do
      uri = service.generate_qr_uri("JBSWY3DPEHPK3PXP", "user@example.com")

      expect(uri).to include("user@example.com")
    end

    it "includes the secret in the URI" do
      uri = service.generate_qr_uri("JBSWY3DPEHPK3PXP", "user@example.com")

      expect(uri).to include("secret=JBSWY3DPEHPK3PXP")
    end

    it "includes SHA1 algorithm" do
      uri = service.generate_qr_uri("JBSWY3DPEHPK3PXP", "user@example.com")

      expect(uri).to include("algorithm=SHA1")
    end

    it "includes 6 digits" do
      uri = service.generate_qr_uri("JBSWY3DPEHPK3PXP", "user@example.com")

      expect(uri).to include("digits=6")
    end

    it "includes 30-second period" do
      uri = service.generate_qr_uri("JBSWY3DPEHPK3PXP", "user@example.com")

      expect(uri).to include("period=30")
    end
  end

  # ------------------------------------------------------------------ #
  # #verify
  # ------------------------------------------------------------------ #
  describe "#verify" do
    it "verifies a correct TOTP code for the current time step" do
      secret = service.generate_secret
      # Generate the correct code using the service's own logic
      current_step = Time.now.to_i / 30
      correct_code = service.send(:generate_totp, secret, current_step)

      expect(service.verify(secret, correct_code)).to be(true)
    end

    it "accepts codes from the previous time step (drift tolerance)" do
      secret = service.generate_secret
      previous_step = (Time.now.to_i / 30) - 1
      previous_code = service.send(:generate_totp, secret, previous_step)

      expect(service.verify(secret, previous_code)).to be(true)
    end

    it "accepts codes from the next time step (drift tolerance)" do
      secret = service.generate_secret
      next_step = (Time.now.to_i / 30) + 1
      next_code = service.send(:generate_totp, secret, next_step)

      expect(service.verify(secret, next_code)).to be(true)
    end

    it "rejects an incorrect code" do
      secret = service.generate_secret

      expect(service.verify(secret, "000000")).to be(false)
    end

    it "rejects a code from a far-off time step" do
      secret = service.generate_secret
      far_step = (Time.now.to_i / 30) + 100
      far_code = service.send(:generate_totp, secret, far_step)

      expect(service.verify(secret, far_code)).to be(false)
    end
  end

  # ------------------------------------------------------------------ #
  # #generate_recovery_codes
  # ------------------------------------------------------------------ #
  describe "#generate_recovery_codes" do
    it "returns 8 recovery codes" do
      codes = service.generate_recovery_codes

      expect(codes.length).to eq(8)
    end

    it "returns codes in the format XXXX-XXXX (hex)" do
      codes = service.generate_recovery_codes

      codes.each do |code|
        expect(code).to match(/\A[A-F0-9]{8}-[A-F0-9]{8}\z/)
      end
    end

    it "generates unique codes" do
      codes = service.generate_recovery_codes

      expect(codes.uniq.length).to eq(8)
    end
  end
end

# ---------------------------------------------------------------------------- #
# 8. SsoService
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::SsoService do
  subject(:service) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  # ------------------------------------------------------------------ #
  # #get_config
  # ------------------------------------------------------------------ #
  describe "#get_config" do
    it "returns all SSO configuration keys with defaults" do
      config = service.get_config

      expect(config).to include(
        "sso_provider" => "none",
        "sso_entity_id" => "",
        "sso_url" => "",
        "sso_certificate" => "",
        "sso_attr_email" => "email",
        "sso_attr_name" => "name",
        "sso_attr_role" => "role",
        "sso_jwt_secret" => "",
        "sso_jwt_algorithm" => "HS256"
      )
    end

    it "returns stored values when settings exist" do
      Escalated::EscalatedSetting.create!(key: "sso_provider", value: "saml")
      Escalated::EscalatedSetting.create!(key: "sso_url", value: "https://idp.example.com/sso")

      config = service.get_config

      expect(config["sso_provider"]).to eq("saml")
      expect(config["sso_url"]).to eq("https://idp.example.com/sso")
    end

    it "mixes stored values with defaults for missing keys" do
      Escalated::EscalatedSetting.create!(key: "sso_provider", value: "jwt")

      config = service.get_config

      expect(config["sso_provider"]).to eq("jwt")
      expect(config["sso_attr_email"]).to eq("email") # default
    end
  end

  # ------------------------------------------------------------------ #
  # #save_config
  # ------------------------------------------------------------------ #
  describe "#save_config" do
    it "creates settings for new keys" do
      expect {
        service.save_config("sso_provider" => "saml", "sso_url" => "https://idp.example.com")
      }.to change(Escalated::EscalatedSetting, :count).by(2)
    end

    it "updates existing settings" do
      Escalated::EscalatedSetting.create!(key: "sso_provider", value: "none")

      service.save_config("sso_provider" => "saml")

      expect(Escalated::EscalatedSetting.find_by(key: "sso_provider").value).to eq("saml")
    end

    it "ignores keys not in CONFIG_KEYS" do
      expect {
        service.save_config("unknown_key" => "value", "sso_provider" => "jwt")
      }.to change(Escalated::EscalatedSetting, :count).by(1)
    end

    it "only saves provided keys" do
      service.save_config("sso_provider" => "saml")

      expect(Escalated::EscalatedSetting.find_by(key: "sso_url")).to be_nil
    end
  end

  # ------------------------------------------------------------------ #
  # #enabled?
  # ------------------------------------------------------------------ #
  describe "#enabled?" do
    it "returns false when provider is 'none'" do
      expect(service.enabled?).to be(false)
    end

    it "returns false when no provider setting exists" do
      expect(service.enabled?).to be(false)
    end

    it "returns true when provider is set to something other than 'none'" do
      Escalated::EscalatedSetting.create!(key: "sso_provider", value: "saml")

      expect(service.enabled?).to be(true)
    end

    it "returns true when provider is 'jwt'" do
      Escalated::EscalatedSetting.create!(key: "sso_provider", value: "jwt")

      expect(service.enabled?).to be(true)
    end
  end

  # ------------------------------------------------------------------ #
  # #provider
  # ------------------------------------------------------------------ #
  describe "#provider" do
    it "returns 'none' by default" do
      expect(service.provider).to eq("none")
    end

    it "returns the stored provider value" do
      Escalated::EscalatedSetting.create!(key: "sso_provider", value: "saml")

      expect(service.provider).to eq("saml")
    end
  end
end

# ---------------------------------------------------------------------------- #
# 9. ReportingService
# ---------------------------------------------------------------------------- #
RSpec.describe Escalated::Services::ReportingService do
  subject(:service) { described_class.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
    allow(Escalated.configuration).to receive(:user_class).and_return("User")
  end

  let(:start_date) { 30.days.ago }
  let(:end_date) { Time.current }

  # ------------------------------------------------------------------ #
  # #ticket_volume_by_date
  # ------------------------------------------------------------------ #
  describe "#ticket_volume_by_date" do
    it "returns ticket counts grouped by date" do
      create(:escalated_ticket, created_at: 5.days.ago)
      create(:escalated_ticket, created_at: 5.days.ago)
      create(:escalated_ticket, created_at: 3.days.ago)

      result = service.ticket_volume_by_date(start_date, end_date)

      expect(result).to be_an(Array)
      expect(result.length).to eq(2) # 2 distinct dates
    end

    it "returns entries with date and count keys" do
      create(:escalated_ticket, created_at: 2.days.ago)

      result = service.ticket_volume_by_date(start_date, end_date)

      expect(result.first).to have_key(:date)
      expect(result.first).to have_key(:count)
    end

    it "returns empty array when no tickets in range" do
      result = service.ticket_volume_by_date(start_date, end_date)

      expect(result).to be_empty
    end

    it "excludes tickets outside the date range" do
      create(:escalated_ticket, created_at: 60.days.ago)
      create(:escalated_ticket, created_at: 5.days.ago)

      result = service.ticket_volume_by_date(start_date, end_date)

      total_count = result.sum { |r| r[:count] }
      expect(total_count).to eq(1)
    end

    it "orders results by date" do
      create(:escalated_ticket, created_at: 10.days.ago)
      create(:escalated_ticket, created_at: 5.days.ago)
      create(:escalated_ticket, created_at: 1.day.ago)

      result = service.ticket_volume_by_date(start_date, end_date)
      dates = result.map { |r| r[:date] }

      expect(dates).to eq(dates.sort)
    end
  end

  # ------------------------------------------------------------------ #
  # #tickets_by_status
  # ------------------------------------------------------------------ #
  describe "#tickets_by_status" do
    it "returns ticket counts grouped by status" do
      create(:escalated_ticket, :open)
      create(:escalated_ticket, :open)
      create(:escalated_ticket, :closed)

      result = service.tickets_by_status

      expect(result).to be_an(Array)
      open_entry = result.find { |r| r[:status] == "open" }
      closed_entry = result.find { |r| r[:status] == "closed" }
      expect(open_entry[:count]).to eq(2)
      expect(closed_entry[:count]).to eq(1)
    end

    it "returns empty array when no tickets exist" do
      result = service.tickets_by_status

      expect(result).to be_empty
    end

    it "includes all present statuses" do
      create(:escalated_ticket, :open)
      create(:escalated_ticket, :in_progress)
      create(:escalated_ticket, :resolved)

      result = service.tickets_by_status
      statuses = result.map { |r| r[:status] }

      expect(statuses).to include("open", "in_progress", "resolved")
    end
  end

  # ------------------------------------------------------------------ #
  # #tickets_by_priority
  # ------------------------------------------------------------------ #
  describe "#tickets_by_priority" do
    it "returns ticket counts grouped by priority" do
      create(:escalated_ticket, priority: :low)
      create(:escalated_ticket, priority: :high)
      create(:escalated_ticket, priority: :high)

      result = service.tickets_by_priority

      expect(result).to be_an(Array)
      high_entry = result.find { |r| r[:priority] == "high" }
      low_entry = result.find { |r| r[:priority] == "low" }
      expect(high_entry[:count]).to eq(2)
      expect(low_entry[:count]).to eq(1)
    end

    it "returns empty array when no tickets exist" do
      result = service.tickets_by_priority

      expect(result).to be_empty
    end
  end

  # ------------------------------------------------------------------ #
  # #average_response_time
  # ------------------------------------------------------------------ #
  describe "#average_response_time" do
    it "returns the average first response time in hours" do
      ticket1 = create(:escalated_ticket, created_at: 10.days.ago)
      create(:escalated_reply, ticket: ticket1, is_internal: false, created_at: ticket1.created_at + 2.hours)

      ticket2 = create(:escalated_ticket, created_at: 8.days.ago)
      create(:escalated_reply, ticket: ticket2, is_internal: false, created_at: ticket2.created_at + 4.hours)

      result = service.average_response_time(start_date, end_date)

      # Average of 2 hours and 4 hours = 3 hours
      expect(result).to be_within(0.1).of(3.0)
    end

    it "ignores internal replies for first response calculation" do
      ticket = create(:escalated_ticket, created_at: 5.days.ago)
      create(:escalated_reply, ticket: ticket, is_internal: true, created_at: ticket.created_at + 1.hour)
      create(:escalated_reply, ticket: ticket, is_internal: false, created_at: ticket.created_at + 3.hours)

      result = service.average_response_time(start_date, end_date)

      expect(result).to be_within(0.1).of(3.0)
    end

    it "returns 0.0 when no tickets have replies" do
      create(:escalated_ticket, created_at: 5.days.ago)

      result = service.average_response_time(start_date, end_date)

      expect(result).to eq(0.0)
    end

    it "returns 0.0 when no tickets exist in range" do
      result = service.average_response_time(start_date, end_date)

      expect(result).to eq(0.0)
    end

    it "only considers the first public reply per ticket" do
      ticket = create(:escalated_ticket, created_at: 5.days.ago)
      create(:escalated_reply, ticket: ticket, is_internal: false, created_at: ticket.created_at + 2.hours)
      create(:escalated_reply, ticket: ticket, is_internal: false, created_at: ticket.created_at + 10.hours)

      result = service.average_response_time(start_date, end_date)

      expect(result).to be_within(0.1).of(2.0)
    end
  end

  # ------------------------------------------------------------------ #
  # #average_resolution_time
  # ------------------------------------------------------------------ #
  describe "#average_resolution_time" do
    it "returns the average resolution time in hours for resolved/closed tickets" do
      ticket1 = create(:escalated_ticket, :resolved, created_at: 10.days.ago)
      ticket1.update_column(:updated_at, ticket1.created_at + 12.hours)

      ticket2 = create(:escalated_ticket, :closed, created_at: 8.days.ago)
      ticket2.update_column(:updated_at, ticket2.created_at + 24.hours)

      result = service.average_resolution_time(start_date, end_date)

      # Average of 12 hours and 24 hours = 18 hours
      expect(result).to be_within(0.5).of(18.0)
    end

    it "returns 0.0 when no resolved/closed tickets exist" do
      create(:escalated_ticket, :open, created_at: 5.days.ago)

      result = service.average_resolution_time(start_date, end_date)

      expect(result).to eq(0.0)
    end

    it "returns 0.0 when no tickets exist in range" do
      result = service.average_resolution_time(start_date, end_date)

      expect(result).to eq(0.0)
    end

    it "excludes open tickets from the calculation" do
      open_ticket = create(:escalated_ticket, :open, created_at: 5.days.ago)
      resolved_ticket = create(:escalated_ticket, :resolved, created_at: 5.days.ago)
      resolved_ticket.update_column(:updated_at, resolved_ticket.created_at + 6.hours)

      result = service.average_resolution_time(start_date, end_date)

      expect(result).to be_within(0.1).of(6.0)
    end
  end

  # ------------------------------------------------------------------ #
  # #agent_performance
  # ------------------------------------------------------------------ #
  describe "#agent_performance" do
    # The agent_performance method uses `joins(:escalated_assigned_tickets)`,
    # which requires the User model to have this association defined.
    # In the dummy test app, this association may not be set up, so we
    # test the method's behavior when it can operate.

    context "when no agents have assigned tickets" do
      it "returns an empty array" do
        # Add the association dynamically for testing
        unless User.reflect_on_association(:escalated_assigned_tickets)
          User.has_many :escalated_assigned_tickets,
                        class_name: "Escalated::Ticket",
                        foreign_key: :assigned_to,
                        dependent: :nullify
        end

        result = service.agent_performance(start_date, end_date)

        expect(result).to be_empty
      end
    end

    context "when agents have assigned tickets" do
      before do
        unless User.reflect_on_association(:escalated_assigned_tickets)
          User.has_many :escalated_assigned_tickets,
                        class_name: "Escalated::Ticket",
                        foreign_key: :assigned_to,
                        dependent: :nullify
        end
      end

      it "returns performance data for each agent" do
        agent = create(:user, :agent)
        create(:escalated_ticket, :open, assigned_to: agent.id, created_at: 5.days.ago)
        create(:escalated_ticket, :resolved, assigned_to: agent.id, created_at: 3.days.ago)

        result = service.agent_performance(start_date, end_date)

        expect(result.length).to eq(1)
        expect(result.first[:agent_id]).to eq(agent.id)
        expect(result.first[:total_tickets]).to eq(2)
        expect(result.first[:resolved_tickets]).to eq(1)
      end

      it "includes the agent name" do
        agent = create(:user, :agent, name: "Jane Smith")
        create(:escalated_ticket, :open, assigned_to: agent.id, created_at: 5.days.ago)

        result = service.agent_performance(start_date, end_date)

        expect(result.first[:agent_name]).to eq("Jane Smith")
      end

      it "returns data for multiple agents" do
        agent1 = create(:user, :agent)
        agent2 = create(:user, :agent)
        create(:escalated_ticket, :open, assigned_to: agent1.id, created_at: 5.days.ago)
        create(:escalated_ticket, :open, assigned_to: agent2.id, created_at: 5.days.ago)

        result = service.agent_performance(start_date, end_date)
        agent_ids = result.map { |r| r[:agent_id] }

        expect(agent_ids).to include(agent1.id, agent2.id)
      end
    end
  end
end
