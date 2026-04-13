# frozen_string_literal: true

module Escalated
  module Api
    module V1
      class TicketsController < BaseController
        before_action :set_ticket,
                      only: %i[show reply status priority assign follow apply_macro tags destroy]

        # GET /api/v1/tickets
        def index
          scope = Escalated::Ticket.all.recent

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(priority: params[:priority]) if params[:priority].present?
          scope = scope.assigned_to(params[:assigned_to]) if params[:assigned_to].present?
          scope = scope.where(department_id: params[:department_id]) if params[:department_id].present?
          scope = scope.unassigned if params[:unassigned] == 'true'
          scope = scope.breached_sla if params[:sla_breached] == 'true'
          scope = scope.search(params[:search]) if params[:search].present?

          if params[:tag_ids].present?
            tag_ids = Array(params[:tag_ids]).map(&:to_i)
            scope = scope.joins(:tags).where(Escalated.table_name('tags') => { id: tag_ids }).distinct
          end

          if params[:following] == 'true'
            followers_table = Escalated.table_name('ticket_followers')
            tickets_table = Escalated.table_name('tickets')
            join_sql = "INNER JOIN #{followers_table} " \
                       "ON #{followers_table}.ticket_id = #{tickets_table}.id"
            followed_ticket_ids = Escalated::Ticket
                                  .joins(join_sql)
                                  .where("#{followers_table}.user_id = ?", current_user.id)
                                  .pluck(:id)
            scope = scope.where(id: followed_ticket_ids)
          end

          result = paginate(scope)

          render json: {
            data: result[:data].includes(:requester, :assignee, :department, :tags).map { |t| ticket_list_json(t) },
            meta: result[:meta]
          }
        end

        # GET /api/v1/tickets/:reference
        def show
          render json: {
            data: ticket_detail_json(@ticket)
          }
        end

        # POST /api/v1/tickets
        def create
          params.require(:subject)
          params.require(:description)

          ticket_params = {
            subject: params[:subject],
            description: params[:description],
            requester: current_user,
            priority: params[:priority] || Escalated.configuration.default_priority.to_s,
            department_id: params[:department_id]
          }

          ticket = Services::TicketService.create(ticket_params)

          if params[:tags].present?
            tag_ids = Array(params[:tags]).map(&:to_i)
            Services::TicketService.add_tags(ticket, tag_ids, actor: current_user)
          end

          ticket.reload

          render json: {
            data: ticket_detail_json(ticket),
            message: 'Ticket created.'
          }, status: :created
        end

        # POST /api/v1/tickets/:reference/reply
        def reply
          params.require(:body)

          is_internal = [true, 'true'].include?(params[:is_internal_note])

          reply = Services::TicketService.reply(@ticket, {
                                                  body: params[:body],
                                                  author: current_user,
                                                  is_internal: is_internal
                                                })

          render json: {
            data: {
              id: reply.id,
              body: reply.body,
              is_internal_note: reply.is_internal,
              author: {
                id: current_user.id,
                name: current_user.respond_to?(:name) ? current_user.name : current_user.email
              },
              created_at: reply.created_at&.iso8601
            },
            message: is_internal ? 'Note added.' : 'Reply sent.'
          }, status: :created
        end

        # PATCH /api/v1/tickets/:reference/status
        def status
          params.require(:status)

          Services::TicketService.transition_status(
            @ticket,
            params[:status],
            actor: current_user,
            note: params[:note]
          )

          render json: { message: 'Status updated.', status: params[:status] }
        end

        # PATCH /api/v1/tickets/:reference/priority
        def priority
          params.require(:priority)

          Services::TicketService.change_priority(@ticket, params[:priority], actor: current_user)

          render json: { message: 'Priority updated.', priority: params[:priority] }
        end

        # POST /api/v1/tickets/:reference/assign
        def assign
          params.require(:agent_id)

          agent = Escalated.configuration.user_model.find(params[:agent_id])
          Services::AssignmentService.assign(@ticket, agent, actor: current_user)

          render json: { message: 'Ticket assigned.' }
        end

        # POST /api/v1/tickets/:reference/follow
        def follow
          user_id = current_user.id

          if @ticket.followed_by?(user_id)
            @ticket.unfollow(user_id)
            render json: { message: 'Unfollowed ticket.', following: false }
          else
            @ticket.follow(user_id)
            render json: { message: 'Following ticket.', following: true }
          end
        end

        # POST /api/v1/tickets/:reference/apply_macro
        def apply_macro
          params.require(:macro_id)

          macro = Escalated::Macro.for_agent(current_user.id).find(params[:macro_id])
          Services::MacroService.apply(macro, @ticket, actor: current_user)

          render json: { message: "Macro \"#{macro.name}\" applied." }
        end

        # POST /api/v1/tickets/:reference/tags
        def tags
          params.require(:tag_ids)

          new_tag_ids = Array(params[:tag_ids]).map(&:to_i)
          current_tag_ids = @ticket.tags.pluck(:id)

          to_add = new_tag_ids - current_tag_ids
          to_remove = current_tag_ids - new_tag_ids

          Services::TicketService.add_tags(@ticket, to_add, actor: current_user) if to_add.any?
          Services::TicketService.remove_tags(@ticket, to_remove, actor: current_user) if to_remove.any?

          render json: { message: 'Tags updated.' }
        end

        # DELETE /api/v1/tickets/:reference
        def destroy
          @ticket.destroy!

          render json: { message: 'Ticket deleted.' }
        end

        private

        def set_ticket
          @ticket = Escalated::Ticket.find_by!(reference: params[:reference])
        rescue ActiveRecord::RecordNotFound
          @ticket = Escalated::Ticket.find(params[:reference])
        end

        def ticket_list_json(ticket)
          {
            id: ticket.id,
            reference: ticket.reference,
            subject: ticket.subject,
            status: ticket.status,
            priority: ticket.priority,
            requester_name: ticket.requester_name,
            requester_email: ticket.requester_email,
            requester: {
              name: ticket.requester_name
            },
            assignee: if ticket.assignee
                        {
                          id: ticket.assignee.id,
                          name: ticket.assignee.respond_to?(:name) ? ticket.assignee.name : ticket.assignee.email
                        }
                      end,
            department: if ticket.department
                          {
                            id: ticket.department.id,
                            name: ticket.department.name
                          }
                        end,
            tags: ticket.tags.map { |t| { id: t.id, name: t.name, color: t.color } },
            sla_breached: ticket.sla_breached,
            last_reply_at: ticket.last_reply_at&.iso8601,
            last_reply_author: ticket.last_reply_author,
            is_live_chat: ticket.is_live_chat,
            is_snoozed: ticket.is_snoozed,
            created_at: ticket.created_at&.iso8601,
            updated_at: ticket.updated_at&.iso8601
          }
        end

        def ticket_detail_json(ticket)
          ticket.reload

          replies = ticket.replies.chronological.includes(:author, :attachments)
          activities = ticket.activities.reverse_chronological.limit(20)

          base = ticket_list_json(ticket).merge(
            description: ticket.description,
            metadata: ticket.metadata,
            sla_policy: if ticket.sla_policy
                          {
                            id: ticket.sla_policy.id,
                            name: ticket.sla_policy.name
                          }
                        end,
            sla_first_response_due_at: ticket.sla_first_response_due_at&.iso8601,
            sla_resolution_due_at: ticket.sla_resolution_due_at&.iso8601,
            first_response_at: ticket.first_response_at&.iso8601,
            resolved_at: ticket.resolved_at&.iso8601,
            closed_at: ticket.closed_at&.iso8601,
            reply_count: ticket.replies.count,
            attachment_count: ticket.attachments.count,
            satisfaction_rating: if ticket.satisfaction_rating
                                   {
                                     id: ticket.satisfaction_rating.id,
                                     rating: ticket.satisfaction_rating.rating,
                                     comment: ticket.satisfaction_rating.comment,
                                     created_at: ticket.satisfaction_rating.created_at&.iso8601
                                   }
                                 end,
            pinned_notes: ticket.pinned_notes.includes(:author).map { |n| reply_json(n) },
            replies: replies.map { |r| reply_json(r) },
            activities: activities.map { |a| activity_json(a) },
            requester_ticket_count: ticket.requester ? Escalated::Ticket.where(requester: ticket.requester).count : 0,
            related_tickets: related_tickets_json(ticket)
          )

          if ticket.chat?
            session = ticket.active_chat_session || ticket.chat_sessions.order(created_at: :desc).first
            base.merge!(
              chat_session_id: session&.id,
              chat_started_at: session&.started_at&.iso8601,
              chat_messages: ticket.replies.chronological.includes(:author).map { |r| chat_message_json(r) },
              chat_metadata: session&.metadata
            )
          end

          base
        end

        def reply_json(reply)
          {
            id: reply.id,
            body: reply.body,
            is_internal: reply.is_internal,
            is_internal_note: reply.is_internal,
            is_system: reply.is_system,
            is_pinned: reply.respond_to?(:is_pinned) ? reply.is_pinned : false,
            author: if reply.author
                      {
                        id: reply.author.id,
                        name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email,
                        is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false
                      }
                    else
                      { name: 'System', is_agent: true }
                    end,
            attachments: reply.attachments.map do |a|
              { id: a.id, filename: a.filename, size: a.human_size, content_type: a.content_type }
            end,
            created_at: reply.created_at&.iso8601
          }
        end

        def activity_json(activity)
          {
            id: activity.id,
            action: activity.action,
            description: activity.description,
            causer: if activity.causer
                      {
                        name: activity.causer.respond_to?(:name) ? activity.causer.name : activity.causer.email
                      }
                    end,
            details: activity.details,
            created_at: activity.created_at&.iso8601,
            created_at_human: "#{ActionController::Base.helpers.time_ago_in_words(activity.created_at)} ago"
          }
        end

        def chat_message_json(reply)
          {
            id: reply.id,
            body: reply.body,
            is_internal_note: reply.is_internal,
            is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false,
            author: if reply.author
                      { id: reply.author.id,
                        name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email }
                    else
                      { name: 'System' }
                    end,
            created_at: reply.created_at&.iso8601
          }
        end

        def related_tickets_json(ticket)
          links = ticket.links_as_parent.includes(:child_ticket) +
                  ticket.links_as_child.includes(:parent_ticket)
          links.map do |link|
            related = link.parent_ticket_id == ticket.id ? link.child_ticket : link.parent_ticket
            { reference: related.reference, subject: related.subject, status: related.status }
          end
        end
      end
    end
  end
end
