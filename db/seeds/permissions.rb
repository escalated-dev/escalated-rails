# frozen_string_literal: true

# Seed granular permissions and default system roles.
#
# This seed file is idempotent — safe to run multiple times.
# Permissions are upserted via find_or_create_by on slug.
# Role-permission assignments are replaced (for system roles only).
#
# Usage:
#   rails runner db/seeds/permissions.rb
#   — or call from db/seeds.rb:
#   load Rails.root.join("db/seeds/permissions.rb")

module Escalated
  module Seeds
    module Permissions
      PERMISSIONS = [
        # Tickets
        { slug: 'ticket.view',    name: 'View tickets',           group: 'Tickets',
          description: 'View tickets' },
        { slug: 'ticket.create',  name: 'Create tickets',         group: 'Tickets',
          description: 'Create tickets' },
        { slug: 'ticket.edit',    name: 'Edit ticket properties', group: 'Tickets',
          description: 'Edit ticket properties' },
        { slug: 'ticket.delete',  name: 'Delete tickets',         group: 'Tickets',
          description: 'Delete tickets' },
        { slug: 'ticket.assign',  name: 'Assign tickets',         group: 'Tickets',
          description: 'Assign tickets to agents' },
        { slug: 'ticket.merge',   name: 'Merge tickets',          group: 'Tickets',
          description: 'Merge tickets together' },
        { slug: 'ticket.close',   name: 'Close tickets',          group: 'Tickets',
          description: 'Close and reopen tickets' },
        { slug: 'ticket.export',  name: 'Export tickets',         group: 'Tickets',
          description: 'Export ticket data' },

        # Replies
        { slug: 'reply.create',          name: 'Reply to tickets',   group: 'Replies',
          description: 'Reply to tickets' },
        { slug: 'reply.create_internal', name: 'Add internal notes', group: 'Replies',
          description: 'Add internal notes' },
        { slug: 'reply.edit',            name: 'Edit replies',       group: 'Replies', description: 'Edit replies' },
        { slug: 'reply.delete',          name: 'Delete replies',     group: 'Replies', description: 'Delete replies' },

        # Knowledge Base
        { slug: 'kb.view',    name: 'View knowledge base', group: 'Knowledge Base',
          description: 'View knowledge base' },
        { slug: 'kb.create',  name: 'Create articles',     group: 'Knowledge Base', description: 'Create articles' },
        { slug: 'kb.edit',    name: 'Edit articles',       group: 'Knowledge Base', description: 'Edit articles' },
        { slug: 'kb.delete',  name: 'Delete articles',     group: 'Knowledge Base', description: 'Delete articles' },
        { slug: 'kb.publish', name: 'Publish articles',    group: 'Knowledge Base',
          description: 'Publish/unpublish articles' },

        # Departments
        { slug: 'department.view',   name: 'View departments',   group: 'Departments',
          description: 'View departments' },
        { slug: 'department.create', name: 'Create departments', group: 'Departments',
          description: 'Create departments' },
        { slug: 'department.edit',   name: 'Edit departments',   group: 'Departments',
          description: 'Edit departments' },
        { slug: 'department.delete', name: 'Delete departments', group: 'Departments',
          description: 'Delete departments' },

        # Reports
        { slug: 'report.view',   name: 'View reports',   group: 'Reports', description: 'View reports and analytics' },
        { slug: 'report.export', name: 'Export reports', group: 'Reports', description: 'Export report data' },

        # SLA
        { slug: 'sla.view',   name: 'View SLA policies',   group: 'SLA', description: 'View SLA policies' },
        { slug: 'sla.manage', name: 'Manage SLA policies', group: 'SLA',
          description: 'Create, edit, delete SLA policies' },

        # Automations
        { slug: 'automation.view',   name: 'View automations',   group: 'Automations',
          description: 'View automations' },
        { slug: 'automation.manage', name: 'Manage automations', group: 'Automations',
          description: 'Create, edit, delete automations' },

        # Escalation Rules
        { slug: 'escalation.view',   name: 'View escalation rules',   group: 'Escalation Rules',
          description: 'View escalation rules' },
        { slug: 'escalation.manage', name: 'Manage escalation rules', group: 'Escalation Rules',
          description: 'Create, edit, delete escalation rules' },

        # Macros
        { slug: 'macro.view',   name: 'View macros',   group: 'Macros', description: 'View macros' },
        { slug: 'macro.create', name: 'Create macros', group: 'Macros', description: 'Create personal macros' },
        { slug: 'macro.manage', name: 'Manage macros', group: 'Macros',
          description: 'Create, edit, delete shared macros' },

        # Tags
        { slug: 'tag.view',   name: 'View tags',   group: 'Tags', description: 'View tags' },
        { slug: 'tag.manage', name: 'Manage tags', group: 'Tags', description: 'Create, edit, delete tags' },

        # Custom Fields
        { slug: 'custom_field.view',   name: 'View custom fields',   group: 'Custom Fields',
          description: 'View custom fields' },
        { slug: 'custom_field.manage', name: 'Manage custom fields', group: 'Custom Fields',
          description: 'Create, edit, delete custom fields' },

        # Roles
        { slug: 'role.view',   name: 'View roles',   group: 'Roles', description: 'View roles' },
        { slug: 'role.manage', name: 'Manage roles', group: 'Roles',
          description: 'Create, edit, delete roles and assign permissions' },

        # Users
        { slug: 'user.view',   name: 'View users',   group: 'Users', description: 'View user profiles' },
        { slug: 'user.manage', name: 'Manage users', group: 'Users',
          description: 'Manage user accounts and agent profiles' },

        # Settings
        { slug: 'settings.view',   name: 'View settings',   group: 'Settings', description: 'View settings' },
        { slug: 'settings.manage', name: 'Manage settings', group: 'Settings', description: 'Manage system settings' },

        # Webhooks
        { slug: 'webhook.view',   name: 'View webhooks',   group: 'Webhooks', description: 'View webhooks' },
        { slug: 'webhook.manage', name: 'Manage webhooks', group: 'Webhooks',
          description: 'Create, edit, delete webhooks' },

        # API Tokens
        { slug: 'api_token.view',   name: 'View API tokens',   group: 'API Tokens', description: 'View API tokens' },
        { slug: 'api_token.manage', name: 'Manage API tokens', group: 'API Tokens',
          description: 'Create, revoke API tokens' },

        # Audit Log
        { slug: 'audit.view', name: 'View audit log', group: 'Audit Log', description: 'View audit log' },

        # Plugins
        { slug: 'plugin.view',   name: 'View plugins',   group: 'Plugins', description: 'View plugins' },
        { slug: 'plugin.manage', name: 'Manage plugins', group: 'Plugins',
          description: 'Install, configure, remove plugins' },

        # Custom Objects
        { slug: 'custom_object.view',   name: 'View custom objects',       group: 'Custom Objects',
          description: 'View custom objects' },
        { slug: 'custom_object.manage', name: 'Manage custom objects',     group: 'Custom Objects',
          description: 'Create, edit, delete custom object schemas' },
        { slug: 'custom_object.data',   name: 'Manage custom object data', group: 'Custom Objects',
          description: 'Manage custom object records' }
      ].freeze

      ROLES = [
        {
          slug: 'admin',
          name: 'Admin',
          description: 'Full access to all features and settings.',
          permissions: ['*']
        },
        {
          slug: 'agent',
          name: 'Agent',
          description: 'Standard agent with ticket handling and limited administrative access.',
          permissions: %w[
            ticket.*
            reply.*
            kb.view
            report.view
            macro.view
            macro.create
            tag.view
            custom_field.view
            audit.view
          ]
        },
        {
          slug: 'light_agent',
          name: 'Light Agent',
          description: 'Limited agent with read-only ticket access and internal note capability.',
          permissions: %w[
            ticket.view
            reply.create
            reply.create_internal
            kb.view
            macro.view
            tag.view
          ]
        }
      ].freeze

      class << self
        def seed!
          seed_permissions!
          seed_roles!
        end

        private

        def seed_permissions!
          PERMISSIONS.each do |attrs|
            permission = Escalated::Permission.find_or_initialize_by(slug: attrs[:slug])
            permission.assign_attributes(
              name: attrs[:name],
              group: attrs[:group],
              description: attrs[:description]
            )
            permission.save!
          end

          Rails.logger.debug { "Seeded #{PERMISSIONS.size} permissions." }
        end

        def seed_roles!
          all_permissions = Escalated::Permission.all.index_by(&:slug)

          ROLES.each do |definition|
            role = Escalated::Role.find_or_initialize_by(slug: definition[:slug])
            role.assign_attributes(
              name: definition[:name],
              description: definition[:description],
              is_system: true
            )
            role.save!

            resolved = resolve_permissions(definition[:permissions], all_permissions)
            role.permissions = resolved

            Rails.logger.debug { "Role \"#{role.name}\" synced with #{resolved.size} permissions." }
          end
        end

        # Resolve a mix of exact slugs and wildcard patterns (e.g. "ticket.*")
        # to Permission records. A single "*" grants all permissions.
        def resolve_permissions(patterns, slug_index)
          permissions = []

          patterns.each do |pattern|
            if pattern == '*'
              return slug_index.values
            elsif pattern.end_with?('.*')
              prefix = pattern.chomp('*') # e.g. "ticket."
              slug_index.each do |slug, perm|
                permissions << perm if slug.start_with?(prefix)
              end
            elsif slug_index.key?(pattern)
              permissions << slug_index[pattern]
            end
          end

          permissions.uniq
        end
      end
    end
  end
end

Escalated::Seeds::Permissions.seed!
