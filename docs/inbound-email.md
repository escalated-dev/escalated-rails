# Inbound email

## Inbound Email

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### Enable

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  config.inbound_email_enabled = true
  config.inbound_email_adapter = :mailgun
  config.inbound_email_address = "support@yourapp.com"

  # Signs the Reply-To on outbound mail (reply+{id}.{hmac8}@domain). Once set,
  # only that signed address links an inbound email to a ticket.
  config.email_domain = "support.yourapp.com"
  config.email_inbound_secret = ENV["ESCALATED_EMAIL_INBOUND_SECRET"]

  # Mailgun
  config.mailgun_signing_key = ENV["ESCALATED_MAILGUN_SIGNING_KEY"]

  # Postmark
  config.postmark_inbound_token = ENV["ESCALATED_POSTMARK_INBOUND_TOKEN"]

  # AWS SES
  config.ses_region = "us-east-1"
  config.ses_topic_arn = ENV["ESCALATED_SES_TOPIC_ARN"]

  # IMAP
  config.imap_host = ENV["ESCALATED_IMAP_HOST"]
  config.imap_port = 993
  config.imap_encryption = :ssl
  config.imap_username = ENV["ESCALATED_IMAP_USERNAME"]
  config.imap_password = ENV["ESCALATED_IMAP_PASSWORD"]
  config.imap_mailbox = "INBOX"
end
```

### Webhook URLs

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### IMAP Polling

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### Features

- Thread detection via the signed Reply-To address when `email_inbound_secret` is set; without a secret, via our `In-Reply-To` / `References` Message-IDs and the subject reference
- Replies accepted only from the ticket's requester (the guest email or the requester's email, case-insensitive) and posted as that requester. Staff identity is never taken from the `From` header, so agents reply in the app. Any other sender gets a new ticket of their own
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets when the requester replies by email
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback
