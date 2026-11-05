# frozen_string_literal: true

require 'rails_helper'

# The embed settings (ADR 2026-11-05-embeddable-admin): config.embed, the
# ESCALATED_EMBED* env vars, config.embed_admin, and the Rack middleware the
# engine installs for iframe framing.
RSpec.describe Escalated::Support::EmbedConfig do
  around do |example|
    previous = Escalated.configuration.embed
    example.run
  ensure
    Escalated.configuration.embed = previous
  end

  def with_env(vars)
    saved = vars.keys.index_with { |key| ENV.fetch(key, nil) }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  it 'is off with every documented default' do
    expect(Escalated::Configuration.new.embed).to eq(
      enabled: false, mode: 'layout', prefix: 'admin/support', middleware: nil, replace_admin_gate: false,
      layout: nil, root_view: nil, frame_ancestors: []
    )
  end

  it 'reads the env vars' do
    with_env('ESCALATED_EMBED' => 'true', 'ESCALATED_EMBED_MODE' => 'iframe',
             'ESCALATED_EMBED_PREFIX' => '/console/support/',
             'ESCALATED_EMBED_FRAME_ANCESTORS' => 'https://a.example, https://b.example:8443') do
      Escalated.configuration.embed = Escalated::Configuration.new.embed

      expect(described_class.enabled?).to be(true)
      expect(described_class.mode).to eq('iframe')
      expect(described_class.prefix).to eq('console/support')
      expect(described_class.frame_ancestors).to eq(%w[https://a.example https://b.example:8443])
    end
  end

  it 'fills keys the host left out from the defaults' do
    Escalated.configuration.embed = { enabled: true }

    expect(described_class.mode).to eq('layout')
    expect(described_class.prefix).to eq('admin/support')
    expect(described_class.replace_admin_gate?).to be(false)
  end

  it 'needs the screens' do
    Escalated.configuration.embed = { enabled: true }
    allow(Escalated.configuration).to receive(:ui_enabled).and_return(false)

    expect(described_class.enabled?).to be(false)
  end

  it 'falls back to layout mode for an unknown mode' do
    Escalated.configuration.embed = { enabled: true, mode: 'popup' }

    expect(described_class.mode).to eq('layout')
  end

  it 'keeps only exact http(s) origins' do
    Escalated.configuration.embed = {
      enabled: true,
      frame_ancestors: ['HTTPS://Admin.Example.com/', 'https://admin.example.com', '*', 'https://*.x.example',
                        'ftp://files.example', 'https://u:p@admin.example', 'https://admin.example/path', '', nil]
    }

    expect(described_class.frame_ancestors).to eq(['https://admin.example.com'])
    expect(described_class.frame_ancestors_directive).to eq("frame-ancestors 'self' https://admin.example.com")
  end

  describe 'Configuration#embed_admin' do
    it 'writes the embed settings and turns embedding on' do
      host_gate = ->(controller) { controller.head(:forbidden) }
      Escalated.configuration.embed_admin(prefix: 'console/support', middleware: [:authenticate_admin!, host_gate],
                                          layout: 'Layouts/ConsoleLayout')

      expect(Escalated.configuration.embed).to eq(
        enabled: true, mode: 'layout', prefix: 'console/support', middleware: [:authenticate_admin!, host_gate],
        replace_admin_gate: false, layout: 'Layouts/ConsoleLayout', root_view: nil, frame_ancestors: []
      )
    end

    it 'is also Escalated.embed_admin' do
      Escalated.embed_admin(mode: 'iframe', frame_ancestors: ['https://admin.example.com'])

      expect(described_class.enabled?).to be(true)
      expect(described_class.mode).to eq('iframe')
    end

    it 'refuses an unknown mode' do
      expect { Escalated.configuration.embed_admin(mode: 'popup') }.to raise_error(ArgumentError, /layout.*iframe/)
    end

    it 'refuses to replace the admin gate without host guards' do
      expect { Escalated.configuration.embed_admin(replace_admin_gate: true, middleware: []) }
        .to raise_error(ArgumentError, /middleware/)
    end
  end

  describe 'the iframe framing middleware' do
    def stack
      ActionDispatch::MiddlewareStack.new { |middleware| middleware.use Rack::Head }
    end

    it 'is installed at the top of the stack while embedding is on' do
      Escalated.configuration.embed = { enabled: true }
      installed = stack
      Escalated::Engine.install_embed_frame_headers(installed)

      expect(installed.first.klass).to eq(Escalated::EmbedFrameHeaders)
    end

    it 'is not installed while embedding is off' do
      Escalated.configuration.embed = { enabled: false }
      installed = stack
      Escalated::Engine.install_embed_frame_headers(installed)

      expect(installed.map(&:klass)).to eq([Rack::Head])
    end

    it 'touches nothing on a response that is not an embedded one' do
      Escalated.configuration.embed = { enabled: true, mode: 'iframe' }
      inner = ->(_env) { [200, { 'x-frame-options' => 'DENY' }, ['ok']] }
      _, headers, = Escalated::EmbedFrameHeaders.new(inner).call(Rack::MockRequest.env_for('/'))

      expect(headers).to eq('x-frame-options' => 'DENY')
    end
  end
end
