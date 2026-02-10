Gem::Specification.new do |spec|
  spec.name          = "escalated"
  spec.version       = "0.4.0"
  spec.authors       = ["Escalated Dev"]
  spec.email         = ["hello@escalated.dev"]
  spec.summary       = "Embeddable support ticket system for Rails"
  spec.description   = "A full-featured support ticket system with SLA, escalation rules, and three hosting modes."
  spec.homepage      = "https://github.com/escalated-dev/escalated-rails"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "db/**/*", "resources/**/*", "stubs/**/*", "LICENSE", "README.md"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "inertia_rails", ">= 3.0"
  spec.add_dependency "pundit", ">= 2.0"

  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "factory_bot_rails"
  spec.add_development_dependency "faker"
  spec.add_development_dependency "shoulda-matchers"
end
