module Escalated
  module Admin
    class TicketsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_ticket, only: [:show, :reply, :note, :assign, :status, :priority, :tags, :department]

      def index
        scope = Escalated::Ticket.all.recent

        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(priority: params[:priority]) if params[:priority].present?
        scope = scope.assigned_to(params[:assigned_to]) if params[:assigned_to].present?
        scope = scope.where(department_id: params[:department_id]) if params[:department_id].present?
        scope = scope.unassigned if params[:unassigned] == "true"
        scope = scope.breached_sla if params[:sla_breached] == "true"
        scope = scope.search(params[:search]) if params[:search].present?

        result = paginate(scope)

        render inertia: "Escalated/Admin/Tickets/Index", props: {
          tickets: result[:data].includes(:requester, :department, :assignee, :tags).map { |t| ticket_list_json(t) },
          meta: result[:meta],
          filters: {
            status: params[:status],
            priority: params[:priority],
            assigned_to: params[:assigned_to],
            department_id: params[:department_id],
            unassigned: params[:unassigned],
            sla_breached: params[:sla_breached],
            search: params[:search]
          },
          departments: Escalated::Department.active.ordered.map { |d| { id: d.id, name: d.name } },
          agents: agent_list,
          tags: Escalated::Tag.ordered.map { |t| { id: t.id, name: t.name, color: t.color } },
          statuses: Escalated::Ticket.statuses.keys,
          priorities: Escalated::Ticket.priorities.keys
        }
      end

      def show
        replies = @ticket.replies.chronological.includes(:author, :attachments)
        activities = @ticket.activities.reverse_chronological.limit(50)

        render inertia: "Escalated/Admin/Tickets/Show", props: {
          ticket: ticket_detail_json(@ticket),
          replies: replies.map { |r| reply_json(r) },
          activities: activities.map { |a| activity_json(a) },
          departments: Escalated::Department.active.ordered.map { |d| { id: d.id, name: d.name } },
          agents: agent_list,
          tags: Escalated::Tag.ordered.map { |t| { id: t.id, name: t.name, color: t.color } },
          canned_responses: Escalated::CannedResponse.for_user(escalated_current_user.id).ordered.map { |c|
            { id: c.id, title: c.title, body: c.body, shortcode: c.shortcode }
          },
          statuses: Escalated::Ticket.statuses.keys,
          priorities: Escalated::Ticket.priorities.keys
        }
      end

      def reply
        reply = Services::TicketService.reply(@ticket, {
          body: params[:body],
          author: escalated_current_user,
          is_internal: false
        })

        if params[:attachments].present?
          Services::AttachmentService.attach(reply, params[:attachments])
        end

        redirect_to admin_ticket_path(@ticket), notice: "Reply sent."
      end

      def note
        Services::TicketService.reply(@ticket, {
          body: params[:body],
          author: escalated_current_user,
          is_internal: true
        })

        redirect_to admin_ticket_path(@ticket), notice: "Internal note added."
      end

      def assign
        if params[:agent_id].present?
          agent = Escalated.configuration.user_model.find(params[:agent_id])
          Services::AssignmentService.assign(@ticket, agent, actor: escalated_current_user)
          redirect_to admin_ticket_path(@ticket), notice: "Ticket assigned to #{agent.respond_to?(:name) ? agent.name : agent.email}."
        else
          Services::AssignmentService.unassign(@ticket, actor: escalated_current_user)
          redirect_to admin_ticket_path(@ticket), notice: "Ticket unassigned."
        end
      end

      def status
        Services::TicketService.transition_status(
          @ticket,
          params[:status],
          actor: escalated_current_user,
          note: params[:note]
        )

        redirect_to admin_ticket_path(@ticket), notice: "Status updated to #{params[:status].humanize}."
      end

      def priority
        Services::TicketService.change_priority(@ticket, params[:priority], actor: escalated_current_user)
        redirect_to admin_ticket_path(@ticket), notice: "Priority updated to #{params[:priority]}."
      end

      def tags
        if params[:add_tag_ids].present?
          Services::TicketService.add_tags(@ticket, params[:add_tag_ids], actor: escalated_current_user)
        end

        if params[:remove_tag_ids].present?
          Services::TicketService.remove_tags(@ticket, params[:remove_tag_ids], actor: escalated_current_user)
        end

        redirect_to admin_ticket_path(@ticket), notice: "Tags updated."
      end

      def department
        dept = Escalated::Department.find(params[:department_id])
        Services::TicketService.change_department(@ticket, dept, actor: escalated_current_user)
        redirect_to admin_ticket_path(@ticket), notice: "Department changed to #{dept.name}."
      end

      private

      def set_ticket
        @ticket = Escalated::Ticket.find(params[:id])
      end

      def admin_ticket_path(ticket)
        escalated.admin_ticket_path(ticket)
      end

      def agent_list
        if Escalated.configuration.user_model.respond_to?(:escalated_agents)
          Escalated.configuration.user_model.escalated_agents.map { |a|
            { id: a.id, name: a.respond_to?(:name) ? a.name : a.email, email: a.email }
          }
        else
          []
        end
      end

      def ticket_list_json(ticket)
        {
          id: ticket.id,
          reference: ticket.reference,
          subject: ticket.subject,
          status: ticket.status,
          priority: ticket.priority,
          requester: {
            name: ticket.requester.respond_to?(:name) ? ticket.requester.name : ticket.requester&.email
          },
          assignee: ticket.assignee ? {
            id: ticket.assignee.id,
            name: ticket.assignee.respond_to?(:name) ? ticket.assignee.name : ticket.assignee.email
          } : nil,
          department: ticket.department ? { id: ticket.department.id, name: ticket.department.name } : nil,
          tags: ticket.tags.map { |t| { id: t.id, name: t.name, color: t.color } },
          sla_breached: ticket.sla_breached,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601
        }
      end

      def ticket_detail_json(ticket)
        ticket_list_json(ticket).merge(
          description: ticket.description,
          metadata: ticket.metadata,
          sla_policy: ticket.sla_policy ? { id: ticket.sla_policy.id, name: ticket.sla_policy.name } : nil,
          sla_first_response_due_at: ticket.sla_first_response_due_at&.iso8601,
          sla_resolution_due_at: ticket.sla_resolution_due_at&.iso8601,
          first_response_at: ticket.first_response_at&.iso8601,
          resolved_at: ticket.resolved_at&.iso8601,
          closed_at: ticket.closed_at&.iso8601,
          reply_count: ticket.replies.count,
          attachment_count: ticket.attachments.count
        )
      end

      def reply_json(reply)
        {
          id: reply.id,
          body: reply.body,
          is_internal: reply.is_internal,
          is_system: reply.is_system,
          author: reply.author ? {
            id: reply.author.id,
            name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email,
            is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false
          } : { name: "System", is_agent: true },
          attachments: reply.attachments.map { |a|
            { id: a.id, filename: a.filename, size: a.human_size, content_type: a.content_type }
          },
          created_at: reply.created_at&.iso8601
        }
      end

      def activity_json(activity)
        {
          id: activity.id,
          action: activity.action,
          description: activity.description,
          causer: activity.causer ? {
            name: activity.causer.respond_to?(:name) ? activity.causer.name : activity.causer.email
          } : nil,
          details: activity.details,
          created_at: activity.created_at&.iso8601
        }
      end
    end
  end
end
