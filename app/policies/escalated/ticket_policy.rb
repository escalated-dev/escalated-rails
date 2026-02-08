module Escalated
  class TicketPolicy
    attr_reader :user, :ticket

    def initialize(user, ticket)
      @user = user
      @ticket = ticket
    end

    def index?
      true
    end

    def show?
      owner? || agent? || admin?
    end

    def create?
      true
    end

    def update?
      agent? || admin?
    end

    def destroy?
      admin?
    end

    def reply?
      owner? || agent? || admin?
    end

    def note?
      agent? || admin?
    end

    def assign?
      agent? || admin?
    end

    def status?
      agent? || admin?
    end

    def priority?
      agent? || admin?
    end

    def tags?
      agent? || admin?
    end

    def department?
      agent? || admin?
    end

    def close?
      if Escalated.configuration.allow_customer_close
        owner? || agent? || admin?
      else
        agent? || admin?
      end
    end

    def reopen?
      owner? || agent? || admin?
    end

    class Scope
      attr_reader :user, :scope

      def initialize(user, scope)
        @user = user
        @scope = scope
      end

      def resolve
        if admin? || agent?
          scope.all
        else
          scope.where(requester: user)
        end
      end

      private

      def admin?
        user.respond_to?(:escalated_admin?) && user.escalated_admin?
      end

      def agent?
        user.respond_to?(:escalated_agent?) && user.escalated_agent?
      end
    end

    private

    def owner?
      ticket.requester == user
    end

    def agent?
      user.respond_to?(:escalated_agent?) && user.escalated_agent?
    end

    def admin?
      user.respond_to?(:escalated_admin?) && user.escalated_admin?
    end
  end
end
