# frozen_string_literal: true

# The dummy app does not ship a host `layouts/application`, but InertiaRails
# defaults to `layout: true`, which makes Rails resolve an ActionView layout for
# `Escalated::*` controllers and raises ArgumentError. Render the gem's
# `inertia` template without a wrapping layout (integration apps set
# `InertiaRails.config.layout`, as in docker/host-app).
InertiaRails.configure do |config|
  config.layout = false
  config.always_include_errors_hash = false
end
