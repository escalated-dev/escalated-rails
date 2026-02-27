module Escalated
  module Services
    class SsoService
      CONFIG_KEYS = %w[sso_provider sso_entity_id sso_url sso_certificate sso_attr_email sso_attr_name sso_attr_role sso_jwt_secret sso_jwt_algorithm].freeze
      DEFAULTS = {
        "sso_provider" => "none",
        "sso_entity_id" => "",
        "sso_url" => "",
        "sso_certificate" => "",
        "sso_attr_email" => "email",
        "sso_attr_name" => "name",
        "sso_attr_role" => "role",
        "sso_jwt_secret" => "",
        "sso_jwt_algorithm" => "HS256"
      }.freeze

      def get_config
        CONFIG_KEYS.each_with_object({}) do |key, hash|
          setting = Escalated::EscalatedSetting.find_by(key: key)
          hash[key] = setting&.value || DEFAULTS[key]
        end
      end

      def save_config(data)
        CONFIG_KEYS.each do |key|
          next unless data.key?(key)

          Escalated::EscalatedSetting.find_or_initialize_by(key: key).update!(value: data[key])
        end
      end

      def enabled?
        provider != "none"
      end

      def provider
        Escalated::EscalatedSetting.find_by(key: "sso_provider")&.value || "none"
      end
    end
  end
end
