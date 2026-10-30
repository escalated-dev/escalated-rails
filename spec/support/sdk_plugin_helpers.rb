# frozen_string_literal: true

# Record SDK plugins (by name) as active, as Admin > Plugins does.
module SdkPluginHelpers
  def activate_sdk_plugins(*names)
    names.each do |name|
      Escalated::Plugin.find_or_initialize_by(slug: Escalated::Bridge::SdkPluginActivation.slug(name))
                       .update!(is_active: true, activated_at: Time.current)
    end
  end
end

RSpec.configure { |config| config.include SdkPluginHelpers }
