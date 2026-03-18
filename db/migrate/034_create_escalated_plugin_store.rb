class CreateEscalatedPluginStore < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("plugin_store") do |t|
      # Which plugin owns this record
      t.string :plugin,     null: false
      # Logical collection / namespace within the plugin
      t.string :collection, null: false
      # Optional named key for direct get/set access
      t.string :key

      # The actual payload — JSON column so complex structures are preserved
      t.json :data

      t.timestamps
    end

    add_index Escalated.table_name("plugin_store"), :plugin
    add_index Escalated.table_name("plugin_store"), [:plugin, :collection],
              name: "idx_escalated_plugin_store_plugin_collection"
    add_index Escalated.table_name("plugin_store"), [:plugin, :collection, :key],
              unique: true,
              where: "key IS NOT NULL",
              name: "idx_escalated_plugin_store_unique_key"
  end
end
