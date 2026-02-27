class User < ApplicationRecord
  has_many :escalated_tickets,
           class_name: "Escalated::Ticket",
           as: :requester,
           dependent: :nullify

  has_many :escalated_assigned_tickets,
           class_name: "Escalated::Ticket",
           foreign_key: :assigned_to,
           dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  def escalated_agent?
    role == "agent" || role == "admin"
  end

  def admin?
    role == "admin"
  end

  def to_s
    name
  end
end
