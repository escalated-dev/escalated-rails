require "rails_helper"

RSpec.describe Escalated::Department, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe "associations" do
    it { is_expected.to have_many(:tickets).class_name("Escalated::Ticket").dependent(:nullify) }
    it { is_expected.to belong_to(:default_sla_policy).class_name("Escalated::SlaPolicy").optional }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context "uniqueness" do
      subject { create(:escalated_department) }

      it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
      it { is_expected.to validate_uniqueness_of(:slug) }
    end

    describe "email format" do
      it "accepts valid email addresses" do
        dept = build(:escalated_department, email: "support@example.com")
        expect(dept).to be_valid
      end

      it "accepts nil email" do
        dept = build(:escalated_department, email: nil)
        expect(dept).to be_valid
      end

      it "rejects invalid email addresses" do
        dept = build(:escalated_department, email: "not-an-email")
        expect(dept).not_to be_valid
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe "callbacks" do
    describe "#generate_slug" do
      it "auto-generates slug from name when slug is blank" do
        dept = build(:escalated_department, name: "Technical Support", slug: nil)
        dept.valid?
        expect(dept.slug).to eq("technical-support")
      end

      it "does not override an existing slug" do
        dept = build(:escalated_department, name: "Sales", slug: "custom-slug")
        dept.valid?
        expect(dept.slug).to eq("custom-slug")
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    describe ".active" do
      it "returns only active departments" do
        active = create(:escalated_department, is_active: true)
        _inactive = create(:escalated_department, :inactive)

        result = described_class.active
        expect(result).to include(active)
        expect(result).not_to include(_inactive)
      end
    end

    describe ".ordered" do
      it "returns departments ordered by name" do
        zeta = create(:escalated_department, name: "Zeta Team")
        alpha = create(:escalated_department, name: "Alpha Team")

        result = described_class.ordered
        expect(result.first).to eq(alpha)
        expect(result.last).to eq(zeta)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#active?" do
    it "returns true when department is active" do
      dept = build(:escalated_department, is_active: true)
      expect(dept.active?).to be(true)
    end

    it "returns false when department is inactive" do
      dept = build(:escalated_department, is_active: false)
      expect(dept.active?).to be(false)
    end
  end

  describe "#open_ticket_count" do
    it "returns the count of open tickets in the department" do
      dept = create(:escalated_department)
      create(:escalated_ticket, department: dept, status: :open)
      create(:escalated_ticket, department: dept, status: :in_progress)
      create(:escalated_ticket, department: dept, status: :closed)

      expect(dept.open_ticket_count).to eq(2)
    end

    it "returns 0 when no open tickets" do
      dept = create(:escalated_department)
      create(:escalated_ticket, department: dept, status: :closed)

      expect(dept.open_ticket_count).to eq(0)
    end
  end

  describe "#agent_count" do
    it "returns the number of agents in the department" do
      dept = create(:escalated_department, :with_agents)
      expect(dept.agent_count).to eq(3) # :with_agents trait creates 3 agents
    end

    it "returns 0 when no agents" do
      dept = create(:escalated_department)
      expect(dept.agent_count).to eq(0)
    end
  end

  # ------------------------------------------------------------------ #
  # Agent management
  # ------------------------------------------------------------------ #
  describe "agent management" do
    let(:dept) { create(:escalated_department) }
    let(:agent1) { create(:user, :agent) }
    let(:agent2) { create(:user, :agent) }

    it "can add agents to the department" do
      dept.agents << agent1
      dept.agents << agent2
      expect(dept.agents.count).to eq(2)
    end

    it "can remove agents from the department" do
      dept.agents << agent1
      dept.agents.delete(agent1)
      expect(dept.agents.count).to eq(0)
    end

    it "prevents duplicate agent assignments" do
      dept.agents << agent1
      expect { dept.agents << agent1 }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
