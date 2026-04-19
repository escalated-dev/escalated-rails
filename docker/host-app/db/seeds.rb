require 'securerandom'

User.delete_all

users = [
  { name: 'Alice Admin', email: 'alice@demo.test', is_admin: true,  is_agent: true },
  { name: 'Bob Agent',   email: 'bob@demo.test',   is_admin: false, is_agent: true },
  { name: 'Carol Agent', email: 'carol@demo.test', is_admin: false, is_agent: true },
  { name: 'Frank Customer', email: 'frank@acme.example', is_admin: false, is_agent: false },
  { name: 'Grace Customer', email: 'grace@acme.example', is_admin: false, is_agent: false },
  { name: 'Henry Customer', email: 'henry@globex.example', is_admin: false, is_agent: false }
].map { |attrs| User.create!(attrs) }

puts "[demo] seeded #{users.size} users"

if defined?(Escalated::Department)
  begin
    %w[Support Billing].each_with_index do |name, i|
      Escalated::Department.find_or_create_by!(slug: name.downcase) do |d|
        d.name = name
        d.description = "Demo #{name} department"
        d.is_active = true
      end
    end
    puts '[demo] seeded departments'
  rescue StandardError => e
    puts "[demo] departments skipped: #{e.message}"
  end
end

if defined?(Escalated::Tag)
  %w[bug refund billing].each do |slug|
    Escalated::Tag.find_or_create_by!(slug: slug) do |t|
      t.name = slug.capitalize
      t.color = '#7c3aed'
    end
  end
  puts '[demo] seeded tags'
end

puts '[demo] seed complete'
