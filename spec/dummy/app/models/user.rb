# frozen_string_literal: true

class User < ApplicationRecord
  scope :escalated_agents, lambda {
    where(is_agent: true).or(where(role: %w[agent admin]))
  }

  has_many :escalated_tickets,
           class_name: 'Escalated::Ticket',
           as: :requester,
           dependent: :nullify

  has_many :escalated_assigned_tickets,
           class_name: 'Escalated::Ticket',
           foreign_key: :assigned_to,
           dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  def escalated_agent?
    return true if respond_to?(:is_agent) && is_agent
    return true if respond_to?(:is_admin) && is_admin

    %w[agent admin].include?(role)
  end

  def escalated_admin?
    return true if respond_to?(:is_admin) && is_admin

    role == 'admin'
  end

  def admin?
    escalated_admin?
  end

  def to_s
    name
  end
end
