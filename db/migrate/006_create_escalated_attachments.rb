class CreateEscalatedAttachments < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("attachments") do |t|
      # Polymorphic - can attach to tickets or replies
      t.string :attachable_type, null: false
      t.bigint :attachable_id, null: false

      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false, default: 0

      t.timestamps
    end

    add_index Escalated.table_name("attachments"), [:attachable_type, :attachable_id]
  end
end
