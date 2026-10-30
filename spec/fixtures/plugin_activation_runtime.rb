# frozen_string_literal: true

# A stand-in plugin runtime with two SDK plugins. Like the real runtime it
# loads every installed plugin whatever the host thinks of them, so it logs
# each message the host sends (to the file named by ARGV[0]) for the specs to
# see what the host chose to send. On the `test.ctx` action it calls
# `ctx.config.set` back for each plugin, the way a plugin's handler would, and
# logs the answer.
require 'json'

# rubocop:disable RSpec/Output -- a runtime speaks JSON-RPC on stdout

$stdout.sync = true
log = ARGV[0]

def plugin(name, label)
  {
    'name' => name, 'version' => '1.2.3', 'description' => "#{label} plugin",
    'pages' => [{ 'route' => 'settings', 'component' => 'Settings', 'menu' => { 'label' => label } }],
    'widgets' => [{ 'component' => 'Inbox', 'label' => "#{label} inbox", 'hasBadge' => true }],
    'components' => [{ 'page' => 'ticket.show', 'slot' => 'sidebar', 'component' => 'Panel' }],
    'cronSchedules' => ['* * * * *']
  }
end

manifests = [plugin('@acme/plugin-crm', 'CRM'), plugin('@acme/plugin-quiet', 'Quiet')]
record = ->(entry) { File.open(log, 'a') { |f| f.puts(JSON.generate(entry)) } }
next_id = 1000

host_call = lambda do |method, params|
  id = next_id
  next_id += 1
  puts JSON.generate('jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params)
  while (line = $stdin.gets)
    message = JSON.parse(line)
    next unless message['id'] == id && !message.key?('method')

    return message.key?('error') ? { 'error' => message['error']['message'] } : { 'result' => message['result'] }
  end
  { 'error' => 'closed' }
end

while (line = $stdin.gets)
  message = JSON.parse(line)
  method = message['method']
  params = message['params'] || {}
  record.call('method' => method, 'params' => params) unless %w[handshake manifest].include?(method)

  if method == 'action' && params['hook'] == 'test.ctx'
    manifests.each do |m|
      answer = host_call.call('ctx.config.set', { 'plugin' => m['name'], 'data' => { 'seen' => true } })
      record.call('method' => 'ctx-answer', 'plugin' => m['name'], 'answer' => answer)
    end
  end

  result = case method
           when 'handshake' then { 'compatible' => true, 'protocol_version' => '1.0' }
           when 'manifest' then manifests
           when 'filter' then params['value']
           when 'endpoint', 'webhook' then { 'plugin' => params['plugin'], 'path' => params['path'] }
           when 'badge' then 5
           else { 'ok' => true }
           end
  puts JSON.generate('jsonrpc' => '2.0', 'id' => message['id'], 'result' => result)
end
# rubocop:enable RSpec/Output
