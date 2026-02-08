module Escalated
  class SlaPolicyPolicy
    attr_reader :user, :sla_policy

    def initialize(user, sla_policy)
      @user = user
      @sla_policy = sla_policy
    end

    def index?
      admin?
    end

    def show?
      admin?
    end

    def create?
      admin?
    end

    def update?
      admin?
    end

    def destroy?
      admin?
    end

    private

    def admin?
      user.respond_to?(:escalated_admin?) && user.escalated_admin?
    end
  end
end
