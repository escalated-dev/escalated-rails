# frozen_string_literal: true

namespace :escalated do
  desc 'Close idle chat sessions that have exceeded auto_close_after_minutes'
  task close_idle_chats: :environment do
    count = 0

    Escalated::ChatRoutingRule.active.find_each do |rule|
      cutoff = rule.auto_close_after_minutes.minutes.ago

      scope = Escalated::ChatSession.active.where(updated_at: ...cutoff)

      if rule.department_id.present?
        ticket_ids = Escalated::Ticket.chat.where(department_id: rule.department_id).pluck(:id)
        scope = scope.where(ticket_id: ticket_ids)
      end

      scope.find_each do |session|
        Escalated::Services::ChatSessionService.end_chat(session)
        count += 1
      end
    end

    # Also close any active chats older than 60 minutes with no routing rule
    fallback_cutoff = 60.minutes.ago
    Escalated::ChatSession.active.where(updated_at: ...fallback_cutoff).find_each do |session|
      Escalated::Services::ChatSessionService.end_chat(session)
      count += 1
    end

    puts "Closed #{count} idle chat session(s)"
  end

  desc 'Cleanup abandoned chat sessions still in waiting state'
  task cleanup_abandoned_chats: :environment do
    cutoff = 15.minutes.ago
    count = 0

    Escalated::ChatSession.waiting.where(created_at: ...cutoff).find_each do |session|
      Escalated::Services::ChatSessionService.end_chat(session)
      count += 1
    end

    puts "Cleaned up #{count} abandoned chat session(s)"
  end
end
