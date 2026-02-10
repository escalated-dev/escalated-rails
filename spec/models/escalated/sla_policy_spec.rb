require "rails_helper"

RSpec.describe Escalated::SlaPolicy, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe "associations" do
    it { is_expected.to have_many(:tickets).class_name("Escalated::Ticket").dependent(:nullify) }
    it { is_expected.to have_many(:departments).class_name("Escalated::Department").dependent(:nullify) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:first_response_hours) }
    it { is_expected.to validate_presence_of(:resolution_hours) }

    context "uniqueness" do
      subject { create(:escalated_sla_policy) }

      it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    describe ".active" do
      it "returns only active policies" do
        active = create(:escalated_sla_policy, is_active: true)
        _inactive = create(:escalated_sla_policy, :inactive)

        result = described_class.active
        expect(result).to include(active)
        expect(result).not_to include(_inactive)
      end
    end

    describe ".default_policy" do
      it "returns policies marked as default" do
        _regular = create(:escalated_sla_policy, is_default: false)
        default = create(:escalated_sla_policy, :default)

        result = described_class.default_policy
        expect(result).to include(default)
        expect(result).not_to include(_regular)
      end
    end

    describe ".ordered" do
      it "returns policies ordered by name" do
        premium = create(:escalated_sla_policy, name: "Premium SLA")
        basic = create(:escalated_sla_policy, name: "Basic SLA")

        result = described_class.ordered
        expect(result.first).to eq(basic)
        expect(result.last).to eq(premium)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Priority hour methods
  # ------------------------------------------------------------------ #
  describe "#first_response_hours_for" do
    let(:policy) do
      create(:escalated_sla_policy, first_response_hours: {
        "low" => 24,
        "medium" => 8,
        "high" => 4,
        "urgent" => 2,
        "critical" => 1
      })
    end

    it "returns hours for low priority" do
      expect(policy.first_response_hours_for(:low)).to eq(24.0)
    end

    it "returns hours for medium priority" do
      expect(policy.first_response_hours_for(:medium)).to eq(8.0)
    end

    it "returns hours for high priority" do
      expect(policy.first_response_hours_for(:high)).to eq(4.0)
    end

    it "returns hours for urgent priority" do
      expect(policy.first_response_hours_for(:urgent)).to eq(2.0)
    end

    it "returns hours for critical priority" do
      expect(policy.first_response_hours_for(:critical)).to eq(1.0)
    end

    it "returns nil for unknown priority" do
      expect(policy.first_response_hours_for(:unknown)).to be_nil
    end

    it "returns nil when first_response_hours is not a hash" do
      policy.first_response_hours = "invalid"
      expect(policy.first_response_hours_for(:low)).to be_nil
    end

    it "accepts string priority keys" do
      expect(policy.first_response_hours_for("high")).to eq(4.0)
    end
  end

  describe "#resolution_hours_for" do
    let(:policy) do
      create(:escalated_sla_policy, resolution_hours: {
        "low" => 72,
        "medium" => 48,
        "high" => 24,
        "urgent" => 8,
        "critical" => 4
      })
    end

    it "returns hours for low priority" do
      expect(policy.resolution_hours_for(:low)).to eq(72.0)
    end

    it "returns hours for critical priority" do
      expect(policy.resolution_hours_for(:critical)).to eq(4.0)
    end

    it "returns nil for unknown priority" do
      expect(policy.resolution_hours_for(:unknown)).to be_nil
    end

    it "returns nil when resolution_hours is not a hash" do
      policy.resolution_hours = "invalid"
      expect(policy.resolution_hours_for(:low)).to be_nil
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#active?" do
    it "returns true when active" do
      policy = build(:escalated_sla_policy, is_active: true)
      expect(policy.active?).to be(true)
    end

    it "returns false when inactive" do
      policy = build(:escalated_sla_policy, is_active: false)
      expect(policy.active?).to be(false)
    end
  end

  describe "#default?" do
    it "returns true when marked as default" do
      policy = build(:escalated_sla_policy, is_default: true)
      expect(policy.default?).to be(true)
    end

    it "returns false when not default" do
      policy = build(:escalated_sla_policy, is_default: false)
      expect(policy.default?).to be(false)
    end
  end

  describe "#priority_targets" do
    let(:policy) do
      create(:escalated_sla_policy,
             first_response_hours: { "low" => 24, "medium" => 8, "high" => 4, "urgent" => 2, "critical" => 1 },
             resolution_hours: { "low" => 72, "medium" => 48, "high" => 24, "urgent" => 8, "critical" => 4 })
    end

    it "returns an array of targets for all priorities" do
      targets = policy.priority_targets
      expect(targets.length).to eq(5) # low, medium, high, urgent, critical
    end

    it "includes priority, first_response, and resolution for each entry" do
      targets = policy.priority_targets
      high_target = targets.find { |t| t[:priority] == "high" }

      expect(high_target[:first_response]).to eq(4.0)
      expect(high_target[:resolution]).to eq(24.0)
    end

    it "covers all priority levels" do
      targets = policy.priority_targets
      priorities = targets.map { |t| t[:priority] }
      expect(priorities).to contain_exactly("low", "medium", "high", "urgent", "critical")
    end
  end
end
