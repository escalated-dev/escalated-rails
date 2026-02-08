module Escalated
  class EscalationRulePolicy
    attr_reader :user, :escalation_rule

    def initialize(user, escalation_rule)
      @user = user
      @escalation_rule = escalation_rule
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
