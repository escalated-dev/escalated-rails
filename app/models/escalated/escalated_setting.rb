module Escalated
  class EscalatedSetting < ApplicationRecord
    self.table_name = Escalated.table_name("settings")

    validates :key, presence: true, uniqueness: true

    # Class-level accessors

    def self.get(key, default = nil)
      record = find_by(key: key)
      record ? record.value : default
    end

    def self.set(key, value)
      record = find_or_initialize_by(key: key)
      record.value = value.nil? ? nil : value.to_s
      record.save!
      record
    end

    def self.get_bool(key, default: false)
      val = get(key)
      return default if val.nil?

      %w[1 true yes].include?(val.to_s.downcase)
    end

    def self.get_int(key, default: 0)
      val = get(key)
      return default if val.nil?

      Integer(val, exception: false) || default
    end

    def self.guest_tickets_enabled?
      get_bool("guest_tickets_enabled", default: true)
    end

    def self.all_as_hash
      all.each_with_object({}) { |s, hash| hash[s.key] = s.value }
    end
  end
end
