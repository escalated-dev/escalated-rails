module Escalated
  module Api
    module V1
      class ResourcesController < BaseController
        # GET /api/v1/agents
        def agents
          agent_data = if Escalated.configuration.user_model.respond_to?(:escalated_agents)
            Escalated.configuration.user_model.escalated_agents.map { |a|
              {
                id: a.id,
                name: a.respond_to?(:name) ? a.name : a.email,
                email: a.email
              }
            }
          else
            []
          end

          render json: { data: agent_data }
        end

        # GET /api/v1/departments
        def departments
          departments = Escalated::Department.active.ordered

          render json: {
            data: departments.map { |d|
              {
                id: d.id,
                name: d.name,
                slug: d.slug,
                description: d.description,
                email: d.email,
                is_active: d.is_active,
                open_ticket_count: d.open_ticket_count,
                agent_count: d.agent_count
              }
            }
          }
        end

        # GET /api/v1/tags
        def tags
          tags = Escalated::Tag.ordered

          render json: {
            data: tags.map { |t|
              {
                id: t.id,
                name: t.name,
                slug: t.slug,
                color: t.color,
                description: t.description,
                ticket_count: t.ticket_count
              }
            }
          }
        end

        # GET /api/v1/canned-responses
        def canned_responses
          responses = Escalated::CannedResponse.for_user(current_user.id).ordered

          render json: {
            data: responses.map { |r|
              {
                id: r.id,
                title: r.title,
                body: r.body,
                shortcode: r.shortcode,
                category: r.category,
                is_shared: r.is_shared
              }
            }
          }
        end

        # GET /api/v1/macros
        def macros
          macros = Escalated::Macro.for_agent(current_user.id).ordered

          render json: {
            data: macros.map { |m|
              {
                id: m.id,
                name: m.name,
                description: m.description,
                actions: m.actions,
                is_shared: m.is_shared
              }
            }
          }
        end

        # GET /api/v1/realtime/config
        def realtime_config
          # Return ActionCable/AnyCable config if available
          cable_config = Rails.application.config.action_cable rescue nil

          if cable_config && cable_config.respond_to?(:url) && cable_config.url.present?
            render json: {
              driver: "action_cable",
              url: cable_config.url
            }
          else
            render json: nil
          end
        end
      end
    end
  end
end
