# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::WidgetController do
  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    Escalated::EscalatedSetting.set('widget_enabled', '1')
  end

  describe 'widget settings' do
    it 'recognizes widget_enabled setting' do
      expect(Escalated::EscalatedSetting.get_bool('widget_enabled')).to be true
    end

    it 'recognizes widget_color setting' do
      Escalated::EscalatedSetting.set('widget_color', '#FF0000')
      expect(Escalated::EscalatedSetting.get('widget_color')).to eq('#FF0000')
    end

    it 'recognizes widget_position setting' do
      Escalated::EscalatedSetting.set('widget_position', 'bottom-left')
      expect(Escalated::EscalatedSetting.get('widget_position')).to eq('bottom-left')
    end

    it 'recognizes widget_greeting setting' do
      Escalated::EscalatedSetting.set('widget_greeting', 'Hello!')
      expect(Escalated::EscalatedSetting.get('widget_greeting')).to eq('Hello!')
    end
  end

  describe 'widget disabled behavior' do
    it 'returns false when widget is not enabled' do
      Escalated::EscalatedSetting.set('widget_enabled', '0')
      expect(Escalated::EscalatedSetting.get_bool('widget_enabled')).to be false
    end

    it 'defaults to disabled when setting is not present' do
      # Clear any existing setting
      Escalated::EscalatedSetting.where(key: 'widget_enabled').destroy_all
      expect(Escalated::EscalatedSetting.get_bool('widget_enabled', default: false)).to be false
    end
  end

  describe 'article search for widget' do
    let!(:published_article) { create(:escalated_article, :published, title: 'Getting Started Guide') }
    let!(:draft_article) { create(:escalated_article, title: 'Draft Article') }

    it 'returns only published articles' do
      results = Escalated::Article.published
      expect(results).to include(published_article)
      expect(results).not_to include(draft_article)
    end

    it 'searches articles by title' do
      results = Escalated::Article.published.search('Getting Started')
      expect(results).to include(published_article)
    end

    it 'does not return draft articles in search' do
      results = Escalated::Article.published.search('Draft')
      expect(results).not_to include(draft_article)
    end
  end

  describe 'ticket creation from widget' do
    it 'creates a ticket via TicketService' do
      expect do
        Escalated::Services::TicketService.create(
          subject: 'Widget ticket',
          description: 'Created from widget',
          guest_name: 'John',
          guest_email: 'john@example.com',
          priority: :medium,
          metadata: { 'source' => 'widget' }
        )
      end.to change(Escalated::Ticket, :count).by(1)
    end

    it 'stores widget source in metadata' do
      ticket = Escalated::Services::TicketService.create(
        subject: 'Widget ticket',
        description: 'Created from widget',
        guest_name: 'John',
        guest_email: 'john@example.com',
        priority: :medium,
        metadata: { 'source' => 'widget' }
      )
      expect(ticket.metadata['source']).to eq('widget')
    end
  end

  describe 'ticket lookup by guest token' do
    let(:ticket) { create(:escalated_ticket, guest_token: SecureRandom.hex(16)) }

    it 'finds ticket by guest_token' do
      found = Escalated::Ticket.find_by!(guest_token: ticket.guest_token)
      expect(found).to eq(ticket)
    end

    it 'raises RecordNotFound for invalid token' do
      expect do
        Escalated::Ticket.find_by!(guest_token: 'invalid_token')
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
