# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# The host's user model says who is staff through escalated_agent? and
# escalated_admin?. Without them every staff request used to be turned away
# with "not an agent"; now the request fails with an error naming the contract,
# and `escalated:doctor` reports it before anyone clicks.
RSpec.describe 'Host user model contract', type: :request do
  # A host user model that never had the role methods added.
  let(:bare_user_class) do
    Class.new do
      def self.name = 'BareUser'
      def id = 42
      def email = 'bare@example.test'
      def name = 'Bare'
    end
  end
  let(:bare_user) { bare_user_class.new }

  before { allow(Escalated.configuration).to receive(:notification_channels).and_return([]) }

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  describe 'staff screens' do
    it 'raises an error naming the contract for an agent screen' do
      sign_in_as(bare_user)

      expect { get '/support/agent/tickets' }.to raise_error(
        Escalated::UserModelNotConfigured, /BareUser does not implement .*#escalated_agent\?.*#escalated_admin\?/
      )
    end

    it 'raises it for an admin screen too' do
      sign_in_as(bare_user)

      expect { get '/support/admin/settings' }.to raise_error(Escalated::UserModelNotConfigured, /escalated:doctor/)
    end

    it 'still turns away a configured user who is not staff' do
      sign_in_as(create(:user, email: 'not-staff@example.test'))

      get '/support/agent/tickets'
      expect(response).to redirect_to('/')
    end

    it 'tells a model with the role methods from one without' do
      expect(Escalated::SetupCheck.staff_contract?(bare_user)).to be(false)
      expect(Escalated::SetupCheck.staff_contract?(create(:user, email: 'c@example.test'))).to be(true)
    end
  end

  describe Escalated::SetupCheck do
    it 'passes the dummy app User' do
      results = described_class.user_model_results

      expect(results.pluck(:level)).to eq([:ok])
    end

    it 'reports each missing piece of the contract' do
      stub_const('BareUser', bare_user_class)
      allow(Escalated.configuration).to receive(:user_class).and_return('BareUser')

      messages = described_class.user_model_results.map { |r| [r[:level], r[:message]] }

      expect(messages).to include(
        [:error, a_string_including('BareUser#escalated_agent? is not defined')],
        [:error, a_string_including('BareUser#escalated_admin? is not defined')],
        [:warning, a_string_including('BareUser.escalated_agents is not defined')]
      )
    end

    it 'reports a user_class that does not load' do
      allow(Escalated.configuration).to receive(:user_class).and_return('NoSuchUser')

      expect(described_class.user_model_results).to eq(
        [{ level: :error, message: 'config.user_class "NoSuchUser" is not a loadable class.' }]
      )
    end

    it 'includes the scheduler heartbeat' do
      expect(described_class.run.last).to include(level: :warning, message: /recurring jobs are not running/)
    end
  end

  describe 'rake escalated:doctor' do
    around do |example|
      original = Rake.application
      Rake.application = Rake::Application.new
      Rails.application.load_tasks
      example.run
    ensure
      Rake.application = original
    end

    it 'prints the checks and passes for a set-up app' do
      expect { Rake::Task['escalated:doctor'].invoke }.to output(/\[OK\] User implements/).to_stdout
    end

    it 'fails when the user model has no role methods' do
      stub_const('BareUser', bare_user_class)
      allow(Escalated.configuration).to receive(:user_class).and_return('BareUser')

      expect do
        expect { Rake::Task['escalated:doctor'].invoke }.to raise_error(SystemExit)
      end.to output(/\[FAIL\] BareUser#escalated_agent\? is not defined/).to_stdout
    end
  end
end
