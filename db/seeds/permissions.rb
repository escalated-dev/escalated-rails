# frozen_string_literal: true

# Seed granular permissions and default system roles (idempotent).
#
# Usage:
#   rails runner db/seeds/permissions.rb   -- or --   rake escalated:permissions:seed
# The definitions live in lib/escalated/seeds/permissions.rb.

require 'escalated/seeds/permissions'

Escalated::Seeds::Permissions.seed!
