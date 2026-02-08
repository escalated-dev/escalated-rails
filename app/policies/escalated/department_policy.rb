module Escalated
  class DepartmentPolicy
    attr_reader :user, :department

    def initialize(user, department)
      @user = user
      @department = department
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
