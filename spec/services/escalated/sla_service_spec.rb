require "rails_helper"

RSpec.describe Escalated::Services::SlaService do
  let(:user) { create(:user) }
  let(:agent) { create(:user, :agent) }

  # Disable email notifications for service tests
  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated.configuration).to receive(:webhook_url).and_return(nil)
  end

  # ------------------------------------------------------------------ #
  # .attach_policy
  # ------------------------------------------------------------------ #
  describe ".attach_policy" do
    let(:ticket) { create(:escalated_ticket, priority: :high) }

    context "when SLA is enabled" do
      before do
        allow(Escalated.configuration).to receive(:sla_enabled?).and_return(true)
        allow(Escalated.configuration).to receive(:business_hours_only?).and_return(false)
      end

      it "attaches the given policy to the ticket" do
        policy = create(:escalated_sla_policy)
        described_class.attach_policy(ticket, policy)
        ticket.reload

        expect(ticket.sla_policy_id).to eq(policy.id)
      end

      it "sets sla_first_response_due_at based on priority" do
        policy = create(:escalated_sla_policy,
                        first_response_hours: { "high" => 4 },
                        resolution_hours: { "high" => 24 })

        described_class.attach_policy(ticket, policy)
        ticket.reload

        expect(ticket.sla_first_response_due_at).to be_within(1.minute).of(4.hours.from_now)
      end

      it "sets sla_resolution_due_at based on priority" do
        policy = create(:escalated_sla_policy,
                        first_response_hours: { "high" => 4 },
                        resolution_hours: { "high" => 24 })

        described_class.attach_policy(ticket, policy)
        ticket.reload

        expect(ticket.sla_resolution_due_at).to be_within(1.minute).of(24.hours.from_now)
      end

      it "finds the default policy when no policy is given" do
        default_policy = create(:escalated_sla_policy, :default)

        described_class.attach_policy(ticket)
        ticket.reload

        expect(ticket.sla_policy_id).to eq(default_policy.id)
      end

      it "finds the department's default SLA policy" do
        dept_policy = create(:escalated_sla_policy)
        dept = create(:escalated_department, default_sla_policy: dept_policy)
        ticket.update!(department: dept)

        described_class.attach_policy(ticket)
        ticket.reload

        expect(ticket.sla_policy_id).to eq(dept_policy.id)
      end

      it "does nothing when no policy is found" do
        described_class.attach_policy(ticket)
        ticket.reload

        expect(ticket.sla_policy_id).to be_nil
      end
    end

    context "when SLA is disabled" do
      before do
        allow(Escalated.configuration).to receive(:sla_enabled?).and_return(false)
      end

      it "does not attach any policy" do
        policy = create(:escalated_sla_policy)
        described_class.attach_policy(ticket, policy)
        ticket.reload

        expect(ticket.sla_policy_id).to be_nil
      end
    end
  end

  # ------------------------------------------------------------------ #
  # .check_breaches
  # ------------------------------------------------------------------ #
  describe ".check_breaches" do
    before do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(true)
      allow(Escalated.configuration).to receive(:business_hours_only?).and_return(false)
    end

    it "returns empty array when SLA is disabled" do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(false)
      expect(described_class.check_breaches).to be_nil
    end

    context "first response breaches" do
      it "marks tickets as breached when first response SLA is overdue" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        sla_breached: false,
                        sla_first_response_due_at: 2.hours.ago,
                        first_response_at: nil)

        result = described_class.check_breaches
        ticket.reload

        expect(result).to include(ticket)
        expect(ticket.sla_breached).to be(true)
      end

      it "does not breach tickets with first response already made" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        sla_breached: false,
                        sla_first_response_due_at: 2.hours.ago,
                        first_response_at: 3.hours.ago)

        result = described_class.check_breaches

        expect(result).not_to include(ticket)
      end

      it "does not breach tickets that are already breached" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        sla_breached: true,
                        sla_first_response_due_at: 2.hours.ago,
                        first_response_at: nil)

        result = described_class.check_breaches

        expect(result).not_to include(ticket)
      end
    end

    context "resolution breaches" do
      it "marks tickets as breached when resolution SLA is overdue" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        sla_breached: false,
                        sla_resolution_due_at: 2.hours.ago,
                        resolved_at: nil)

        result = described_class.check_breaches
        ticket.reload

        expect(result).to include(ticket)
        expect(ticket.sla_breached).to be(true)
      end

      it "does not breach tickets that are already resolved" do
        ticket = create(:escalated_ticket,
                        status: :open,
                        sla_breached: false,
                        sla_resolution_due_at: 2.hours.ago,
                        resolved_at: 3.hours.ago)

        result = described_class.check_breaches

        expect(result).not_to include(ticket)
      end
    end

    it "creates an sla_breached activity" do
      ticket = create(:escalated_ticket,
                      status: :open,
                      sla_breached: false,
                      sla_first_response_due_at: 2.hours.ago,
                      first_response_at: nil)

      described_class.check_breaches

      activity = ticket.activities.find_by(action: "sla_breached")
      expect(activity).to be_present
    end
  end

  # ------------------------------------------------------------------ #
  # .check_warnings
  # ------------------------------------------------------------------ #
  describe ".check_warnings" do
    before do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(true)
      allow(Escalated.configuration).to receive(:business_hours_only?).and_return(false)
    end

    it "returns nil when SLA is disabled" do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(false)
      expect(described_class.check_warnings).to be_nil
    end

    it "returns tickets nearing first response breach" do
      ticket = create(:escalated_ticket,
                      status: :open,
                      sla_breached: false,
                      sla_first_response_due_at: 30.minutes.from_now,
                      first_response_at: nil)

      result = described_class.check_warnings

      warning_tickets = result.map { |w| w[:ticket] }
      expect(warning_tickets).to include(ticket)
    end

    it "returns tickets nearing resolution breach" do
      ticket = create(:escalated_ticket,
                      status: :open,
                      sla_breached: false,
                      sla_resolution_due_at: 1.hour.from_now,
                      resolved_at: nil)

      result = described_class.check_warnings

      warning_tickets = result.map { |w| w[:ticket] }
      expect(warning_tickets).to include(ticket)
    end

    it "includes the warning type" do
      create(:escalated_ticket,
             status: :open,
             sla_breached: false,
             sla_first_response_due_at: 30.minutes.from_now,
             first_response_at: nil)

      result = described_class.check_warnings
      expect(result.first[:type]).to eq(:first_response_warning)
    end

    it "does not return tickets with responses already made" do
      create(:escalated_ticket,
             status: :open,
             sla_breached: false,
             sla_first_response_due_at: 30.minutes.from_now,
             first_response_at: Time.current)

      result = described_class.check_warnings

      first_response_warnings = result.select { |w| w[:type] == :first_response_warning }
      expect(first_response_warnings).to be_empty
    end

    it "does not return tickets already breached" do
      create(:escalated_ticket,
             status: :open,
             sla_breached: true,
             sla_first_response_due_at: 30.minutes.from_now,
             first_response_at: nil)

      result = described_class.check_warnings

      expect(result).to be_empty
    end
  end

  # ------------------------------------------------------------------ #
  # .calculate_due_date
  # ------------------------------------------------------------------ #
  describe ".calculate_due_date" do
    before do
      allow(Escalated.configuration).to receive(:business_hours_only?).and_return(false)
    end

    it "returns nil for nil hours" do
      expect(described_class.calculate_due_date(nil)).to be_nil
    end

    it "calculates due date based on hours from now" do
      result = described_class.calculate_due_date(4)
      expect(result).to be_within(1.minute).of(4.hours.from_now)
    end

    context "with business hours" do
      before do
        allow(Escalated.configuration).to receive(:business_hours_only?).and_return(true)
        allow(Escalated.configuration).to receive(:business_hours).and_return({
          start: 9,
          end: 17,
          timezone: "UTC",
          working_days: [1, 2, 3, 4, 5]
        })
      end

      it "calculates due date within business hours" do
        result = described_class.calculate_due_date(4)
        expect(result).to be_present
        expect(result).to be > Time.current
      end
    end
  end

  # ------------------------------------------------------------------ #
  # .recalculate_for_ticket
  # ------------------------------------------------------------------ #
  describe ".recalculate_for_ticket" do
    before do
      allow(Escalated.configuration).to receive(:business_hours_only?).and_return(false)
    end

    it "recalculates SLA dates for the ticket based on its policy" do
      policy = create(:escalated_sla_policy,
                      first_response_hours: { "high" => 4 },
                      resolution_hours: { "high" => 24 })
      ticket = create(:escalated_ticket,
                      priority: :high,
                      sla_policy: policy,
                      sla_first_response_due_at: 1.hour.ago,
                      first_response_at: nil,
                      resolved_at: nil)

      described_class.recalculate_for_ticket(ticket)
      ticket.reload

      expect(ticket.sla_first_response_due_at).to be_within(1.minute).of(4.hours.from_now)
      expect(ticket.sla_resolution_due_at).to be_within(1.minute).of(24.hours.from_now)
    end

    it "does not recalculate first response when already responded" do
      policy = create(:escalated_sla_policy,
                      first_response_hours: { "high" => 4 },
                      resolution_hours: { "high" => 24 })
      original_due = 3.hours.ago
      ticket = create(:escalated_ticket,
                      priority: :high,
                      sla_policy: policy,
                      sla_first_response_due_at: original_due,
                      first_response_at: 4.hours.ago,
                      resolved_at: nil)

      described_class.recalculate_for_ticket(ticket)
      ticket.reload

      # First response due_at should not be updated since first_response_at is set
      expect(ticket.sla_first_response_due_at).to be_within(1.second).of(original_due)
    end

    it "does nothing when ticket has no SLA policy" do
      ticket = create(:escalated_ticket, sla_policy: nil)

      expect { described_class.recalculate_for_ticket(ticket) }.not_to raise_error
    end
  end

  # ------------------------------------------------------------------ #
  # .stats
  # ------------------------------------------------------------------ #
  describe ".stats" do
    before do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(true)
    end

    it "returns empty hash when SLA is disabled" do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(false)
      expect(described_class.stats).to eq({})
    end

    it "returns SLA statistics" do
      policy = create(:escalated_sla_policy)
      create(:escalated_ticket,
             sla_policy: policy,
             sla_breached: false,
             sla_first_response_due_at: 4.hours.from_now,
             first_response_at: 1.hour.ago)
      create(:escalated_ticket,
             sla_policy: policy,
             sla_breached: true)

      stats = described_class.stats

      expect(stats).to have_key(:total_with_sla)
      expect(stats).to have_key(:total_breached)
      expect(stats).to have_key(:breach_rate)
      expect(stats[:total_with_sla]).to eq(2)
      expect(stats[:total_breached]).to eq(1)
      expect(stats[:breach_rate]).to eq(50.0)
    end
  end
end
