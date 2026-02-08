module Escalated
  class CannedResponsePolicy
    attr_reader :user, :canned_response

    def initialize(user, canned_response)
      @user = user
      @canned_response = canned_response
    end

    def index?
      agent? || admin?
    end

    def create?
      agent? || admin?
    end

    def update?
      owner? || admin?
    end

    def destroy?
      owner? || admin?
    end

    private

    def owner?
      canned_response.created_by == user.id
    end

    def agent?
      user.respond_to?(:escalated_agent?) && user.escalated_agent?
    end

    def admin?
      user.respond_to?(:escalated_admin?) && user.escalated_admin?
    end
  end
end
