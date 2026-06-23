# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Newsletter::Renderer do
  subject(:renderer) { described_class.new }

  let(:contact) { create(:escalated_contact, name: 'Ada Lovelace', email: 'ada@example.com') }
  let(:newsletter) do
    create(:escalated_newsletter,
           body_markdown: '# Hello {{ contact.first_name }} {{ contact.does_not_exist }}',
           status: 'sending')
  end
  let(:delivery) { create(:escalated_newsletter_delivery, newsletter: newsletter, contact: contact, status: 'sent') }

  before do
    allow(Escalated.configuration).to receive_messages(
      app_url: 'https://app.example.test',
      newsletter_markdown_renderer: lambda { |markdown|
        markdown
        .sub(/\A# (.*)/, '<h1>\\1</h1>')
        .gsub(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\\2">\\1</a>')
      },
      newsletter_tracking_enabled?: true
    )
  end

  it 'renders markdown, merge fields, rewritten links, and a tracking pixel' do
    newsletter.update!(body_markdown: '# Hello {{ contact.first_name }} [Site](https://example.com)')

    html = renderer.render(delivery)

    expect(html).to include('<h1>Hello Ada')
    expect(html).not_to include('{{')
    expect(html).to include("/escalated/n/c/#{delivery.tracking_token}?u=")
    expect(html).not_to include('href="https://example.com"')
    expect(html).to include("/escalated/n/o/#{delivery.tracking_token}.gif")
  end

  it 'does not rewrite links or inject a pixel when tracking is disabled' do
    allow(Escalated.configuration).to receive(:newsletter_tracking_enabled?).and_return(false)
    newsletter.update!(body_markdown: '[Site](https://example.com)')

    html = renderer.render(delivery)

    expect(html).to include('https://example.com')
    expect(html).not_to include("/escalated/n/c/#{delivery.tracking_token}")
    expect(html).not_to include("/escalated/n/o/#{delivery.tracking_token}.gif")
  end

  it 'strips javascript links and keeps unsubscribe links untracked' do
    unsubscribe = "https://app.example.test/escalated/n/u/#{delivery.tracking_token}"
    newsletter.update!(body_markdown: %([Unsafe](javascript:alert(1)) [Unsub](#{unsubscribe})))

    html = renderer.render(delivery)

    expect(html).not_to include('javascript:alert')
    expect(html).to include(unsubscribe)
  end
end
