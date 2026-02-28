FactoryBot.define do
  factory :escalated_skill, class: "Escalated::Skill" do
    name { Faker::Job.unique.field }

    trait :with_agents do
      after(:create) do |skill|
        users = create_list(:user, 2)
        users.each do |user|
          Escalated::AgentSkill.create!(user: user, skill: skill)
        end
      end
    end
  end
end
