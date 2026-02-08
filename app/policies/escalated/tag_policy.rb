module Escalated
  class TagPolicy
    attr_reader :user, :tag

    def initialize(user, tag)
      @user = user
      @tag = tag
    end

    def index?
      agent? || admin?
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

    def agent?
      user.respond_to?(:escalated_agent?) && user.escalated_agent?
    end

    def admin?
      user.respond_to?(:escalated_admin?) && user.escalated_admin?
    end
  end
end
