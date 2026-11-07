# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'escalated'
  spec.version       = '0.7.12'
  spec.authors       = ['Escalated Dev']
  spec.email         = ['hello@escalated.dev']
  spec.summary       = 'Embeddable support ticket system for Rails'
  spec.description   = 'A full-featured support ticket system with SLA, escalation rules, and three hosting modes.'
  spec.homepage      = 'https://github.com/escalated-dev/escalated-rails'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*', 'app/**/*', 'config/**/*', 'db/**/*', 'resources/**/*', 'stubs/**/*',
                   'vendor/widget/**/*', 'LICENSE', 'README.md']

  spec.add_dependency 'csv'
  spec.add_dependency 'escalated-locale', '~> 0.1'
  spec.add_dependency 'inertia_rails', '>= 3.0'
  # 2.10.3 and 3.2.0 fix GHSA-c32j-vqhx-rx3x; 3.0.0-3.1.2 are affected.
  spec.add_dependency 'jwt', '>= 2.10.3', '< 4', '!= 3.0.0', '!= 3.1.0', '!= 3.1.1', '!= 3.1.2'
  spec.add_dependency 'oauth2', '~> 2.0', '>= 2.0.22' # GHSA-pp92-crg2-gfv9
  spec.add_dependency 'pundit', '>= 2.0'
  spec.add_dependency 'rails', '>= 8.0'
  spec.add_dependency 'rexml', '>= 3.4.2' # GHSA-c2f4-jgmc-q2r5 and earlier ReDoS fixes
  spec.add_dependency 'rotp', '~> 6.3'
  spec.add_dependency 'ruby-saml', '~> 1.18', '>= 1.18.1' # GHSA-rrqh-93c8-j966

  spec.add_development_dependency 'factory_bot_rails'
  spec.add_development_dependency 'faker'
  spec.add_development_dependency 'rspec-rails'
  spec.add_development_dependency 'shoulda-matchers'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
