# frozen_string_literal: true

require 'spec_helper'
require 'json'

# ====================================================================== #
# Page Name Parity
#
# Every page name this engine renders has to resolve to a component in
# @escalated-dev/escalated.
#
# Inertia resolving a name to nothing is not an error. The response is a 200,
# the resolver returns undefined, Vue renders nothing, and the panel comes up
# blank -- which reads as a permissions problem or an empty dataset. Several
# screens shipped that way across this portfolio before anyone noticed.
#
# Neither repo's specs can see it alone: a controller spec asserts a status,
# and the frontend never hears the name. This is the comparison, against the
# manifest the frontend package publishes and this repo vendors at
# spec/fixtures/escalated-pages.json.
#
# Adding a screen goes: component into the frontend, frontend release, refresh
# the fixture, then render the name here. In that order, or it ships blank.
# ====================================================================== #

module PageNameParity
  MANIFEST = File.expand_path('fixtures/escalated-pages.json', __dir__)

  # Names that render a blank panel today and are not fixed by renaming. Each
  # is a case where this engine's surface is a different shape from the
  # component's, so pointing the name at it would render a form of blanks whose
  # Save posts fields the controller ignores -- worse than blank, because it
  # looks like it works.
  #
  #   Reports/{Cohort,Frt*,Resolution*}
  #     Nine advanced-report endpoints pass { data:, filters: } while every
  #     report component takes flat props. Three of the nine resolve by name and
  #     still render an empty report; these six do not resolve at all. Closing
  #     them means collapsing the three FRT endpoints into the one ResponseTimes
  #     screen and the two resolution endpoints into ResolutionTimes.
  #
  #   Settings/Csat
  #     Persists csat_enabled, csat_send_after_hours and csat_message;
  #     CsatSettings is built around csat_question_text, csat_scale,
  #     csat_delivery_trigger and csat_delay_hours. Aligning them changes the
  #     settings keys this engine stores.
  #
  #   Settings/Sso
  #     Exposes an OIDC-shaped surface (sso_client_id, sso_issuer); SsoSettings
  #     is SAML-and-JWT-shaped (sso_entity_id, sso_certificate, sso_jwt_secret,
  #     the attribute mappings).
  #
  # This list may shrink. It must never grow.
  KNOWN_BLANK = [
    'Escalated/Admin/Reports/Cohort',
    'Escalated/Admin/Reports/FrtByAgent',
    'Escalated/Admin/Reports/FrtDistribution',
    'Escalated/Admin/Reports/FrtTrends',
    'Escalated/Admin/Reports/ResolutionDistribution',
    'Escalated/Admin/Reports/ResolutionTrends',
    'Escalated/Admin/Settings/Csat',
    'Escalated/Admin/Settings/Sso'
  ].freeze

  PAGE_NAME = %r{'(Escalated/[A-Za-z0-9/_]+)'}

  module_function

  def shipped_pages
    @shipped_pages ||= JSON.parse(File.read(MANIFEST)).fetch('pages')
  end

  # Page names rendered anywhere in app/ or lib/, mapped to the files that
  # render them, so a failure can name the file and not only the string.
  def rendered_pages
    @rendered_pages ||= begin
      root = File.expand_path('..', __dir__)

      Dir.glob(File.join(root, '{app,lib}', '**', '*.rb')).each_with_object({}) do |path, found|
        File.read(path).scan(PAGE_NAME).flatten.each do |name|
          (found[name] ||= Set.new) << Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
        end
      end
    end
  end

  def explain(missing)
    lines = ['these page names have no component in @escalated-dev/escalated, so they render a blank panel:']
    missing.each { |name| lines << "  #{name}  (#{rendered_pages[name].to_a.join(', ')})" }
    lines << ''
    lines << 'Either the name is wrong, or the component has not been released yet.'
    lines << 'If it has been: refresh spec/fixtures/escalated-pages.json from the package.'
    lines.join("\n")
  end
end

RSpec.describe 'page name parity' do # rubocop:disable RSpec/DescribeClass
  include PageNameParity

  it 'renders only page names the frontend ships' do
    expect(rendered_pages).not_to(
      be_empty, 'found no page names at all, which means this spec is not looking where it should'
    )

    missing = (rendered_pages.keys - shipped_pages - PageNameParity::KNOWN_BLANK).sort

    expect(missing).to eq([]), -> { explain(missing) }
  end

  it 'has a manifest that is present and looks like one' do
    # A fixture gone missing or empty would make the example above pass by
    # comparing against nothing.
    expect(File).to exist(PageNameParity::MANIFEST)
    expect(shipped_pages.length).to be > 50
    expect(shipped_pages).to all(start_with('Escalated/'))
  end

  it 'does not keep excusing names that have been fixed' do
    # The exception list is a record of work still owed. Leaving an entry in it
    # after the screen is fixed is how the list stops meaning anything.
    # This spec loads spec_helper rather than rails_helper -- it reads source,
    # not the database -- so ActiveSupport's exclude? is not available here.
    stale = PageNameParity::KNOWN_BLANK.reject do |name|
      rendered_pages.key?(name) && !shipped_pages.include?(name) # rubocop:disable Rails/NegateInclude
    end

    expect(stale).to(
      eq([]),
      'these names are on the blank-screen exception list but no longer need ' \
      "to be, remove them:\n  #{stale.join("\n  ")}"
    )
  end
end
