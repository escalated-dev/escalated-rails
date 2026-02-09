module Escalated
  module Drivers
    class LocalDriver
      ALLOWED_SORT_COLUMNS = %w[created_at updated_at status priority subject reference assigned_to department_id resolved_at closed_at].freeze

      def create_ticket(params)
        ticket = Escalated::Ticket.new(
          subject: params[:subject],
          description: params[:description],
          priority: params[:priority] || Escalated.configuration.default_priority,
          status: :open,
          requester: params[:requester],
          assigned_to: params[:assigned_to],
          department_id: params[:department_id],
          reference: Escalated::Ticket.generate_reference,
          metadata: params[:metadata] || {}
        )

        ActiveRecord::Base.transaction do
          ticket.save!

          if params[:tag_ids].present?
            ticket.tags = Escalated::Tag.where(id: params[:tag_ids])
          end

          attach_sla_policy(ticket)
          log_activity(ticket, params[:requester], "ticket_created", { subject: ticket.subject })
        end

        instrument("escalated.ticket.created", ticket: ticket)
        ticket
      end

      def update_ticket(ticket, params, actor:)
        ActiveRecord::Base.transaction do
          changes = {}

          if params[:subject].present? && params[:subject] != ticket.subject
            changes[:subject] = [ticket.subject, params[:subject]]
            ticket.subject = params[:subject]
          end

          if params[:description].present? && params[:description] != ticket.description
            changes[:description] = [ticket.description, params[:description]]
            ticket.description = params[:description]
          end

          if params[:metadata].present?
            ticket.metadata = ticket.metadata.merge(params[:metadata])
          end

          ticket.save!

          if changes.any?
            log_activity(ticket, actor, "ticket_updated", changes)
          end
        end

        instrument("escalated.ticket.updated", ticket: ticket)
        ticket
      end

      def transition_status(ticket, new_status, actor:, note: nil)
        old_status = ticket.status

        ActiveRecord::Base.transaction do
          ticket.update!(status: new_status)

          if new_status.to_s == "resolved"
            ticket.update!(resolved_at: Time.current)
          end

          if new_status.to_s == "closed"
            ticket.update!(closed_at: Time.current)
          end

          if new_status.to_s == "reopened"
            ticket.update!(resolved_at: nil, closed_at: nil)
          end

          log_activity(ticket, actor, "status_changed", {
            from: old_status,
            to: new_status,
            note: note
          })
        end

        instrument("escalated.ticket.status_changed", ticket: ticket, from: old_status, to: new_status)
        ticket
      end

      def assign_ticket(ticket, agent, actor:)
        old_assignee_id = ticket.assigned_to

        ActiveRecord::Base.transaction do
          ticket.update!(assigned_to: agent.id, status: :in_progress)

          log_activity(ticket, actor, "ticket_assigned", {
            from_agent_id: old_assignee_id,
            to_agent_id: agent.id
          })
        end

        instrument("escalated.ticket.assigned", ticket: ticket, agent: agent)
        ticket
      end

      def unassign_ticket(ticket, actor:)
        old_assignee_id = ticket.assigned_to

        ActiveRecord::Base.transaction do
          ticket.update!(assigned_to: nil, status: :open)

          log_activity(ticket, actor, "ticket_unassigned", {
            from_agent_id: old_assignee_id
          })
        end

        instrument("escalated.ticket.unassigned", ticket: ticket)
        ticket
      end

      def add_reply(ticket, params)
        reply = nil

        ActiveRecord::Base.transaction do
          reply = ticket.replies.create!(
            body: params[:body],
            author: params[:author],
            is_internal: params[:is_internal] || false,
            is_system: params[:is_system] || false
          )

          # Update first response time if this is the first agent reply
          if !params[:is_internal] && ticket.first_response_at.nil? && is_agent?(params[:author])
            ticket.update!(first_response_at: Time.current)
          end

          # Update status based on who replied
          if is_agent?(params[:author]) && !params[:is_internal]
            ticket.update!(status: :waiting_on_customer) if ticket.open? || ticket.in_progress?
          elsif !is_agent?(params[:author])
            ticket.update!(status: :waiting_on_agent) if ticket.waiting_on_customer?
          end

          log_activity(ticket, params[:author], params[:is_internal] ? "internal_note_added" : "reply_added", {
            reply_id: reply.id
          })
        end

        instrument("escalated.ticket.reply_added", ticket: ticket, reply: reply)
        reply
      end

      def get_ticket(id)
        Escalated::Ticket.find(id)
      end

      def list_tickets(filters = {})
        scope = Escalated::Ticket.all

        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.where(priority: filters[:priority]) if filters[:priority].present?
        scope = scope.where(assigned_to: filters[:assigned_to]) if filters[:assigned_to].present?
        scope = scope.where(department_id: filters[:department_id]) if filters[:department_id].present?
        scope = scope.where(requester: filters[:requester]) if filters[:requester].present?
        scope = scope.search(filters[:search]) if filters[:search].present?

        if filters[:sla_breached]
          scope = scope.breached_sla
        end

        order_col = filters[:order_by].to_s
        order_col = 'created_at' unless ALLOWED_SORT_COLUMNS.include?(order_col)
        order_dir = filters[:order_dir].to_s.downcase == 'asc' ? :asc : :desc
        scope = scope.order(order_col => order_dir)

        if filters[:page].present?
          scope = scope.page(filters[:page]).per(filters[:per_page] || 25)
        end

        scope
      end

      def add_tags(ticket, tag_ids, actor:)
        tags = Escalated::Tag.where(id: tag_ids)
        new_tags = tags - ticket.tags

        ActiveRecord::Base.transaction do
          ticket.tags << new_tags

          if new_tags.any?
            log_activity(ticket, actor, "tags_added", {
              tag_names: new_tags.map(&:name)
            })
          end
        end

        instrument("escalated.ticket.tags_added", ticket: ticket, tags: new_tags)
        ticket
      end

      def remove_tags(ticket, tag_ids, actor:)
        tags_to_remove = ticket.tags.where(id: tag_ids)

        ActiveRecord::Base.transaction do
          ticket.tags.delete(tags_to_remove)

          if tags_to_remove.any?
            log_activity(ticket, actor, "tags_removed", {
              tag_names: tags_to_remove.map(&:name)
            })
          end
        end

        instrument("escalated.ticket.tags_removed", ticket: ticket, tags: tags_to_remove)
        ticket
      end

      def change_department(ticket, department, actor:)
        old_department_id = ticket.department_id

        ActiveRecord::Base.transaction do
          ticket.update!(department_id: department.id)

          log_activity(ticket, actor, "department_changed", {
            from_department_id: old_department_id,
            to_department_id: department.id
          })
        end

        instrument("escalated.ticket.department_changed", ticket: ticket, department: department)
        ticket
      end

      def change_priority(ticket, new_priority, actor:)
        old_priority = ticket.priority

        ActiveRecord::Base.transaction do
          ticket.update!(priority: new_priority)

          log_activity(ticket, actor, "priority_changed", {
            from: old_priority,
            to: new_priority
          })
        end

        instrument("escalated.ticket.priority_changed", ticket: ticket, from: old_priority, to: new_priority)
        ticket
      end

      private

      def log_activity(ticket, actor, action, details = {})
        ticket.activities.create!(
          action: action,
          causer: actor,
          details: details
        )
      end

      def instrument(event, payload = {})
        ActiveSupport::Notifications.instrument(event, payload)
      end

      def attach_sla_policy(ticket)
        return unless Escalated.configuration.sla_enabled?

        policy = if ticket.department&.default_sla_policy_id.present?
                   Escalated::SlaPolicy.find_by(id: ticket.department.default_sla_policy_id)
                 else
                   Escalated::SlaPolicy.default_policy.first
                 end

        if policy
          ticket.update!(
            sla_policy_id: policy.id,
            sla_first_response_due_at: calculate_due_date(policy.first_response_hours_for(ticket.priority)),
            sla_resolution_due_at: calculate_due_date(policy.resolution_hours_for(ticket.priority))
          )
        end
      end

      def calculate_due_date(hours)
        return nil unless hours

        if Escalated.configuration.business_hours_only?
          calculate_business_hours_due_date(hours)
        else
          Time.current + hours.hours
        end
      end

      def calculate_business_hours_due_date(hours)
        bh = Escalated.configuration.business_hours
        start_hour = bh[:start] || 9
        end_hour = bh[:end] || 17
        working_days = bh[:working_days] || [1, 2, 3, 4, 5]
        tz = bh[:timezone] || "UTC"

        current_time = Time.current.in_time_zone(tz)
        remaining_hours = hours.to_f
        hours_per_day = end_hour - start_hour

        while remaining_hours > 0
          if working_days.include?(current_time.wday)
            day_start = current_time.change(hour: start_hour, min: 0, sec: 0)
            day_end = current_time.change(hour: end_hour, min: 0, sec: 0)

            if current_time < day_start
              current_time = day_start
            end

            if current_time < day_end
              available_hours = (day_end - current_time) / 3600.0

              if remaining_hours <= available_hours
                return current_time + remaining_hours.hours
              else
                remaining_hours -= available_hours
              end
            end
          end

          current_time = (current_time + 1.day).change(hour: start_hour, min: 0, sec: 0)
        end

        current_time
      end

      def is_agent?(user)
        return false unless user.present?

        # Check if user responds to agent-like methods
        user.respond_to?(:escalated_agent?) && user.escalated_agent?
      rescue StandardError
        false
      end
    end
  end
end
