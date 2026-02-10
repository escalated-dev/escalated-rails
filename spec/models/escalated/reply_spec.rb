require "rails_helper"

RSpec.describe Escalated::Reply, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe "associations" do
    it { is_expected.to belong_to(:ticket).class_name("Escalated::Ticket") }
    it { is_expected.to belong_to(:author) }
    it { is_expected.to have_many(:attachments) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:body) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    let(:ticket) { create(:escalated_ticket) }
    let(:author) { create(:user, :agent) }

    describe ".public_replies" do
      it "returns only non-internal replies" do
        public_reply = create(:escalated_reply, ticket: ticket, author: author, is_internal: false)
        _internal = create(:escalated_reply, :internal, ticket: ticket, author: author)

        result = described_class.public_replies
        expect(result).to include(public_reply)
        expect(result).not_to include(_internal)
      end
    end

    describe ".internal_notes" do
      it "returns only internal replies" do
        _public = create(:escalated_reply, ticket: ticket, author: author, is_internal: false)
        internal = create(:escalated_reply, :internal, ticket: ticket, author: author)

        result = described_class.internal_notes
        expect(result).to include(internal)
        expect(result).not_to include(_public)
      end
    end

    describe ".system_messages" do
      it "returns only system messages" do
        _regular = create(:escalated_reply, ticket: ticket, author: author)
        system_msg = create(:escalated_reply, :system, ticket: ticket, is_system: true)

        result = described_class.system_messages
        expect(result).to include(system_msg)
        expect(result).not_to include(_regular)
      end
    end

    describe ".pinned" do
      it "returns only pinned replies" do
        _unpinned = create(:escalated_reply, ticket: ticket, author: author, is_pinned: false)
        pinned = create(:escalated_reply, ticket: ticket, author: author, is_pinned: true)

        result = described_class.pinned
        expect(result).to include(pinned)
        expect(result).not_to include(_unpinned)
      end
    end

    describe ".chronological" do
      it "returns replies in chronological order" do
        old = create(:escalated_reply, ticket: ticket, author: author, created_at: 2.hours.ago)
        recent = create(:escalated_reply, ticket: ticket, author: author, created_at: 1.hour.ago)

        result = described_class.chronological
        expect(result.first).to eq(old)
        expect(result.last).to eq(recent)
      end
    end

    describe ".reverse_chronological" do
      it "returns replies in reverse chronological order" do
        old = create(:escalated_reply, ticket: ticket, author: author, created_at: 2.hours.ago)
        recent = create(:escalated_reply, ticket: ticket, author: author, created_at: 1.hour.ago)

        result = described_class.reverse_chronological
        expect(result.first).to eq(recent)
        expect(result.last).to eq(old)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#public?" do
    it "returns true when not internal" do
      reply = build(:escalated_reply, is_internal: false)
      expect(reply.public?).to be(true)
    end

    it "returns false when internal" do
      reply = build(:escalated_reply, is_internal: true)
      expect(reply.public?).to be(false)
    end
  end

  describe "#internal?" do
    it "returns true when internal" do
      reply = build(:escalated_reply, is_internal: true)
      expect(reply.internal?).to be(true)
    end

    it "returns false when public" do
      reply = build(:escalated_reply, is_internal: false)
      expect(reply.internal?).to be(false)
    end
  end

  describe "#system?" do
    it "returns true for system messages" do
      reply = build(:escalated_reply, is_system: true)
      expect(reply.system?).to be(true)
    end

    it "returns false for regular messages" do
      reply = build(:escalated_reply, is_system: false)
      expect(reply.system?).to be(false)
    end
  end

  describe "#pinned?" do
    it "returns true when pinned" do
      reply = build(:escalated_reply, is_pinned: true)
      expect(reply.pinned?).to be(true)
    end

    it "returns false when not pinned" do
      reply = build(:escalated_reply, is_pinned: false)
      expect(reply.pinned?).to be(false)
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe "callbacks" do
    describe "#touch_ticket" do
      it "updates the ticket's updated_at after creating a reply" do
        ticket = create(:escalated_ticket, updated_at: 1.day.ago)
        author = create(:user, :agent)
        original_time = ticket.updated_at

        create(:escalated_reply, ticket: ticket, author: author)
        ticket.reload

        expect(ticket.updated_at).to be > original_time
      end
    end
  end
end
