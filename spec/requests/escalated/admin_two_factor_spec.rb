# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The enrolment the shared Admin/Settings/TwoFactor page drives by itself: it
# posts to the setup route and reads flash.two_factor_setup.qr_uri, then posts
# { code } to the confirm route and reads flash.two_factor_confirmed.recovery_codes.
RSpec.describe 'Admin two-factor enrolment', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-two-factor@example.test') }
  let(:totp) { Escalated::Services::TwoFactorService.new }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    sign_in_as(admin)
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  # Inertia HTML responses JSON-encode the page inside data-page="..." (HTML-escaped).
  def inertia_props_from(body)
    encoded = body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))['props']
  end

  def codes_accepted_now(secret)
    step = Time.now.to_i / Escalated::Services::TwoFactorService::PERIOD
    (-1..1).map { |offset| totp.send(:generate_totp, secret, step + offset) }
  end

  def start_enrolment
    post '/support/admin/settings/two_factor/setup'
    Escalated::TwoFactor.find_by(user_id: admin.id)
  end

  it 'stores an unconfirmed secret and gives the page its QR code' do
    two_factor = start_enrolment

    expect(two_factor).to be_present
    expect(two_factor).not_to be_confirmed
    expect(two_factor.recovery_codes.length).to eq(8)

    follow_redirect!
    props = inertia_props_from(response.body)
    expect(props['pending']).to be(true)
    expect(props['enabled']).to be(false)
    expect(props.dig('flash', 'two_factor_setup', 'qr_uri')).to include("secret=#{two_factor.secret}")
  end

  it 'confirms with a valid code and hands back the recovery codes' do
    two_factor = start_enrolment

    post '/support/admin/settings/two_factor/confirm', params: { code: codes_accepted_now(two_factor.secret).first }

    expect(two_factor.reload).to be_confirmed
    follow_redirect!
    props = inertia_props_from(response.body)
    expect(props['enabled']).to be(true)
    expect(props.dig('flash', 'two_factor_confirmed', 'recovery_codes')).to eq(two_factor.recovery_codes)
  end

  it 'does not replace an enrolment that is already confirmed' do
    confirmed = create(:escalated_two_factor, user: admin)

    post '/support/admin/settings/two_factor/setup'

    expect(response).to redirect_to('/support/admin/settings/two_factor')
    expect(Escalated::TwoFactor.where(user_id: admin.id).pluck(:id)).to eq([confirmed.id])
    expect(confirmed.reload).to be_confirmed
  end

  it 'refuses a wrong code and leaves enrolment pending' do
    two_factor = start_enrolment
    wrong = (%w[000000 111111 222222 333333] - codes_accepted_now(two_factor.secret)).first

    post '/support/admin/settings/two_factor/confirm', params: { code: wrong }

    expect(two_factor.reload).not_to be_confirmed
  end
end
