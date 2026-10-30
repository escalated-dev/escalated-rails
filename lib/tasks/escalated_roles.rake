# frozen_string_literal: true

# Roles & permissions (ADR 2026-10-29-configurable-access-features).
namespace :escalated do
  namespace :permissions do
    desc 'Create the permissions and the admin, agent and light_agent roles (idempotent)'
    task seed: :environment do
      require 'escalated/seeds/permissions'
      Escalated::Seeds::Permissions.seed!
      puts "Seeded #{Escalated::Seeds::Permissions::PERMISSIONS.size} permissions and the system roles."
    end
  end

  namespace :roles do
    desc 'Give a user an Escalated role: rake "escalated:roles:assign[you@example.com,admin]"'
    task :assign, %i[user role] => :environment do |_task, args|
      user = Escalated::AccessControl.assign_role!(args[:user].to_s, (args[:role].presence || 'admin').to_s)
      puts "Gave #{args[:user]} the #{args[:role].presence || 'admin'} role (user #{user.id})."
    rescue ArgumentError => e
      abort e.message
    end
  end

  namespace :two_factor do
    desc 'Remove the two-factor enrolment of a user (lost device): rake "escalated:two_factor:reset[you@example.com]"'
    task :reset, %i[user] => :environment do |_task, args|
      model = Escalated.configuration.user_model
      ref = args[:user].to_s
      user = model.find_by(email: ref) || (ref.match?(/\A\d+\z/) && model.find_by(id: ref))
      abort "No user [#{ref}]." unless user

      Escalated::TwoFactor.where(user_id: user.id).delete_all
      puts "Removed the two-factor enrolment of user #{user.id}."
    end
  end
end
