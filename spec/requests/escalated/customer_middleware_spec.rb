# frozen_string_literal: true

require 'rails_helper'

# config.customer_middleware: extra guards on the customer portal and the
# customer knowledge base, for installs where only staff use Escalated.
RSpec.describe 'Customer route guards (config.customer_middleware)', type: :request do
  let(:customer) { create(:user, email: 'customer-guard@example.test') }
  let(:agent) { create(:user, :agent, email: 'agent-guard@example.test') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated::EscalatedSetting.set('knowledge_base_enabled', '1')
    Escalated::EscalatedSetting.set('knowledge_base_public', '1')
  end

  after { Escalated.configuration.customer_middleware = [] }

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def customer_paths
    ['/support/customer/tickets', '/support/customer/tickets/new', '/support/customer/kb']
  end

  it 'is empty by default' do
    expect(Escalated::Configuration.new.customer_middleware).to eq([])
  end

  it 'lets any signed-in user in by default' do
    sign_in_as(customer)

    customer_paths.each do |path|
      get path
      expect(response).to have_http_status(:ok), "GET #{path} answered #{response.status}"
    end
  end

  context 'with [:require_staff!]' do
    before { Escalated.configuration.customer_middleware = [:require_staff!] }

    it 'turns away a signed-in user who is not staff' do
      sign_in_as(customer)

      customer_paths.each do |path|
        get path
        expect(response).to redirect_to('/'), "GET #{path} answered #{response.status}"
      end

      post '/support/customer/tickets', params: { subject: 'Hi', description: 'There' }
      expect(response).to redirect_to('/')
      expect(Escalated::Ticket.count).to eq(0)
    end

    it 'lets staff in' do
      sign_in_as(agent)

      customer_paths.each do |path|
        get path
        expect(response).to have_http_status(:ok), "GET #{path} answered #{response.status}"
      end
    end
  end

  it 'accepts a callable guard and stops at the first that responds' do
    Escalated.configuration.customer_middleware = [
      ->(controller) { controller.head :forbidden unless controller.send(:current_user)&.escalated_agent? },
      ->(_controller) { raise 'the second guard must not run' }
    ]
    sign_in_as(customer)

    get '/support/customer/tickets'
    expect(response).to have_http_status(:forbidden)
    get '/support/customer/kb'
    expect(response).to have_http_status(:forbidden)
  end

  it 'leaves the agent screens to their own gate' do
    Escalated.configuration.customer_middleware = [->(controller) { controller.head :forbidden }]
    sign_in_as(agent)

    get '/support/agent/tickets'
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a guard name the controller does not have' do
    Escalated.configuration.customer_middleware = [:no_such_guard!]
    sign_in_as(customer)
    config = Rails.application.env_config
    previous = config['action_dispatch.show_exceptions']
    config['action_dispatch.show_exceptions'] = :none # let the error reach the spec

    expect { get '/support/customer/tickets' }.to raise_error(ArgumentError, /customer_middleware :no_such_guard!/)
  ensure
    config['action_dispatch.show_exceptions'] = previous if config
  end
end
