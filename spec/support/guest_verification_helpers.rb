# frozen_string_literal: true

# Mailbox proof for request specs: asks for a code the way the shared
# frontend does, then reads it from the email, the only place it appears.
module GuestVerificationHelpers
  def last_guest_code
    mail = ActionMailer::Base.deliveries.last
    body = mail.text_part ? mail.text_part.body.to_s : mail.body.to_s
    body[/\b\d{8}\b/]
  end

  # {verification_id:, verification_code:} for POSTing with a guest request.
  def guest_proof(email, purpose = 'ticket', prefix: '/support/widget', headers: {})
    headers = { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json',
                'REMOTE_ADDR' => "10.9.#{rand(250)}.#{rand(250)}" }.merge(headers)
    post "#{prefix}/verification", params: { email: email, purpose: purpose }.to_json, headers: headers
    raise "verification request failed: #{response.status} #{response.body}" unless response.status == 202

    { verification_id: response.parsed_body['verification_id'], verification_code: last_guest_code }
  end
end

RSpec.configure do |config|
  config.include GuestVerificationHelpers, type: :request
end
