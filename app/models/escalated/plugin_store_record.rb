module Escalated
  # Persistent key-value / document store for SDK plugins.
  #
  # Each row belongs to a plugin (identified by name string) and lives inside
  # a named collection.  An optional +key+ column allows O(1) look-ups for
  # named entries, while keyless rows support append-only log-style usage.
  #
  # The +data+ column is a JSON blob that can hold any serialisable structure
  # that the plugin wants to persist.
  class PluginStoreRecord < ApplicationRecord
    self.table_name = Escalated.table_name("plugin_store")

    # -------------------------------------------------------------------------
    # Validations
    # -------------------------------------------------------------------------

    validates :plugin,     presence: true
    validates :collection, presence: true
    validates :key,
              uniqueness: { scope: [:plugin, :collection], allow_nil: true },
              allow_nil: true

    # -------------------------------------------------------------------------
    # Scopes
    # -------------------------------------------------------------------------

    scope :for_plugin,     ->(plugin)     { where(plugin: plugin) }
    scope :in_collection,  ->(collection) { where(collection: collection) }
    scope :with_key,       ->(key)        { where(key: key) }

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    # Convenience finder that mirrors the PHP PluginStoreRecord pattern.
    #
    # @param plugin     [String]
    # @param collection [String]
    # @param key        [String]
    # @return [PluginStoreRecord, nil]
    def self.fetch(plugin, collection, key)
      for_plugin(plugin).in_collection(collection).with_key(key).first
    end

    # Upsert a keyed record for a given plugin/collection.
    #
    # @param plugin     [String]
    # @param collection [String]
    # @param key        [String]
    # @param value      [Object]  Any JSON-serialisable value
    # @return [PluginStoreRecord]
    def self.store(plugin, collection, key, value)
      find_or_initialize_by(plugin: plugin, collection: collection, key: key)
        .tap { |r| r.update!(data: value) }
    end
  end
end
