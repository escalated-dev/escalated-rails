# frozen_string_literal: true

# Host-app stand-in for ticket subject specs (string primary key).
class FakeProject < ApplicationRecord
  include Escalated::PresentsAsTicketSubject

  self.table_name = 'fake_projects'
  self.primary_key = 'id'

  def ticket_subject_subtitle
    "Project · #{account}"
  end

  def ticket_subject_url
    "https://app.test/projects/#{id}"
  end

  def ticket_subject_color
    '#2563eb'
  end

  def ticket_subject_icon
    'folder'
  end
end
