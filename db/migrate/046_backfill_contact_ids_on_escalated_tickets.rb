# frozen_string_literal: true

# Backfills contact_id on existing tickets that have a guest_email.
# Idempotent: the unique email index on contacts prevents duplicates,
# and tickets already carrying a contact_id are skipped.
class BackfillContactIdsOnEscalatedTickets < ActiveRecord::Migration[7.0]
  def up
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"
    tickets_table = "#{Escalated.configuration.table_prefix}tickets"

    seen = {} # normalized email => contact id

    connection.execute(<<~SQL.squish).each do |row|
      SELECT id, guest_email, guest_name
      FROM #{tickets_table}
      WHERE guest_email IS NOT NULL
        AND contact_id IS NULL
    SQL
      id = row['id']
      email = row['guest_email'].to_s.strip.downcase
      next if email.empty?

      unless seen.key?(email)
        existing = connection.select_one(
          "SELECT id FROM #{contacts_table} WHERE email = #{connection.quote(email)}",
        )
        seen[email] = if existing
                        existing['id']
                      else
                        now = connection.quote(Time.current)
                        name = connection.quote(row['guest_name'].presence)
                        connection.insert(<<~SQL.squish)
                          INSERT INTO #{contacts_table} (email, name, user_id, metadata, created_at, updated_at)
                          VALUES (#{connection.quote(email)}, #{name}, NULL, '{}', #{now}, #{now})
                        SQL
                      end
      end

      connection.execute(<<~SQL.squish)
        UPDATE #{tickets_table}
        SET contact_id = #{seen[email]}
        WHERE id = #{id}
      SQL
    end
  end

  def down
    tickets_table = "#{Escalated.configuration.table_prefix}tickets"
    connection.execute("UPDATE #{tickets_table} SET contact_id = NULL")
  end
end
