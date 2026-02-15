require "rails_helper"

RSpec.describe Escalated::Tag, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe "associations" do
    it "has and belongs to many tickets" do
      tag = create(:escalated_tag)
      ticket1 = create(:escalated_ticket)
      ticket2 = create(:escalated_ticket)

      tag.tickets << ticket1
      tag.tickets << ticket2
      expect(tag.tickets.count).to eq(2)
    end
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context "uniqueness" do
      subject { create(:escalated_tag) }

      it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
      it { is_expected.to validate_uniqueness_of(:slug) }
    end

    describe "color format" do
      it "accepts valid hex colors" do
        tag = build(:escalated_tag, color: "#FF0000")
        expect(tag).to be_valid
      end

      it "accepts nil color" do
        tag = build(:escalated_tag, color: nil)
        expect(tag).to be_valid
      end

      it "rejects invalid hex colors" do
        tag = build(:escalated_tag, color: "red")
        expect(tag).not_to be_valid
        expect(tag.errors[:color]).to include("must be a valid hex color")
      end

      it "rejects short hex colors" do
        tag = build(:escalated_tag, color: "#FFF")
        expect(tag).not_to be_valid
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe "callbacks" do
    describe "#generate_slug" do
      it "auto-generates slug from name when slug is blank" do
        tag = build(:escalated_tag, name: "My Custom Tag", slug: nil)
        tag.valid?
        expect(tag.slug).to eq("my-custom-tag")
      end

      it "auto-generates slug from name with special characters" do
        tag = build(:escalated_tag, name: "Bug & Error Report", slug: nil)
        tag.valid?
        expect(tag.slug).to eq("bug-error-report")
      end

      it "does not override an existing slug" do
        tag = build(:escalated_tag, name: "My Tag", slug: "custom-slug")
        tag.valid?
        expect(tag.slug).to eq("custom-slug")
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    describe ".ordered" do
      it "returns tags ordered by name" do
        zeta = create(:escalated_tag, name: "Zeta")
        alpha = create(:escalated_tag, name: "Alpha")
        beta = create(:escalated_tag, name: "Beta")

        result = described_class.ordered
        expect(result).to eq([alpha, beta, zeta])
      end
    end

    describe ".by_name" do
      it "searches tags by name" do
        bug = create(:escalated_tag, name: "Bug Report")
        _feature = create(:escalated_tag, name: "Feature Request")

        result = described_class.by_name("Bug")
        expect(result).to include(bug)
        expect(result).not_to include(_feature)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#ticket_count" do
    it "returns the number of associated tickets" do
      tag = create(:escalated_tag)
      create_list(:escalated_ticket, 3).each { |t| t.tags << tag }

      expect(tag.ticket_count).to eq(3)
    end

    it "returns 0 when no tickets" do
      tag = create(:escalated_tag)
      expect(tag.ticket_count).to eq(0)
    end
  end
end
