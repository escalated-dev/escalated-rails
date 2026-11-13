# Newsletters

## Newsletters (optional, disabled by default)

Admin-only broadcast feature for sending Markdown emails to contacts. Off by default — when disabled, no dispatcher tick runs.

```ruby
Escalated.configure do |config|
  config.enable_newsletters = true
  config.app_url = 'https://support.example.com'
  config.newsletter_default_from = 'hi@example.com'
  config.newsletter_default_theme = 'default'
  config.newsletter_brand_physical_address = 'Acme Inc. · 123 Main St · Springfield USA'

  # Register a Markdown renderer (CommonMarker recommended; Redcarpet works too):
  require 'commonmarker'
  config.newsletter_markdown_renderer = ->(md) { Commonmarker.to_html(md) }
end
```

Schedule the dispatcher every minute (cron, sidekiq-cron, whatever your stack uses):

```ruby
Escalated::Newsletter::Dispatcher.new.dispatch_batch
```

Custom themes go in `app/views/escalated/newsletter_themes/<slug>.html.erb`. Each theme receives `subject`, `body` (pre-rendered HTML), `unsubscribe_url`, `view_in_browser_url`, and `brand` (hash with `:name`, `:accent`, `:logo_url`, `:physical_address`).
