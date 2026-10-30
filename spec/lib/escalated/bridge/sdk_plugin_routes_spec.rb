# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Bridge::SdkPluginRoutes do
  let(:bridge) { instance_double(Escalated::Bridge::PluginBridge, booted?: true, manifests: manifests) }
  let(:manifests) { { '@twin/a' => {}, 'twin/a' => {}, 'solo' => { 'x' => 1 } } }

  before do
    allow(Escalated).to receive(:plugin_bridge).and_return(bridge)
    allow(Escalated::Bridge::SdkPluginActivation).to receive(:active?).and_return(true)
  end

  it 'serves neither of two plugins whose names share a slug' do
    expect(described_class.active_plugin('twin--a')).to be_nil
    expect(described_class.active_plugin('solo')).to eq(['solo', { 'x' => 1 }])
  end

  it 'matches manifest paths with :param segments, list or legacy map' do
    list = [{ 'method' => 'post', 'path' => '/items/:id' }]
    expect(described_class.match(list, 'POST', '/items/7')).to eq([{ 'method' => 'POST', 'path' => '/items/:id' },
                                                                   { 'id' => '7' }])
    expect(described_class.match(list, 'GET', '/items/7')).to be_nil
    expect(described_class.match(list, 'POST', '/items/7/more')).to be_nil
    expect(described_class.match({ 'GET /ping' => {} }, 'GET', '/ping').last).to eq({})
    expect(described_class.match([{ 'method' => 'GET', 'path' => '/../x' }], 'GET', '/../x')).to be_nil
  end
end
