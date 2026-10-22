# frozen_string_literal: true

# An import source for specs. It stands in for a plugin-provided adapter
# (Zendesk, Freshdesk, ...): core never talks to a third-party API itself, it
# only drives whatever the "import.adapters" filter hands it.
#
# The records are fixed: two contacts, one tag, three tickets served two to a
# page, and two replies. `on_extract` lets a spec act between batches, for
# example to pause the job or to observe the import context.
class FakeImportAdapter
  include Escalated::ImportAdapter

  TOKEN = 'secret-token'

  RECORDS = {
    'contacts' => [
      { 'source_id' => 'c1', 'email' => 'ada@customer.test', 'name' => 'Ada Customer' },
      { 'source_id' => 'c2', 'email' => 'bob@customer.test', 'name' => 'Bob Customer' }
    ],
    'tags' => [{ 'source_id' => 't1', 'name' => 'Billing' }],
    'tickets' => [
      { 'source_id' => 'k1', 'title' => 'Refund please', 'description' => 'Charged twice.', 'status' => 'open',
        'priority' => 'high', 'requester_source_id' => 'c1', 'tag_source_ids' => ['t1'],
        'created_at' => '2024-01-02T03:04:05Z' },
      { 'source_id' => 'k2', 'title' => 'Login broken', 'status' => 'solved', 'priority' => 'urgent',
        'requester_source_id' => 'c2' },
      { 'source_id' => 'k3', 'title' => 'Feature idea', 'status' => 'pending', 'requester_source_id' => 'c1' }
    ],
    'replies' => [
      { 'source_id' => 'r1', 'ticket_source_id' => 'k1', 'body' => 'Looking into it, @admin.importer',
        'author_source_id' => 'c1' },
      { 'source_id' => 'r2', 'ticket_source_id' => 'k2', 'body' => 'Internal note', 'is_internal_note' => true }
    ]
  }.freeze

  PAGE_SIZE = 2

  attr_accessor :on_extract
  attr_reader :extract_calls, :source_field_credentials

  def initialize
    @extract_calls = []
  end

  def name = 'fakedesk'
  def display_name = 'FakeDesk'

  def credential_fields
    [
      { 'name' => 'subdomain', 'label' => 'Subdomain', 'type' => 'text', 'help' => 'acme' },
      { 'name' => 'api_token', 'label' => 'API token', 'type' => 'password', 'help' => '' }
    ]
  end

  def test_connection(credentials)
    raise 'FakeDesk is unreachable' if credentials['subdomain'] == 'down'

    credentials['api_token'] == TOKEN
  end

  def entity_types = RECORDS.keys

  def default_field_mappings(entity_type)
    entity_type == 'tickets' ? { 'subject' => 'title', 'state' => 'status' } : {}
  end

  def available_source_fields(entity_type, credentials)
    @source_field_credentials = credentials
    return [] unless entity_type == 'tickets'

    [
      { 'name' => 'subject', 'label' => 'Subject', 'escalated_options' => %w[title description] },
      { 'name' => 'state', 'label' => 'State', 'escalated_options' => %w[status] }
    ]
  end

  def extract(entity_type, credentials, cursor)
    raise 'bad credentials' unless credentials['api_token'] == TOKEN

    @extract_calls << [entity_type, cursor]
    on_extract&.call(entity_type, cursor)

    records = RECORDS.fetch(entity_type)
    offset = cursor.to_i
    page = records[offset, PAGE_SIZE] || []
    next_offset = offset + PAGE_SIZE

    Escalated::ExtractResult.new(
      records: page,
      cursor: next_offset < records.size ? next_offset.to_s : nil,
      total_count: records.size
    )
  end
end
