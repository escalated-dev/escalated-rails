# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Support::WidgetOrigins do
  describe '.normalize_pattern' do
    {
      'https://Shop.Example.com' => 'https://shop.example.com',
      'https://shop.example.com/' => 'https://shop.example.com',
      'https://shop.example.com:443' => 'https://shop.example.com',
      'http://localhost:5173' => 'http://localhost:5173',
      'https://*.example.com' => 'https://*.example.com',
      'https://*.example.com:8443' => 'https://*.example.com:8443',
      'https://shop.example.com/checkout' => nil,
      'https://shop.example.com?x=1' => nil,
      'shop.example.com' => nil,
      '*' => nil,
      'https://*' => nil,
      'https://a.*.example.com' => nil,
      'ftp://shop.example.com' => nil,
      'https://user@shop.example.com' => nil
    }.each do |entry, expected|
      it "turns #{entry.inspect} into #{expected.inspect}" do
        expect(described_class.normalize_pattern(entry)).to eq(expected)
      end
    end
  end

  describe '.allows?' do
    before do
      allow(Escalated.configuration).to receive(:widget_allowed_origins)
        .and_return(['https://shop.example.com', 'https://*.brand.test', 'http://localhost:5173'])
    end

    {
      'https://shop.example.com' => true,
      'https://SHOP.example.com:443' => true,
      'http://shop.example.com' => false,
      'https://shop.example.com:8443' => false,
      'https://help.brand.test' => true,
      'https://a.b.brand.test' => true,
      'https://brand.test' => false,
      'https://notbrand.test' => false,
      'https://help.brand.test.evil.com' => false,
      'http://localhost:5173' => true,
      'http://localhost' => false,
      'null' => false
    }.each do |origin, allowed|
      it "#{allowed ? 'allows' : 'refuses'} #{origin}" do
        expect(described_class.allows?(origin)).to be(allowed)
      end
    end
  end

  it 'merges the config list with the admin setting' do
    allow(Escalated.configuration).to receive(:widget_allowed_origins).and_return(['https://shop.example.com'])
    Escalated::EscalatedSetting.set('widget_allowed_origins',
                                    "https://blog.example.com, https://bad.example.com/path\n")

    expect(described_class.configured).to eq(['https://shop.example.com', 'https://blog.example.com'])
  end

  it 'reads a comma separated environment list into the configuration default' do
    original = ENV.fetch('ESCALATED_WIDGET_ALLOWED_ORIGINS', nil)
    ENV['ESCALATED_WIDGET_ALLOWED_ORIGINS'] = 'https://shop.example.com, https://*.brand.test'

    expect(Escalated::Configuration.new.widget_allowed_origins)
      .to eq(['https://shop.example.com', 'https://*.brand.test'])
  ensure
    ENV['ESCALATED_WIDGET_ALLOWED_ORIGINS'] = original
  end

  describe '.cross_origin' do
    def request_with(origin)
      env = Rack::MockRequest.env_for('https://help.example.com/support/widget/config')
      env['HTTP_ORIGIN'] = origin if origin
      ActionDispatch::Request.new(env)
    end

    {
      nil => nil,
      'null' => nil,
      'https://help.example.com' => nil,
      'https://help.example.com:443' => nil,
      'https://shop.example.com' => 'https://shop.example.com',
      'http://help.example.com' => 'http://help.example.com'
    }.each do |origin, expected|
      it "reports #{expected.inspect} for an Origin of #{origin.inspect}" do
        expect(described_class.cross_origin(request_with(origin))).to eq(expected)
      end
    end
  end
end

RSpec.describe Escalated::Support::WidgetMetadata do
  it 'keeps a flat map of short scalar values' do
    clean = described_class.sanitize(
      {
        'order_number' => 'A-1001', 'items' => 3, 'total' => 12.5, 'gift' => false,
        'nested' => { 'x' => 1 }, 'list' => [1], 'none' => nil, 'bad key!' => 'x',
        'note' => " #{'a' * 600} ", 'page_url' => 'javascript:alert(1)', 'embedded_on' => 'https://spoofed.example'
      },
      origin: nil
    )

    expect(clean).to eq(
      'order_number' => 'A-1001', 'items' => 3, 'total' => 12.5, 'gift' => false, 'note' => 'a' * 500
    )
  end

  it 'keeps at most 25 entries and records the embedding origin' do
    clean = described_class.sanitize((1..40).index_by { |i| "k#{i}" }, origin: 'https://shop.example.com')

    expect(clean.size).to eq(26)
    expect(clean['embedded_on']).to eq('https://shop.example.com')
  end

  it 'keeps a web page_url and returns nil when nothing is left' do
    expect(described_class.sanitize({ 'page_url' => 'https://shop.example.com/cart' }, origin: nil))
      .to eq('page_url' => 'https://shop.example.com/cart')
    expect(described_class.sanitize({ 'page_url' => 'ftp://shop.example.com/cart' }, origin: nil)).to be_nil
    expect(described_class.sanitize(nil, origin: nil)).to be_nil
  end

  it 'rejects metadata that is not an object or has more than 50 keys' do
    expect(described_class.invalid?(nil)).to be(false)
    expect(described_class.invalid?({ 'a' => 1 })).to be(false)
    expect(described_class.invalid?('order=1')).to be(true)
    expect(described_class.invalid?([1, 2])).to be(true)
    expect(described_class.invalid?((1..51).index_by { |i| "k#{i}" })).to be(true)
  end
end
