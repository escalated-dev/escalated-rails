require "rails_helper"

RSpec.describe Escalated::CannedResponse, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe "associations" do
    it { is_expected.to belong_to(:creator).class_name("User").with_foreign_key(:created_by) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:body) }

    context "shortcode uniqueness" do
      subject { create(:escalated_canned_response) }

      it { is_expected.to validate_uniqueness_of(:shortcode).case_insensitive }
    end

    it "allows nil shortcode" do
      response = build(:escalated_canned_response, shortcode: nil)
      expect(response).to be_valid
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe "scopes" do
    let(:agent) { create(:user, :agent) }
    let(:other_agent) { create(:user, :agent) }

    describe ".shared" do
      it "returns only shared responses" do
        shared = create(:escalated_canned_response, creator: agent, is_shared: true)
        _personal = create(:escalated_canned_response, :personal, creator: agent)

        result = described_class.shared
        expect(result).to include(shared)
        expect(result).not_to include(_personal)
      end
    end

    describe ".personal" do
      it "returns only personal responses" do
        _shared = create(:escalated_canned_response, creator: agent, is_shared: true)
        personal = create(:escalated_canned_response, :personal, creator: agent)

        result = described_class.personal
        expect(result).to include(personal)
        expect(result).not_to include(_shared)
      end
    end

    describe ".for_user" do
      it "returns shared responses and user's personal responses" do
        shared = create(:escalated_canned_response, creator: other_agent, is_shared: true)
        own_personal = create(:escalated_canned_response, :personal, creator: agent)
        _other_personal = create(:escalated_canned_response, :personal, creator: other_agent)

        result = described_class.for_user(agent.id)
        expect(result).to include(shared, own_personal)
        expect(result).not_to include(_other_personal)
      end
    end

    describe ".by_category" do
      it "returns responses in a specific category" do
        greeting = create(:escalated_canned_response, :greeting, creator: agent)
        _closing = create(:escalated_canned_response, :closing, creator: agent)

        result = described_class.by_category("greeting")
        expect(result).to include(greeting)
        expect(result).not_to include(_closing)
      end
    end

    describe ".search" do
      it "searches by title" do
        response = create(:escalated_canned_response, title: "Password Reset Template", creator: agent)
        _other = create(:escalated_canned_response, title: "Billing Question", creator: agent)

        result = described_class.search("Password")
        expect(result).to include(response)
        expect(result).not_to include(_other)
      end

      it "searches by body" do
        response = create(:escalated_canned_response, body: "Please reset your credentials", creator: agent)
        _other = create(:escalated_canned_response, body: "Your invoice is attached", creator: agent)

        result = described_class.search("credentials")
        expect(result).to include(response)
        expect(result).not_to include(_other)
      end

      it "searches by shortcode" do
        response = create(:escalated_canned_response, shortcode: "pw_reset", creator: agent)
        _other = create(:escalated_canned_response, shortcode: "billing_q", creator: agent)

        result = described_class.search("pw_reset")
        expect(result).to include(response)
        expect(result).not_to include(_other)
      end
    end

    describe ".ordered" do
      it "returns responses ordered by title" do
        beta = create(:escalated_canned_response, title: "Beta Template", creator: agent)
        alpha = create(:escalated_canned_response, title: "Alpha Template", creator: agent)

        result = described_class.ordered
        expect(result.first).to eq(alpha)
        expect(result.last).to eq(beta)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe "#shared?" do
    it "returns true when shared" do
      response = build(:escalated_canned_response, is_shared: true)
      expect(response.shared?).to be(true)
    end

    it "returns false when not shared" do
      response = build(:escalated_canned_response, is_shared: false)
      expect(response.shared?).to be(false)
    end
  end

  describe "#personal?" do
    it "returns true when not shared" do
      response = build(:escalated_canned_response, is_shared: false)
      expect(response.personal?).to be(true)
    end

    it "returns false when shared" do
      response = build(:escalated_canned_response, is_shared: true)
      expect(response.personal?).to be(false)
    end
  end

  describe "#render" do
    let(:agent) { create(:user, :agent) }

    it "replaces variables with provided values" do
      response = build(:escalated_canned_response,
                       body: "Hello {{ticket.requester_name}}, regarding {{ticket.subject}}.",
                       creator: agent)

      result = response.render(
        "ticket.requester_name" => "John Doe",
        "ticket.subject" => "Login Issue"
      )

      expect(result).to eq("Hello John Doe, regarding Login Issue.")
    end

    it "removes unmatched variables" do
      response = build(:escalated_canned_response,
                       body: "Hello {{ticket.requester_name}}, {{unknown.variable}} here.",
                       creator: agent)

      result = response.render("ticket.requester_name" => "Jane")
      expect(result).to eq("Hello Jane,  here.")
    end

    it "handles empty variables hash" do
      response = build(:escalated_canned_response,
                       body: "Hello {{ticket.requester_name}}!",
                       creator: agent)

      result = response.render({})
      expect(result).to eq("Hello !")
    end

    it "renders body with multiple variables" do
      response = build(:escalated_canned_response, :with_variables, creator: agent)

      result = response.render(
        "ticket.requester_name" => "Alice",
        "ticket.subject" => "Password reset",
        "agent.name" => "Bob"
      )

      expect(result).to include("Alice")
      expect(result).to include("Password reset")
      expect(result).to include("Bob")
    end

    it "does not modify the original body" do
      response = build(:escalated_canned_response,
                       body: "Hello {{name}}",
                       creator: agent)

      response.render("name" => "Test")
      expect(response.body).to eq("Hello {{name}}")
    end

    it "converts non-string values to strings" do
      response = build(:escalated_canned_response,
                       body: "Ticket #{{ticket.id}}",
                       creator: agent)

      result = response.render("ticket.id" => 42)
      expect(result).to eq("Ticket #42")
    end
  end
end
