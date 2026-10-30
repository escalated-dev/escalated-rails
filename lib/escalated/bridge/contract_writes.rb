# frozen_string_literal: true

module Escalated
  module Bridge
    # The fields each ctx write takes (domain-model/plugin-contract.md), and
    # how a plugin's data becomes attributes. Any key outside the contract is
    # an ArgumentError naming it, never an attribute.
    module ContractWrites
      # The fields each ctx write takes (plugin contract). title and body are
      # the SDK's names for subject and description. Any other key is an
      # error, never an attribute: a plugin never names an author, a
      # requester, an assignee or a reply's flags.
      TICKET_UPDATE_FIELDS = %w[subject title body description priority status department_id
                                ticket_type metadata].freeze
      # channel is accepted for the contract; tickets here have no channel column.
      TICKET_CREATE_FIELDS = (TICKET_UPDATE_FIELDS + %w[channel contact_id requester_email
                                                        requester_name]).freeze
      REPLY_CREATE_FIELDS = %w[ticket_id body is_internal].freeze
      CONTACT_CREATE_FIELDS = %w[name email].freeze
      TAG_CREATE_FIELDS = %w[name slug color].freeze

      private

      def tickets_create(params)
        method = 'ctx.tickets.create'
        data = contract_fields(params['data'], TICKET_CREATE_FIELDS, method)
        attributes = ticket_attributes(data, method)
        raise ArgumentError, "#{method} requires subject" if attributes[:subject].blank?

        attributes[:description] = attributes[:subject] if attributes[:description].blank?
        contact = ticket_contact(data, method)
        if contact
          attributes[:contact] = contact
          attributes[:guest_email] = contact.email
          attributes[:guest_name] = contact.name.presence || contact.email
        end

        # Through the ticket service, like a ticket opened over the API: the
        # creation activity, SLA, ticket.created, workflows and webhooks. The
        # service opens every ticket; a requested status is a status change.
        status = attributes.delete(:status)
        ticket = ticket_service.create(attributes.merge(requester: nil))
        if changes?(ticket.status, status)
          ticket = ticket_service.transition_status(ticket, status, actor: @acting_user)
        end
        ticket.reload.as_json
      end

      def tickets_update(params)
        id = params['id'] or raise ArgumentError, 'ctx.tickets.update requires id'
        data = contract_fields(params['data'], TICKET_UPDATE_FIELDS, 'ctx.tickets.update')

        ticket = Escalated::Ticket.find(id)
        attributes = ticket_attributes(data, 'ctx.tickets.update')
        update_ticket_details(ticket, attributes)
        if changes?(ticket.priority, attributes[:priority])
          ticket = ticket_service.change_priority(ticket, attributes[:priority], actor: @acting_user)
        end
        update_ticket_department(ticket, attributes) if attributes.key?(:department_id)
        if changes?(ticket.status, attributes[:status])
          ticket = ticket_service.transition_status(ticket, attributes[:status], actor: @acting_user)
        end
        ticket.reload.as_json
      end

      # Each change goes the way the API makes it, so it is logged and
      # announced (ticket.updated, ticket.priority_changed, ...).
      def update_ticket_details(ticket, attributes)
        details = attributes.slice(:subject, :description)
        direct = attributes.slice(:ticket_type, :metadata)
        return if details.empty? && direct.empty?

        ticket.update!(direct) if direct.any?
        ticket_service.update(ticket, details, actor: @acting_user)
      end

      def update_ticket_department(ticket, attributes)
        return if ticket.department_id == attributes[:department_id]

        if attributes[:department_id].nil?
          ticket.update!(department_id: nil)
          ticket_service.update(ticket, {}, actor: @acting_user)
        else
          ticket_service.change_department(ticket, Escalated::Department.find(attributes[:department_id]),
                                           actor: @acting_user)
        end
      end

      def changes?(current, requested)
        !requested.nil? && requested.to_s != current.to_s
      end

      def ticket_service
        Escalated::Services::TicketService
      end

      def replies_create(params)
        method = 'ctx.replies.create'
        data = contract_fields(params['data'], REPLY_CREATE_FIELDS, method)
        ticket = Escalated::Ticket.find_by(id: data['ticket_id']) unless data['ticket_id'].nil?
        raise ArgumentError, "#{method} requires an existing ticket_id" unless ticket

        body = optional_text(data, 'body', method) or raise ArgumentError, "#{method} requires body"

        # The author is the acting user (the signed-in user of the request the
        # plugin is serving), or nobody: a plugin never names it. Through the
        # ticket service, like a reply over the API: activity log, first
        # response, reply.created / note.created, workflows and webhooks.
        ticket_service.reply(ticket, {
                               body: body,
                               is_internal: [true, 1, '1', 'true'].include?(data['is_internal']),
                               is_system: false,
                               author: @acting_user
                             }).as_json
      end

      # The plugin's data, refused when it holds a key outside the contract.
      def contract_fields(data, allowed, method)
        raise ArgumentError, "#{method} requires a data object" unless data.is_a?(Hash)

        unknown = data.keys.map(&:to_s) - allowed
        raise ArgumentError, "#{method} does not accept: #{unknown.join(', ')}" if unknown.any?

        data.transform_keys(&:to_s)
      end

      # A stripped, non-empty string field, or nil when absent or blank.
      def optional_text(data, key, method)
        value = data[key]
        return nil if value.nil?
        raise ArgumentError, "#{method}: #{key} must be a string" unless value.is_a?(String) || value.is_a?(Integer)

        value.to_s.strip.presence
      end

      # Ticket attributes from the contract fields a plugin sent.
      def ticket_attributes(data, method)
        attributes = {}
        subject = optional_text(data, 'subject', method) || optional_text(data, 'title', method)
        attributes[:subject] = subject if subject
        if data.key?('description') || data.key?('body')
          description = data.key?('description') ? data['description'] : data['body']
          unless description.nil? || description.is_a?(String)
            raise ArgumentError, "#{method}: description must be a string"
          end

          attributes[:description] = description.to_s
        end
        ticket_enum(attributes, data, 'priority', Escalated::Ticket.priorities, method)
        ticket_enum(attributes, data, 'status', Escalated::Ticket.statuses, method)
        if data.key?('department_id')
          attributes[:department_id] = data['department_id'].nil? ? nil : ticket_department(data, method)
        end
        if data.key?('ticket_type')
          type = optional_text(data, 'ticket_type', method)
          unless type.nil? || Escalated::Ticket::TICKET_TYPES.include?(type)
            raise ArgumentError, "#{method}: unknown ticket_type \"#{type}\""
          end

          attributes[:ticket_type] = type if type
        end
        if data.key?('metadata')
          unless data['metadata'].nil? || data['metadata'].is_a?(Hash)
            raise ArgumentError, "#{method}: metadata must be an object"
          end

          attributes[:metadata] = data['metadata']
        end
        attributes
      end

      def ticket_enum(attributes, data, key, values, method)
        value = optional_text(data, key, method)
        return if value.nil?
        raise ArgumentError, "#{method}: unknown #{key} \"#{value}\"" unless values.key?(value)

        attributes[key.to_sym] = value
      end

      def ticket_department(data, method)
        Escalated::Department.find_by(id: data['department_id'])&.id or
          raise ArgumentError, "#{method}: no such department"
      end

      # The requester is a contact, never a user id the plugin names.
      def ticket_contact(data, method)
        unless data['contact_id'].nil?
          return Escalated::Contact.find_by(id: data['contact_id']) ||
                 raise(ArgumentError, "#{method}: no such contact")
        end

        email = optional_text(data, 'requester_email', method)
        return nil if email.nil?
        unless email.match?(URI::MailTo::EMAIL_REGEXP)
          raise ArgumentError, "#{method}: requester_email is not an email address"
        end

        Escalated::Contact.find_or_create_by_email(email, optional_text(data, 'requester_name', method))
      end
    end
  end
end
