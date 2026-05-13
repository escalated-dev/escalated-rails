# frozen_string_literal: true

# The Escalated engine registers its mount via `Escalated::Engine` initializers
# (`escalated.append_routes`). Do not mount again here or Rails will raise
# "Invalid route name, already in use: 'escalated'".
Rails.application.routes.draw do
  root to: proc { [200, {}, ['dummy host root']] }
end
