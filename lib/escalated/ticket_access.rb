# frozen_string_literal: true

require 'active_support/current_attributes'
require 'active_support/concern'

module Escalated
  module TicketAccess
    class InvalidAccountFilter < ArgumentError; end

    class Context < ActiveSupport::CurrentAttributes
      attribute :actor
    end

    module Controller
      extend ActiveSupport::Concern

      included do
        prepend_around_action :with_ticket_access
        rescue_from TicketAccess::InvalidAccountFilter do |error|
          render json: { errors: { account: [error.message] } }, status: :unprocessable_content
        end
      end

      private

      def with_ticket_access(&)
        TicketAccess.with_actor(-> { respond_to?(:current_user, true) ? current_user : nil }, &)
      end
    end

    module_function

    def with_actor(actor, &)
      Context.set(actor: actor, &)
    end

    def current_actor
      Context.actor.respond_to?(:call) ? Context.actor.call : Context.actor
    end

    def accounts
      { enabled: false, scope_agents: false, resolver: nil }.merge(Escalated.configuration.accounts || {})
    end

    def validate!
      config = Escalated.configuration
      unless %w[all department].include?(config.visibility.to_s)
        raise ArgumentError, 'Ticket visibility must be all or department'
      end

      if accounts[:scope_agents] && (!accounts[:enabled] || !accounts[:resolver].respond_to?(:call))
        raise ArgumentError, 'Account visibility requires accounts.enabled and a resolver'
      end
      if config.mode.to_s == 'cloud' && (config.visibility.to_s != 'all' || accounts[:enabled] || config.sla[:targeted])
        raise ArgumentError, 'Local ticket access and targeted SLAs are unavailable in cloud-only mode'
      end
    end

    def restricted?(user = current_actor)
      validate!
      return false if user.nil? || (user.respond_to?(:escalated_admin?) && user.escalated_admin?)

      (Escalated.configuration.visibility.to_s == 'department' || accounts[:scope_agents]) &&
        user.respond_to?(:escalated_agent?) && user.escalated_agent?
    end

    def department_ids(user)
      # Query the package pivot without joining the host user table.
      connection = Escalated::Department.connection
      table = connection.quote_table_name(Escalated.table_name('department_agents'))
      connection.select_values("SELECT department_id FROM #{table} WHERE agent_id = #{connection.quote(user.id)}")
    end

    def resolve_account(model)
      return nil unless model && accounts[:enabled] && accounts[:resolver]

      account = accounts[:resolver].call(model)
      unless account.nil? || (account.is_a?(ActiveRecord::Base) && account.persisted?)
        raise ArgumentError, 'Account resolver must return a persisted model or nil'
      end

      account
    end

    def identity(model)
      model && { 'type' => model.class.polymorphic_name, 'id' => model.id.to_s }
    end

    def normalize_identity(value)
      return nil unless value.is_a?(Hash)

      value = value.stringify_keys
      return nil unless value['type'].is_a?(String) && value['type'].present?
      return nil unless (value['id'].is_a?(String) || value['id'].is_a?(Integer)) && value['id'].to_s.present?

      { 'type' => value['type'], 'id' => value['id'].to_s }
    end

    def apply(scope, user = current_actor)
      return scope.all unless restricted?(user)

      if Escalated.configuration.visibility.to_s == 'department'
        scope = scope.where(department_id: department_ids(user))
      end
      if accounts[:scope_agents]
        account = identity(resolve_account(user))
        return scope.none unless account

        scope = scope.where(account_type: account['type'], account_id: account['id'])
      end
      scope
    end

    def allowed?(user, ticket)
      return true unless restricted?(user)

      if Escalated.configuration.visibility.to_s == 'department'
        departments = department_ids(user).map(&:to_s)
        return false if ticket.department_id.nil? || departments.exclude?(ticket.department_id.to_s)
      end

      if accounts[:scope_agents]
        account = identity(resolve_account(user))
        return false unless account && ticket.account_type == account['type'] && ticket.account_id == account['id']
      end
      true
    end

    def children(scope, *columns)
      return scope.all unless restricted?

      columns = [:ticket_id] if columns.empty?
      columns.reduce(scope) { |query, column| query.where(column => Escalated::Ticket.select(:id)) }
    end

    def filter_accounts(scope, params)
      return scope unless accounts[:enabled] && (params.key?(:account_type) || params.key?(:account_id))

      account = normalize_identity(type: params[:account_type], id: params[:account_id])
      raise InvalidAccountFilter, 'Account filters require account_type and account_id' unless account

      scope.where(account_type: account['type'], account_id: account['id'])
    end

    def assignment_candidates(ticket = nil)
      users = Escalated.configuration.user_model
      return [] unless users.respond_to?(:escalated_agents)

      users.escalated_agents.filter_map do |user|
        next if ticket && !allowed?(user, ticket)

        { id: user.id, name: user.respond_to?(:name) ? user.name : user.email, email: user.email }
      end
    end

    def restrictions_enabled?
      Escalated.configuration.visibility.to_s == 'department' || accounts[:scope_agents]
    end

    def chat_allowed?(user, ticket, guest_session = nil)
      return true unless restrictions_enabled?
      return Escalated::TicketPolicy.new(user, ticket).show? if user
      return false if guest_session.blank?

      session = with_actor(nil) { Escalated::ChatSession.find_by(ticket_id: ticket.id) }
      session && session.customer_session_id.present? &&
        ActiveSupport::SecurityUtils.secure_compare(session.customer_session_id.to_s, guest_session.to_s)
    end

    def eligible_agent?(agent_id, ticket)
      return true unless restrictions_enabled?

      user = Escalated.configuration.user_model.find_by(id: agent_id)
      user && allowed?(user, ticket)
    end

    def serialize_account(ticket)
      accounts[:enabled] ? { account_type: ticket.account_type, account_id: ticket.account_id } : {}
    end
  end
end
