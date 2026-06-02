# frozen_string_literal: true

# Ticket subjects — host-app entities a ticket is *about* (Project, Customer, …),
# distinct from the requester and the subject line. subject_id is a string so
# integer, UUID, and other host primary keys all work.
class CreateEscalatedTicketSubjects < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('ticket_subjects') do |t|
      t.references :ticket,
                   null: false,
                   foreign_key: { to_table: Escalated.table_name('tickets'), on_delete: :cascade }
      t.string :subject_type, null: false
      t.string :subject_id, null: false
      t.string :role
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index Escalated.table_name('ticket_subjects'),
              %i[ticket_id subject_type subject_id],
              unique: true,
              name: 'idx_escalated_ticket_subjects_unique'
    add_index Escalated.table_name('ticket_subjects'),
              %i[subject_type subject_id],
              name: 'idx_escalated_ticket_subjects_polymorphic'
  end
end
