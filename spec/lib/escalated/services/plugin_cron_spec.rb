# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::PluginCron do
  # 2026-10-29 is a Thursday; 2026-11-01 a Sunday.
  [
    ['* * * * *', '2026-10-29T13:37:00Z', true],
    ['37 13 * * *', '2026-10-29T13:37:45Z', true],
    ['38 13 * * *', '2026-10-29T13:37:00Z', false],
    ['*/15 * * * *', '2026-10-29T13:45:00Z', true],
    ['*/15 * * * *', '2026-10-29T13:46:00Z', false],
    ['0-10/5 9-17 * * *', '2026-10-29T09:10:00Z', true],
    ['0-10/5 9-17 * * *', '2026-10-29T18:10:00Z', false],
    ['1,2,3 * * * *', '2026-10-29T13:02:00Z', true],
    ['0 9 * * thu', '2026-10-29T09:00:00Z', true],
    ['0 9 * * MON-WED', '2026-10-29T09:00:00Z', false],
    ['0 0 * * 7', '2026-11-01T00:00:00Z', true],
    ['0 0 1 nov *', '2026-11-01T00:00:00Z', true],
    ['0 0 13 * 4', '2026-10-29T00:00:00Z', true],
    ['0 0 13 * 5', '2026-10-29T00:00:00Z', false],
    ['0 0 29 * *', '2026-10-29T00:00:00Z', true],
    ['0 9 * * *', '2026-10-29T05:00:00-04:00', true],
    ['@hourly', '2026-10-29T13:00:00Z', true],
    ['@daily', '2026-10-29T13:00:00Z', false],
    ['@weekly', '2026-11-01T00:00:00Z', true]
  ].each do |expression, at, due|
    it "#{due ? 'runs' : 'does not run'} '#{expression}' at #{at} (UTC)" do
      expect(described_class.due?(expression, Time.iso8601(at))).to be(due)
    end
  end

  ['', '* * * *', '61 * * * *', '* * * * * *', 'a b c d e', '*/0 * * * *', '5-1 * * * *'].each do |bad|
    it "refuses '#{bad}'" do
      expect { described_class.due?(bad, Time.now.utc) }.to raise_error(ArgumentError)
    end
  end
end
