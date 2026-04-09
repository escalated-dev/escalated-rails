# frozen_string_literal: true

module Escalated
  class MentionService
    MENTION_REGEX = /@(\w+(?:\.\w+)*)/

    # Extract @mentions from reply body and create mention records + notifications
    def process_mentions(reply)
      usernames = extract_mentions(reply.body)
      return [] if usernames.empty?

      users = find_users(usernames)
      mentions = create_mentions(reply, users)
      notify_mentioned_users(reply, mentions)
      mentions
    end

    # Extract unique usernames from text
    def extract_mentions(text)
      return [] if text.blank?

      text.scan(MENTION_REGEX).flatten.uniq
    end

    # Search agents for autocomplete
    def search_agents(query, limit: 10)
      return [] if query.blank?

      user_model = Escalated.configuration.user_model
      scope = user_model.all

      scope = if user_model.column_names.include?('name')
                scope.where('name LIKE :q OR email LIKE :q',
                            q: "%#{Escalated::Ticket.sanitize_sql_like(query)}%")
              else
                scope.where('email LIKE :q',
                            q: "%#{Escalated::Ticket.sanitize_sql_like(query)}%")
              end

      scope.limit(limit).map do |user|
        {
          id: user.id,
          name: user.respond_to?(:name) ? user.name : user.email,
          email: user.email,
          username: extract_username(user)
        }
      end
    end

    # Get unread mentions for a user
    def unread_mentions(user_id)
      Escalated::Mention.for_user(user_id).unread.recent.includes(reply: :ticket)
    end

    # Mark mentions as read
    def mark_as_read(mention_ids, user_id)
      Escalated::Mention.where(id: mention_ids, user_id: user_id).update_all(read_at: Time.current)
    end

    private

    def find_users(usernames)
      user_model = Escalated.configuration.user_model
      users = []

      usernames.each do |username|
        user = if user_model.column_names.include?('username')
                 user_model.find_by(username: username)
               else
                 user_model.find_by(email: "#{username}@%") || user_model.where('email LIKE ?', "#{username}@%").first
               end
        users << user if user
      end

      users.uniq
    end

    def create_mentions(reply, users)
      users.filter_map do |user|
        Escalated::Mention.find_or_create_by!(reply: reply, user: user)
      rescue ActiveRecord::RecordInvalid
        nil
      end
    end

    def notify_mentioned_users(reply, mentions)
      ticket = reply.ticket
      mentions.each do |mention|
        notification_body = "You were mentioned in ticket ##{ticket.reference}"

        # Create an activity record for the mention notification
        Escalated::TicketActivity.create(
          ticket: ticket,
          activity_type: 'mention',
          details: {
            mentioned_user_id: mention.user_id,
            reply_id: reply.id,
            message: notification_body
          }
        )

        Rails.logger.info("Escalated mention notification: user=#{mention.user_id} ticket=#{ticket.reference}")
      end
    end

    def extract_username(user)
      if user.respond_to?(:username) && user.username.present?
        user.username
      else
        user.email.split('@').first
      end
    end
  end
end
