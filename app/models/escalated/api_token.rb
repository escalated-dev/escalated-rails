module Escalated
  class ApiToken < ApplicationRecord
    self.table_name = Escalated.table_name("api_tokens")

    belongs_to :tokenable, polymorphic: true

    validates :name, presence: true, length: { maximum: 255 }
    validates :token, presence: true, uniqueness: true, length: { maximum: 64 }

    scope :active, -> {
      where(expires_at: nil).or(where("expires_at > ?", Time.current))
    }
    scope :expired, -> {
      where.not(expires_at: nil).where("expires_at <= ?", Time.current)
    }

    # Create a new API token for a user.
    # Returns { token: <ApiToken>, plain_text_token: <String> }
    def self.create_token(user, name, abilities = ["*"], expires_at = nil)
      plain_text = SecureRandom.hex(32)

      token = create!(
        tokenable_type: user.class.name,
        tokenable_id: user.id,
        name: name,
        token: Digest::SHA256.hexdigest(plain_text),
        abilities: abilities,
        expires_at: expires_at
      )

      { token: token, plain_text_token: plain_text }
    end

    # Look up a token by its plain-text value (hashes before query).
    def self.find_by_plain_text(plain_text)
      return nil if plain_text.blank?

      where(token: Digest::SHA256.hexdigest(plain_text)).first
    end

    # Check whether this token grants the given ability.
    # A token with ["*"] has all abilities.
    def has_ability?(ability)
      abilities_list = abilities || []
      abilities_list.include?("*") || abilities_list.include?(ability.to_s)
    end

    # Whether this token has passed its expiration date.
    def expired?
      return false if expires_at.nil?

      expires_at <= Time.current
    end
  end
end
