# frozen_string_literal: true

require 'rails_helper'

# ====================================================================== #
# Platform Parity Model Specs
#
# Covers all models added during the platform parity work:
#   AuditLog, TicketStatus, BusinessSchedule, Holiday, Role, Permission,
#   CustomField, CustomFieldValue, TicketLink, SideConversation,
#   SideConversationReply, ArticleCategory, Article, AgentProfile,
#   AgentSkill, Skill, AgentCapacity, Webhook, WebhookDelivery,
#   Automation, TwoFactor, CustomObject, CustomObjectRecord
# ====================================================================== #

# ====================================================================== #
# Escalated::AuditLog
# ====================================================================== #
RSpec.describe Escalated::AuditLog, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:auditable) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    let(:user) { create(:user) }

    describe '.recent' do
      it 'returns audit logs ordered by created_at descending' do
        old_log = create(:escalated_audit_log, created_at: 3.days.ago)
        new_log = create(:escalated_audit_log, created_at: 1.day.ago)

        result = described_class.recent
        expect(result.first).to eq(new_log)
        expect(result.last).to eq(old_log)
      end
    end

    describe '.by_action' do
      it 'returns logs matching a specific action' do
        login_log = create(:escalated_audit_log, action: 'login')
        _destroy_log = create(:escalated_audit_log, action: 'destroy')

        result = described_class.by_action('login')
        expect(result).to include(login_log)
        expect(result).not_to include(_destroy_log)
      end
    end

    describe '.by_user' do
      it 'returns logs for a specific user' do
        user_log = create(:escalated_audit_log, user: user)
        _other_log = create(:escalated_audit_log)

        result = described_class.by_user(user.id)
        expect(result).to include(user_log)
        expect(result).not_to include(_other_log)
      end
    end
  end
end

# ====================================================================== #
# Escalated::TicketStatus
# ====================================================================== #
RSpec.describe Escalated::TicketStatus, type: :model do
  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:label) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject { create(:escalated_ticket_status) }

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe 'callbacks' do
    describe '#generate_slug' do
      it 'auto-generates slug from label when slug is blank' do
        status = build(:escalated_ticket_status, label: 'Waiting On Agent', slug: nil)
        status.valid?
        expect(status.slug).to eq('waiting_on_agent')
      end

      it 'does not override an existing slug' do
        status = build(:escalated_ticket_status, label: 'Open', slug: 'custom_slug')
        status.valid?
        expect(status.slug).to eq('custom_slug')
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.ordered' do
      it 'returns statuses ordered by category and position' do
        later = create(:escalated_ticket_status, category: 'pending', position: 2)
        first = create(:escalated_ticket_status, category: 'open', position: 1)

        result = described_class.ordered
        expect(result.first).to eq(first)
        expect(result.last).to eq(later)
      end
    end

    describe '.by_category' do
      it 'returns statuses in a specific category' do
        open_status = create(:escalated_ticket_status, :open_category)
        _pending_status = create(:escalated_ticket_status, :pending_category)

        result = described_class.by_category('open')
        expect(result).to include(open_status)
        expect(result).not_to include(_pending_status)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Constants
  # ------------------------------------------------------------------ #
  describe 'CATEGORIES' do
    it 'defines the expected categories' do
      expect(described_class::CATEGORIES).to eq(%w[new open pending on_hold solved])
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the label' do
      status = build(:escalated_ticket_status, label: 'In Progress')
      expect(status.to_s).to eq('In Progress')
    end
  end
end

# ====================================================================== #
# Escalated::BusinessSchedule
# ====================================================================== #
RSpec.describe Escalated::BusinessSchedule, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_many(:holidays).dependent(:destroy) }
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      schedule = described_class.new(name: 'US Business Hours')
      expect(schedule.to_s).to eq('US Business Hours')
    end
  end

  describe 'holiday association' do
    it 'can have associated holidays' do
      schedule = described_class.create!(name: 'Test Schedule', timezone: 'UTC')
      Escalated::Holiday.create!(schedule: schedule, name: 'New Year', date: Date.new(2026, 1, 1))
      Escalated::Holiday.create!(schedule: schedule, name: 'Christmas', date: Date.new(2026, 12, 25))

      expect(schedule.holidays.count).to eq(2)
    end

    it 'destroys holidays when schedule is destroyed' do
      schedule = described_class.create!(name: 'Destroy Test', timezone: 'UTC')
      Escalated::Holiday.create!(schedule: schedule, name: 'Holiday 1', date: Date.new(2026, 6, 1))

      expect { schedule.destroy }.to change(Escalated::Holiday, :count).by(-1)
    end
  end
end

# ====================================================================== #
# Escalated::Holiday
# ====================================================================== #
RSpec.describe Escalated::Holiday, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:schedule).class_name('Escalated::BusinessSchedule') }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:date) }
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name and date' do
      schedule = Escalated::BusinessSchedule.create!(name: 'Test', timezone: 'UTC')
      holiday = described_class.new(
        schedule: schedule,
        name: 'Christmas',
        date: Date.new(2026, 12, 25)
      )
      expect(holiday.to_s).to eq('Christmas (2026-12-25)')
    end
  end
end

# ====================================================================== #
# Escalated::Role
# ====================================================================== #
RSpec.describe Escalated::Role, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_and_belong_to_many(:permissions).class_name('Escalated::Permission') }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject { create(:escalated_role) }

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe 'callbacks' do
    describe '#generate_slug' do
      it 'auto-generates slug from name when slug is blank' do
        role = build(:escalated_role, name: 'Support Agent', slug: nil)
        role.valid?
        expect(role.slug).to eq('support_agent')
      end

      it 'does not override an existing slug' do
        role = build(:escalated_role, name: 'Admin', slug: 'custom_admin')
        role.valid?
        expect(role.slug).to eq('custom_admin')
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#has_permission?' do
    it 'returns true when the role has the permission' do
      role = create(:escalated_role)
      permission = create(:escalated_permission, slug: 'manage_tickets')
      role.permissions << permission

      expect(role.has_permission?('manage_tickets')).to be(true)
    end

    it 'returns false when the role does not have the permission' do
      role = create(:escalated_role)
      _permission = create(:escalated_permission, slug: 'manage_tickets')

      expect(role.has_permission?('manage_tickets')).to be(false)
    end
  end

  describe '#to_s' do
    it 'returns the name' do
      role = build(:escalated_role, name: 'Administrator')
      expect(role.to_s).to eq('Administrator')
    end
  end

  describe 'permission management' do
    it 'can have permissions associated' do
      role = create(:escalated_role)
      perm1 = Escalated::Permission.create!(name: 'View Tickets', slug: "view_tickets_#{SecureRandom.hex(4)}")
      perm2 = Escalated::Permission.create!(name: 'Edit Tickets', slug: "edit_tickets_#{SecureRandom.hex(4)}")
      role.permissions << perm1
      role.permissions << perm2

      expect(role.permissions.count).to eq(2)
    end
  end
end

# ====================================================================== #
# Escalated::Permission
# ====================================================================== #
RSpec.describe Escalated::Permission, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_and_belong_to_many(:roles).class_name('Escalated::Role') }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject { create(:escalated_permission, slug: "test_perm_#{SecureRandom.hex(4)}") }

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.ordered' do
      it 'returns permissions ordered by group and name' do
        perm_b = create(:escalated_permission, group: 'tickets', name: 'Zeta', slug: 'zeta_perm')
        perm_a = create(:escalated_permission, group: 'settings', name: 'Alpha', slug: 'alpha_perm')

        result = described_class.ordered
        expect(result.first).to eq(perm_a)
        expect(result.last).to eq(perm_b)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      permission = build(:escalated_permission, name: 'Manage Tickets')
      expect(permission.to_s).to eq('Manage Tickets')
    end
  end
end

# ====================================================================== #
# Escalated::CustomField
# ====================================================================== #
RSpec.describe Escalated::CustomField, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_many(:values).class_name('Escalated::CustomFieldValue').dependent(:destroy) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject do
        described_class.create!(name: 'Test Field', slug: 'test_field_uniq', field_type: 'text', context: 'ticket')
      end

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe 'callbacks' do
    describe '#generate_slug' do
      it 'auto-generates slug from name when slug is blank' do
        field = described_class.new(name: 'Product Version', slug: nil, field_type: 'text', context: 'ticket')
        field.valid?
        expect(field.slug).to eq('product_version')
      end

      it 'does not override an existing slug' do
        field = described_class.new(name: 'Priority Level', slug: 'custom_priority', field_type: 'text',
                                    context: 'ticket')
        field.valid?
        expect(field.slug).to eq('custom_priority')
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Constants
  # ------------------------------------------------------------------ #
  describe 'FIELD_TYPES' do
    it 'defines the expected field types' do
      expect(described_class::FIELD_TYPES).to eq(%w[text textarea select multi_select checkbox date number])
    end
  end

  describe 'CONTEXTS' do
    it 'defines the expected contexts' do
      expect(described_class::CONTEXTS).to eq(%w[ticket user organization])
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.ordered' do
      it 'returns fields ordered by position' do
        second = described_class.create!(name: 'Field B', slug: 'field_b', field_type: 'text', context: 'ticket',
                                         position: 2)
        first = described_class.create!(name: 'Field A', slug: 'field_a', field_type: 'text', context: 'ticket',
                                        position: 1)

        result = described_class.ordered
        expect(result.first).to eq(first)
        expect(result.last).to eq(second)
      end
    end

    describe '.active' do
      it 'returns only active fields' do
        active = described_class.create!(name: 'Active Field', slug: 'active_field', field_type: 'text',
                                         context: 'ticket', active: true)
        _inactive = described_class.create!(name: 'Inactive Field', slug: 'inactive_field', field_type: 'text',
                                            context: 'ticket', active: false)

        result = described_class.active
        expect(result).to include(active)
        expect(result).not_to include(_inactive)
      end
    end

    describe '.for_context' do
      it 'returns fields for a specific context' do
        ticket_field = described_class.create!(name: 'Ticket Field', slug: 'ticket_field', field_type: 'text',
                                               context: 'ticket')
        _user_field = described_class.create!(name: 'User Field', slug: 'user_field', field_type: 'text',
                                              context: 'user')

        result = described_class.for_context('ticket')
        expect(result).to include(ticket_field)
        expect(result).not_to include(_user_field)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      field = described_class.new(name: 'Product Version')
      expect(field.to_s).to eq('Product Version')
    end
  end
end

# ====================================================================== #
# Escalated::CustomFieldValue
# ====================================================================== #
RSpec.describe Escalated::CustomFieldValue, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:custom_field).class_name('Escalated::CustomField') }
    it { is_expected.to belong_to(:entity) }
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the field name and value' do
      field = Escalated::CustomField.create!(name: 'Priority Level', slug: 'priority_level', field_type: 'text',
                                             context: 'ticket')
      ticket = create(:escalated_ticket)
      value = described_class.new(
        custom_field: field,
        entity: ticket,
        value: 'High'
      )

      expect(value.to_s).to eq('Priority Level: High')
    end
  end
end

# ====================================================================== #
# Escalated::TicketLink
# ====================================================================== #
RSpec.describe Escalated::TicketLink, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:parent_ticket).class_name('Escalated::Ticket') }
    it { is_expected.to belong_to(:child_ticket).class_name('Escalated::Ticket') }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:link_type) }

    it 'validates inclusion of link_type' do
      ticket1 = create(:escalated_ticket)
      ticket2 = create(:escalated_ticket)
      link = described_class.new(
        parent_ticket_id: ticket1.id,
        child_ticket_id: ticket2.id,
        link_type: 'invalid_type'
      )
      expect(link).not_to be_valid
      expect(link.errors[:link_type]).to be_present
    end

    it 'accepts valid link types' do
      ticket1 = create(:escalated_ticket)
      ticket2 = create(:escalated_ticket)
      %w[problem_incident parent_child related].each do |type|
        link = described_class.new(
          parent_ticket_id: ticket1.id,
          child_ticket_id: ticket2.id,
          link_type: type
        )
        link.valid?
        expect(link.errors[:link_type]).to be_empty, "Expected #{type} to be valid"
      end
    end

    context 'uniqueness' do
      it 'prevents duplicate links between the same tickets with the same type' do
        ticket1 = create(:escalated_ticket)
        ticket2 = create(:escalated_ticket)
        described_class.create!(
          parent_ticket_id: ticket1.id,
          child_ticket_id: ticket2.id,
          link_type: 'related'
        )

        duplicate = described_class.new(
          parent_ticket_id: ticket1.id,
          child_ticket_id: ticket2.id,
          link_type: 'related'
        )
        expect(duplicate).not_to be_valid
      end

      it 'allows different link types between the same tickets' do
        ticket1 = create(:escalated_ticket)
        ticket2 = create(:escalated_ticket)
        described_class.create!(
          parent_ticket_id: ticket1.id,
          child_ticket_id: ticket2.id,
          link_type: 'related'
        )

        different_type = described_class.new(
          parent_ticket_id: ticket1.id,
          child_ticket_id: ticket2.id,
          link_type: 'parent_child'
        )
        expect(different_type).to be_valid
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Constants
  # ------------------------------------------------------------------ #
  describe 'LINK_TYPES' do
    it 'defines the expected link types' do
      expect(described_class::LINK_TYPES).to eq(%w[problem_incident parent_child related])
    end
  end
end

# ====================================================================== #
# Escalated::SideConversation
# ====================================================================== #
RSpec.describe Escalated::SideConversation, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:ticket).class_name('Escalated::Ticket') }
    it { is_expected.to belong_to(:created_by).optional }
    it { is_expected.to have_many(:replies).class_name('Escalated::SideConversationReply').dependent(:destroy) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.open' do
      it 'returns only open side conversations' do
        open_conv = create(:escalated_side_conversation, status: 'open')
        _closed_conv = create(:escalated_side_conversation, :closed)

        result = described_class.open
        expect(result).to include(open_conv)
        expect(result).not_to include(_closed_conv)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it "returns the subject prefixed with 'Side conversation:'" do
      conv = build(:escalated_side_conversation, subject: 'Check with engineering')
      expect(conv.to_s).to eq('Side conversation: Check with engineering')
    end
  end

  describe 'replies association' do
    it 'can have associated replies' do
      conv = create(:escalated_side_conversation)
      Escalated::SideConversationReply.create!(side_conversation: conv, body: 'Reply 1')
      Escalated::SideConversationReply.create!(side_conversation: conv, body: 'Reply 2')

      expect(conv.replies.count).to eq(2)
    end

    it 'destroys replies when conversation is destroyed' do
      conv = create(:escalated_side_conversation)
      Escalated::SideConversationReply.create!(side_conversation: conv, body: 'Reply 1')

      expect { conv.destroy }.to change(Escalated::SideConversationReply, :count).by(-1)
    end
  end
end

# ====================================================================== #
# Escalated::SideConversationReply
# ====================================================================== #
RSpec.describe Escalated::SideConversationReply, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:side_conversation).class_name('Escalated::SideConversation') }
    it { is_expected.to belong_to(:author).optional }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:body) }
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns a description referencing the conversation subject' do
      conv = create(:escalated_side_conversation, subject: 'Engineering question')
      reply = described_class.new(side_conversation: conv, body: 'Test reply')
      expect(reply.to_s).to eq('Reply on Engineering question')
    end
  end
end

# ====================================================================== #
# Escalated::ArticleCategory
# ====================================================================== #
RSpec.describe Escalated::ArticleCategory, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:parent).class_name('Escalated::ArticleCategory').optional }
    it { is_expected.to have_many(:children).class_name('Escalated::ArticleCategory').dependent(:nullify) }
    it { is_expected.to have_many(:articles).class_name('Escalated::Article').dependent(:nullify) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.roots' do
      it 'returns categories with no parent' do
        root = create(:escalated_article_category, parent: nil)
        child = create(:escalated_article_category, parent: root)

        result = described_class.roots
        expect(result).to include(root)
        expect(result).not_to include(child)
      end
    end

    describe '.ordered' do
      it 'returns categories ordered by position and name' do
        second = create(:escalated_article_category, position: 2, name: 'Alpha')
        first = create(:escalated_article_category, position: 1, name: 'Zeta')

        result = described_class.ordered
        expect(result.first).to eq(first)
        expect(result.last).to eq(second)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      category = build(:escalated_article_category, name: 'Getting Started')
      expect(category.to_s).to eq('Getting Started')
    end
  end

  describe 'parent-child relationships' do
    it 'supports nested categories' do
      parent = create(:escalated_article_category, name: 'Support')
      child = create(:escalated_article_category, name: 'FAQ', parent: parent)

      expect(parent.children).to include(child)
      expect(child.parent).to eq(parent)
    end

    it 'nullifies children when parent is destroyed' do
      parent = create(:escalated_article_category, name: 'Support')
      child = create(:escalated_article_category, name: 'FAQ', parent: parent)

      parent.destroy
      child.reload
      expect(child.parent_id).to be_nil
    end
  end

  describe 'with_articles trait' do
    it 'creates associated articles' do
      category = create(:escalated_article_category, :with_articles)
      expect(category.articles.count).to eq(3)
    end
  end
end

# ====================================================================== #
# Escalated::Article
# ====================================================================== #
RSpec.describe Escalated::Article, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:category).class_name('Escalated::ArticleCategory').optional }
    it { is_expected.to belong_to(:author).optional }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject { create(:escalated_article) }

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.published' do
      it 'returns only published articles' do
        published = create(:escalated_article, :published)
        _draft = create(:escalated_article, status: 'draft')

        result = described_class.published
        expect(result).to include(published)
        expect(result).not_to include(_draft)
      end
    end

    describe '.draft' do
      it 'returns only draft articles' do
        _published = create(:escalated_article, :published)
        draft = create(:escalated_article, status: 'draft')

        result = described_class.draft
        expect(result).to include(draft)
        expect(result).not_to include(_published)
      end
    end

    describe '.search' do
      it 'searches by title' do
        article = create(:escalated_article, title: 'How to Reset Password')
        _other = create(:escalated_article, title: 'Billing FAQ')

        result = described_class.search('Reset')
        expect(result).to include(article)
        expect(result).not_to include(_other)
      end

      it 'searches by body' do
        article = create(:escalated_article, body: 'Navigate to the credentials page')
        _other = create(:escalated_article, body: 'Check your invoice details')

        result = described_class.search('credentials')
        expect(result).to include(article)
        expect(result).not_to include(_other)
      end
    end

    describe '.recent' do
      it 'returns articles ordered by created_at descending' do
        old = create(:escalated_article, created_at: 3.days.ago)
        newer = create(:escalated_article, created_at: 1.day.ago)

        result = described_class.recent
        expect(result.first).to eq(newer)
        expect(result.last).to eq(old)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#increment_views!' do
    it 'increments the view count by 1' do
      article = create(:escalated_article)
      expect { article.increment_views! }.to change { article.reload.view_count }.by(1)
    end
  end

  describe '#mark_helpful!' do
    it 'increments the helpful count by 1' do
      article = create(:escalated_article)
      expect { article.mark_helpful! }.to change { article.reload.helpful_count }.by(1)
    end
  end

  describe '#mark_not_helpful!' do
    it 'increments the not helpful count by 1' do
      article = create(:escalated_article)
      expect { article.mark_not_helpful! }.to change { article.reload.not_helpful_count }.by(1)
    end
  end

  describe '#to_s' do
    it 'returns the title' do
      article = build(:escalated_article, title: 'Getting Started Guide')
      expect(article.to_s).to eq('Getting Started Guide')
    end
  end
end

# ====================================================================== #
# Escalated::AgentProfile
# ====================================================================== #
RSpec.describe Escalated::AgentProfile, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    context 'uniqueness' do
      subject { described_class.create!(user: user, agent_type: 'full') }

      let(:user) { create(:user) }


      it { is_expected.to validate_uniqueness_of(:user_id) }
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#light_agent?' do
    it 'returns true when agent_type is light' do
      user = create(:user)
      profile = described_class.new(user: user, agent_type: 'light')
      expect(profile.light_agent?).to be(true)
    end

    it 'returns false when agent_type is full' do
      user = create(:user)
      profile = described_class.new(user: user, agent_type: 'full')
      expect(profile.light_agent?).to be(false)
    end
  end

  describe '#full_agent?' do
    it 'returns true when agent_type is full' do
      user = create(:user)
      profile = described_class.new(user: user, agent_type: 'full')
      expect(profile.full_agent?).to be(true)
    end

    it 'returns false when agent_type is light' do
      user = create(:user)
      profile = described_class.new(user: user, agent_type: 'light')
      expect(profile.full_agent?).to be(false)
    end
  end

  # ------------------------------------------------------------------ #
  # Class methods
  # ------------------------------------------------------------------ #
  describe '.for_user' do
    it 'returns the profile for a given user_id' do
      user = create(:user)
      profile = described_class.create!(user: user, agent_type: 'full')
      expect(described_class.for_user(user.id)).to eq(profile)
    end

    it 'returns nil when no profile exists' do
      expect(described_class.for_user(999_999)).to be_nil
    end
  end
end

# ====================================================================== #
# Escalated::AgentSkill
# ====================================================================== #
RSpec.describe Escalated::AgentSkill, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:skill).class_name('Escalated::Skill') }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    context 'uniqueness' do
      let(:user) { create(:user) }
      let(:skill) { create(:escalated_skill) }

      it 'prevents duplicate user-skill assignments' do
        described_class.create!(user_id: user.id, skill_id: skill.id)
        duplicate = described_class.new(user_id: user.id, skill_id: skill.id)
        expect(duplicate).not_to be_valid
      end

      it 'allows the same user with different skills' do
        other_skill = create(:escalated_skill)
        described_class.create!(user_id: user.id, skill_id: skill.id)
        different = described_class.new(user_id: user.id, skill_id: other_skill.id)
        expect(different).to be_valid
      end
    end
  end
end

# ====================================================================== #
# Escalated::Skill
# ====================================================================== #
RSpec.describe Escalated::Skill, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_many(:agent_skills).class_name('Escalated::AgentSkill').dependent(:destroy) }

    it 'has many agents through agent_skills' do
      skill = described_class.create!(name: 'Test Skill', slug: 'test_skill_assoc')
      user = create(:user)
      Escalated::AgentSkill.create!(user: user, skill: skill)

      expect(skill.agents).to include(user)
    end
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject { create(:escalated_skill) }

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Callbacks
  # ------------------------------------------------------------------ #
  describe 'callbacks' do
    describe '#generate_slug' do
      it 'auto-generates slug from name when slug is blank' do
        skill = build(:escalated_skill, name: 'Technical Support', slug: nil)
        skill.valid?
        expect(skill.slug).to eq('technical_support')
      end

      it 'does not override an existing slug' do
        skill = build(:escalated_skill, name: 'Sales', slug: 'custom_sales')
        skill.valid?
        expect(skill.slug).to eq('custom_sales')
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      skill = build(:escalated_skill, name: 'Networking')
      expect(skill.to_s).to eq('Networking')
    end
  end
end

# ====================================================================== #
# Escalated::AgentCapacity
# ====================================================================== #
RSpec.describe Escalated::AgentCapacity, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    context 'uniqueness' do
      it 'prevents duplicate user-channel combinations' do
        user = create(:user)
        described_class.create!(user_id: user.id, channel: 'default', max_concurrent: 10, current_count: 0)
        duplicate = described_class.new(user_id: user.id, channel: 'default', max_concurrent: 5, current_count: 0)
        expect(duplicate).not_to be_valid
      end

      it 'allows the same user with different channels' do
        user = create(:user)
        described_class.create!(user_id: user.id, channel: 'default', max_concurrent: 10, current_count: 0)
        different = described_class.new(user_id: user.id, channel: 'email', max_concurrent: 5, current_count: 0)
        expect(different).to be_valid
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#load_percentage' do
    let(:user) { create(:user) }

    it 'returns the load percentage' do
      capacity = described_class.new(user: user, max_concurrent: 10, current_count: 5)
      expect(capacity.load_percentage).to eq(50)
    end

    it 'returns 0 when max_concurrent is zero' do
      capacity = described_class.new(user: user, max_concurrent: 0, current_count: 0)
      expect(capacity.load_percentage).to eq(0)
    end

    it 'returns 0 when max_concurrent is nil' do
      capacity = described_class.new(user: user, max_concurrent: nil, current_count: 0)
      expect(capacity.load_percentage).to eq(0)
    end

    it 'rounds to the nearest integer' do
      capacity = described_class.new(user: user, max_concurrent: 3, current_count: 1)
      expect(capacity.load_percentage).to eq(33)
    end
  end

  describe '#has_capacity?' do
    let(:user) { create(:user) }

    it 'returns true when current count is below max' do
      capacity = described_class.new(user: user, max_concurrent: 5, current_count: 3)
      expect(capacity.has_capacity?).to be(true)
    end

    it 'returns false when at capacity' do
      capacity = described_class.new(user: user, max_concurrent: 5, current_count: 5)
      expect(capacity.has_capacity?).to be(false)
    end

    it 'returns false when current count exceeds max' do
      capacity = described_class.new(user: user, max_concurrent: 5, current_count: 6)
      expect(capacity.has_capacity?).to be(false)
    end
  end
end

# ====================================================================== #
# Escalated::Webhook
# ====================================================================== #
RSpec.describe Escalated::Webhook, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_many(:deliveries).class_name('Escalated::WebhookDelivery').dependent(:destroy) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:url) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.active' do
      it 'returns only active webhooks' do
        active = described_class.create!(url: 'https://hooks.example.com/a', active: true)
        _inactive = described_class.create!(url: 'https://hooks.example.com/b', active: false)

        result = described_class.active
        expect(result).to include(active)
        expect(result).not_to include(_inactive)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#subscribed_to?' do
    let(:webhook) { described_class.new(url: 'https://example.com', events: %w[ticket.created ticket.updated]) }

    it 'returns true when the event is in the events list' do
      expect(webhook.subscribed_to?('ticket.created')).to be(true)
    end

    it 'returns false when the event is not in the events list' do
      expect(webhook.subscribed_to?('ticket.deleted')).to be(false)
    end

    it 'accepts symbol event names' do
      expect(webhook.subscribed_to?(:'ticket.created')).to be(true)
    end
  end

  describe '#to_s' do
    it 'returns the url' do
      webhook = described_class.new(url: 'https://hooks.example.com/notify')
      expect(webhook.to_s).to eq('https://hooks.example.com/notify')
    end
  end
end

# ====================================================================== #
# Escalated::WebhookDelivery
# ====================================================================== #
RSpec.describe Escalated::WebhookDelivery, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:webhook).class_name('Escalated::Webhook') }
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#success?' do
    let(:webhook) { Escalated::Webhook.create!(url: 'https://test.example.com/hook', active: true) }

    it 'returns true for 200 response code' do
      delivery = described_class.new(webhook: webhook, response_code: 200)
      expect(delivery.success?).to be(true)
    end

    it 'returns true for 201 response code' do
      delivery = described_class.new(webhook: webhook, response_code: 201)
      expect(delivery.success?).to be(true)
    end

    it 'returns true for 299 response code' do
      delivery = described_class.new(webhook: webhook, response_code: 299)
      expect(delivery.success?).to be(true)
    end

    it 'returns false for 500 response code' do
      delivery = described_class.new(webhook: webhook, response_code: 500)
      expect(delivery.success?).to be(false)
    end

    it 'returns false for nil response code' do
      delivery = described_class.new(webhook: webhook, response_code: nil)
      expect(delivery.success?).to be(false)
    end

    it 'returns false for 404 response code' do
      delivery = described_class.new(webhook: webhook, response_code: 404)
      expect(delivery.success?).to be(false)
    end

    it 'returns false for 100 response code' do
      delivery = described_class.new(webhook: webhook, response_code: 100)
      expect(delivery.success?).to be(false)
    end
  end
end

# ====================================================================== #
# Escalated::Automation
# ====================================================================== #
RSpec.describe Escalated::Automation, type: :model do
  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  # ------------------------------------------------------------------ #
  # Scopes
  # ------------------------------------------------------------------ #
  describe 'scopes' do
    describe '.active' do
      it 'returns only active automations ordered by position' do
        active_second = described_class.create!(name: 'Rule B', active: true, position: 2)
        active_first = described_class.create!(name: 'Rule A', active: true, position: 1)
        _inactive = described_class.create!(name: 'Rule C', active: false, position: 0)

        result = described_class.active
        expect(result).to include(active_first, active_second)
        expect(result).not_to include(_inactive)
        expect(result.first).to eq(active_first)
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      automation = described_class.new(name: 'Auto-assign urgent tickets')
      expect(automation.to_s).to eq('Auto-assign urgent tickets')
    end
  end
end

# ====================================================================== #
# Escalated::TwoFactor
# ====================================================================== #
RSpec.describe Escalated::TwoFactor, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    context 'uniqueness' do
      subject { described_class.create!(user: user, secret: 'test_secret') }

      let(:user) { create(:user) }


      it { is_expected.to validate_uniqueness_of(:user_id) }
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#confirmed?' do
    it 'returns true when confirmed_at is present' do
      user = create(:user)
      two_factor = described_class.new(user: user, confirmed_at: 1.hour.ago)
      expect(two_factor.confirmed?).to be(true)
    end

    it 'returns false when confirmed_at is nil' do
      user = create(:user)
      two_factor = described_class.new(user: user, confirmed_at: nil)
      expect(two_factor.confirmed?).to be(false)
    end
  end
end

# ====================================================================== #
# Escalated::CustomObject
# ====================================================================== #
RSpec.describe Escalated::CustomObject, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to have_many(:records).class_name('Escalated::CustomObjectRecord').dependent(:destroy) }
  end

  # ------------------------------------------------------------------ #
  # Validations
  # ------------------------------------------------------------------ #
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }

    context 'uniqueness' do
      subject { described_class.create!(name: 'Test Object', slug: 'test_object_uniq') }

      it { is_expected.to validate_uniqueness_of(:slug) }
    end
  end

  # ------------------------------------------------------------------ #
  # Instance methods
  # ------------------------------------------------------------------ #
  describe '#to_s' do
    it 'returns the name' do
      obj = described_class.new(name: 'Asset Tracker')
      expect(obj.to_s).to eq('Asset Tracker')
    end
  end

  describe 'dependent destroy' do
    it 'destroys associated records when custom object is destroyed' do
      obj = described_class.create!(name: 'Test', slug: 'test_dep_destroy')
      Escalated::CustomObjectRecord.create!(object: obj, data: { 'name' => 'Item' })
      Escalated::CustomObjectRecord.create!(object: obj, data: { 'name' => 'Item 2' })

      expect { obj.destroy }.to change(Escalated::CustomObjectRecord, :count).by(-2)
    end
  end
end

# ====================================================================== #
# Escalated::CustomObjectRecord
# ====================================================================== #
RSpec.describe Escalated::CustomObjectRecord, type: :model do
  # ------------------------------------------------------------------ #
  # Associations
  # ------------------------------------------------------------------ #
  describe 'associations' do
    it { is_expected.to belong_to(:object).class_name('Escalated::CustomObject') }
  end

  # ------------------------------------------------------------------ #
  # Record creation
  # ------------------------------------------------------------------ #
  describe 'record creation' do
    it 'can be created with a custom object' do
      custom_object = Escalated::CustomObject.create!(name: 'Test Obj', slug: 'test_obj_rec')
      record = described_class.create!(object: custom_object, data: { 'name' => 'Test' })

      expect(record).to be_persisted
      expect(record.object).to eq(custom_object)
    end
  end

  describe 'dependent destroy' do
    it 'is destroyed when the parent custom object is destroyed' do
      custom_object = Escalated::CustomObject.create!(name: 'Destroyable', slug: 'destroyable_obj')
      described_class.create!(object: custom_object, data: { 'name' => 'Record 1' })
      described_class.create!(object: custom_object, data: { 'name' => 'Record 2' })
      described_class.create!(object: custom_object, data: { 'name' => 'Record 3' })

      expect { custom_object.destroy }.to change(described_class, :count).by(-3)
    end
  end
end
