# frozen_string_literal: true

# UMD Customization
# Declarative definitions of the UMD access-control scenarios (LIBAVALON-554).
#
# One place describes every combination of collection settings, item settings and access
# grants worth exercising, along with the outcome expected of each persona. Three things
# consume these definitions, so none of them can drift from the others:
#
#   * lib/tasks/umd_access_scenarios.rake -- provisions, reports on and tears down the set
#   * spec/services/umd_access_scenarios_spec.rb -- checks every declared expectation
#     against what Ability actually decides
#   * spec/cypress/integration/umd_access_scenarios_spec.js -- drives them over HTTP
#
# Expectations are deliberately sparse: declare a persona only where its outcome is
# interesting for that scenario. See umd_docs/AccessScenarioHarness.md.
class UmdAccessScenarios
  # Everything the harness creates carries this identifier prefix, and teardown selects on
  # it alone -- nothing else distinguishes harness content from real content.
  IDENTIFIER_PREFIX = 'zz-axs'
  IDENTIFIER_SOURCE = 'local'
  UNIT_NAME = 'ZZ Access Scenarios (harness)'
  COLLECTION_PREFIX = 'ZZ-AXS'

  # The first four map to accounts cy.login() already knows about
  # (spec/cypress/cypress.env.local.json).
  PERSONAS = %i[
    anonymous
    user
    manager
    administrator
    special_access_user
    token_stream
    token_download
    token_expired
    token_revoked
    ip_in_range
    ip_out_of_range
  ].freeze

  CollectionSpec = Struct.new(
    :slug, :kind, :default_visibility, :default_hidden, :default_read_users, :default_read_groups,
    keyword_init: true
  ) do
    def name
      "#{COLLECTION_PREFIX}-#{slug}"
    end

    def course_reserves?
      kind == :course_reserves
    end
  end

  Scenario = Struct.new(
    :slug, :description, :collection, :published, :visibility, :hidden, :disable_inheritance,
    :read_users, :read_groups, :tokens, :expectations, :canary, :requires_ip,
    keyword_init: true
  ) do
    def identifier
      "#{IDENTIFIER_PREFIX}-#{slug}"
    end

    def title
      "#{COLLECTION_PREFIX} #{slug}"
    end

    def published?
      published != false
    end

    def canary?
      canary == true
    end

    def expectation_for(persona)
      (expectations || {})[persona] || {}
    end

    def personas
      (expectations || {}).keys
    end
  end

  # Convenience for the tables below. Sparse by design -- an omitted key is not asserted.
  def self.outcome(browse: nil, page: nil, stream: nil, download: nil)
    { browse: browse, page: page, stream: stream, download: download }.compact
  end

  # Special access is granted to a named user. Locally this is an account the harness
  # creates; on av-test there are no local password accounts, so pass a real CAS username.
  def self.special_access_user
    ENV['SPECIAL_ACCESS_USER'].presence || 'zz-axs-special@example.com'
  end

  # UMD IP Manager group used by the IP-based scenarios, e.g. "umd.ip.manager:campus".
  # Nil when unconfigured, which makes those scenarios skip rather than fail.
  def self.ip_group
    key = ENV['IP_GROUP_KEY'].presence
    key && "#{UmdIpManager::GROUP_PREFIX}#{key}"
  end

  def self.ip_scenarios_configured?
    ip_group.present? && ENV['IP_IN_RANGE_ADDRESS'].present?
  end

  COLLECTIONS = {
    standard: CollectionSpec.new(
      slug: 'standard', kind: :standard, default_visibility: 'public', default_hidden: false
    ),
    standard_hidden: CollectionSpec.new(
      slug: 'standard-hidden', kind: :standard, default_visibility: 'public', default_hidden: true
    ),
    restricted_hidden: CollectionSpec.new(
      slug: 'restricted-hidden', kind: :standard, default_visibility: 'restricted', default_hidden: true
    ),
    private_hidden: CollectionSpec.new(
      slug: 'private-hidden', kind: :standard, default_visibility: 'private', default_hidden: true
    ),
    private_visible: CollectionSpec.new(
      slug: 'private-visible', kind: :standard, default_visibility: 'private', default_hidden: false
    ),
    special_user_hidden: CollectionSpec.new(
      slug: 'special-user-hidden', kind: :standard, default_visibility: 'private', default_hidden: true,
      default_read_users: -> { [special_access_user] }
    ),
    course_reserves: CollectionSpec.new(
      slug: 'course-reserves', kind: :course_reserves, default_visibility: 'private', default_hidden: false
    ),
    course_reserves_ip: CollectionSpec.new(
      slug: 'course-reserves-ip', kind: :course_reserves, default_visibility: 'private', default_hidden: false,
      default_read_groups: -> { [ip_group].compact }
    )
  }.freeze

  # rubocop:disable Metrics/BlockLength
  SCENARIOS = [
    # --- Item Access and hiding set on the item itself -----------------------------
    Scenario.new(
      slug: 'item-public',
      description: 'Public item, discoverable. The ordinary case.',
      collection: :standard, visibility: 'public', hidden: false, disable_inheritance: true,
      expectations: {
        anonymous: outcome(browse: :visible, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'item-public-hidden',
      description: 'Public item hidden from search. Must stay reachable by direct URL.',
      collection: :standard, visibility: 'public', hidden: true, disable_inheritance: true,
      canary: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'item-restricted',
      description: 'Logged-in-only item, discoverable. Anonymous sees metadata, cannot stream.',
      collection: :standard, visibility: 'restricted', hidden: false, disable_inheritance: true,
      expectations: {
        anonymous: outcome(page: 200, stream: false),
        user: outcome(browse: :visible, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'item-restricted-hidden',
      description: 'Logged-in-only item, hidden. Anonymous is refused, logged-in users are not.',
      collection: :standard, visibility: 'restricted', hidden: true, disable_inheritance: true,
      canary: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        user: outcome(browse: :hidden, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'item-private',
      description: 'Collection-staff-only item, not hidden. Metadata is public, playback is not.',
      collection: :standard, visibility: 'private', hidden: false, disable_inheritance: true,
      expectations: {
        anonymous: outcome(page: 200, stream: false),
        manager: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'item-private-hidden',
      description: 'Collection-staff-only item, hidden. Refused to everyone but staff.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      canary: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        user: outcome(browse: :hidden, page: 401, stream: false),
        manager: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'item-unpublished-private',
      description: 'Unpublished staff-only item. Invisible and unreachable.',
      collection: :standard, published: false, visibility: 'private', hidden: false,
      disable_inheritance: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        manager: outcome(page: 200)
      }
    ),
    Scenario.new(
      slug: 'item-unpublished-public',
      description: 'Unpublished item whose Item Access is public: the page still renders. ' \
                   'Known divergence from upstream, tracked as LIBAVALON-178 -- the two ' \
                   'upstream specs asserting a 401 here are marked pending for it. Pinned ' \
                   'so that the day it changes, it changes deliberately.',
      collection: :standard, published: false, visibility: 'public', hidden: false,
      disable_inheritance: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 200, stream: false)
      }
    ),

    # --- Item Access and hiding inherited from the collection ----------------------
    Scenario.new(
      slug: 'coll-public',
      description: 'Public collection, item inherits. The ordinary case.',
      collection: :standard, visibility: 'public', hidden: false, disable_inheritance: false,
      expectations: {
        anonymous: outcome(browse: :visible, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'coll-public-hidden',
      description: 'Hidden collection, public item. Same as item-public-hidden, set one level up.',
      collection: :standard_hidden, visibility: 'public', hidden: false, disable_inheritance: false,
      canary: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'coll-restricted-hidden',
      description: 'Hidden logged-in-only collection, item inherits.',
      collection: :restricted_hidden, visibility: 'restricted', hidden: false,
      disable_inheritance: false,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        user: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'coll-private-hidden',
      description: 'Hidden staff-only collection, item inherits.',
      collection: :private_hidden, visibility: 'private', hidden: false, disable_inheritance: false,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        manager: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'coll-private-visible',
      description: 'Staff-only collection that is not hidden: discoverable but not streamable.',
      collection: :private_visible, visibility: 'private', hidden: false, disable_inheritance: false,
      expectations: {
        anonymous: outcome(browse: :visible, page: 200, stream: false)
      }
    ),
    Scenario.new(
      slug: 'override-visible-in-hidden-collection',
      description: 'Item overrides a hidden collection and is itself visible.',
      collection: :standard_hidden, visibility: 'public', hidden: false, disable_inheritance: true,
      expectations: {
        anonymous: outcome(browse: :visible, page: 200, stream: true)
      }
    ),

    # --- Assign special access -----------------------------------------------------
    Scenario.new(
      slug: 'special-user-hidden',
      description: 'Hidden staff-only item with special access granted to one user.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      read_users: -> { [special_access_user] },
      expectations: {
        anonymous: outcome(page: 401, stream: false),
        user: outcome(page: 401, stream: false),
        special_access_user: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'special-user-collection-hidden',
      description: 'Same grant made on the collection instead of the item.',
      collection: :special_user_hidden, visibility: 'private', hidden: false,
      disable_inheritance: false,
      expectations: {
        anonymous: outcome(page: 401, stream: false),
        special_access_user: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'special-ip-hidden',
      description: 'Hidden staff-only item with special access granted to an IP Manager group.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      read_groups: -> { [ip_group].compact },
      canary: true, requires_ip: true,
      expectations: {
        anonymous: outcome(page: 401, stream: false),
        ip_out_of_range: outcome(page: 401, stream: false),
        ip_in_range: outcome(page: 200, stream: true)
      }
    ),

    # --- Course Reserves -----------------------------------------------------------
    Scenario.new(
      slug: 'cr-public-item',
      description: 'Public item in a Course Reserves collection: reachable but never discoverable.',
      collection: :course_reserves, visibility: 'public', hidden: false, disable_inheritance: false,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'cr-private-item',
      description: 'Staff-only item in a Course Reserves collection.',
      collection: :course_reserves, visibility: 'private', hidden: false, disable_inheritance: false,
      canary: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        manager: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'cr-ip-item',
      description: 'Course Reserves collection granting access to an IP Manager group.',
      collection: :course_reserves_ip, visibility: 'private', hidden: false,
      disable_inheritance: false,
      canary: true, requires_ip: true,
      expectations: {
        anonymous: outcome(browse: :hidden, page: 401, stream: false),
        ip_in_range: outcome(page: 200, stream: true)
      }
    ),

    # --- Access tokens -------------------------------------------------------------
    Scenario.new(
      slug: 'token-stream',
      description: 'Hidden staff-only item reached through a streaming access token URL.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      tokens: %i[stream], canary: true,
      expectations: {
        anonymous: outcome(page: 401, stream: false),
        token_stream: outcome(page: 200, stream: true)
      }
    ),
    Scenario.new(
      slug: 'token-download',
      description: 'Hidden staff-only item reached through a download-only access token URL.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      tokens: %i[download],
      expectations: {
        anonymous: outcome(page: 401),
        token_download: outcome(page: 200, stream: false, download: true)
      }
    ),
    Scenario.new(
      slug: 'token-expired',
      description: 'Expired token grants nothing.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      tokens: %i[expired],
      expectations: {
        token_expired: outcome(page: 401, stream: false)
      }
    ),
    Scenario.new(
      slug: 'token-revoked',
      description: 'Revoked token grants nothing.',
      collection: :standard, visibility: 'private', hidden: true, disable_inheritance: true,
      tokens: %i[revoked],
      expectations: {
        token_revoked: outcome(page: 401, stream: false)
      }
    )
  ].freeze
  # rubocop:enable Metrics/BlockLength

  class << self
    def all
      SCENARIOS.reject { |scenario| skip?(scenario) }
    end

    def canaries
      all.select(&:canary?)
    end

    def find(slug)
      SCENARIOS.find { |scenario| scenario.slug == slug.to_s }
    end

    def collection_spec(scenario)
      COLLECTIONS.fetch(scenario.collection)
    end

    def collection_specs
      all.map { |scenario| collection_spec(scenario) }.uniq
    end

    # IP-based scenarios need a configured group and a known in-range address; without
    # them they are skipped rather than reported as failures.
    def skip?(scenario)
      scenario.requires_ip == true && !ip_scenarios_configured?
    end

    # Resolves a value that may have been declared as a lambda, so that scenarios can refer
    # to environment-dependent users and groups without freezing them at load time.
    def resolve(value)
      value.is_a?(Proc) ? instance_exec(&value) : value
    end
  end
end
# End UMD Customization
