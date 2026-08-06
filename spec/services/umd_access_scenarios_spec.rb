# frozen_string_literal: true

require 'rails_helper'

# UMD Customization
# Checks every expectation declared in UmdAccessScenarios against what Ability and
# SearchBuilder actually decide, so a wrong entry in the harness table fails here rather
# than misleading someone reading the report or debugging a Cypress failure.
describe UmdAccessScenarios, :umd do
  let(:provisioner) { UmdAccessScenarios::Provisioner.new(logger: Logger.new(File::NULL)) }
  let(:ordinary_user) { FactoryBot.create(:user) }
  let(:special_user) do
    FactoryBot.create(:user, username: described_class.special_access_user,
                             email: described_class.special_access_user)
  end
  let(:administrator) { FactoryBot.create(:admin) }

  before do
    Admin::Unit.where(name_ssi: Settings.streaming_reserves.unit_name).first ||
      FactoryBot.create(:unit, name: Settings.streaming_reserves.unit_name)
    Ability.clear_course_reserves_collection_cache
  end

  def ability_for(persona, result)
    media_object = result[:media_object]
    case persona
    when :anonymous then Ability.new(nil)
    when :user then Ability.new(ordinary_user)
    when :manager then Ability.new(User.find_by(username: media_object.collection.managers.first))
    when :administrator then Ability.new(administrator)
    when :special_access_user then Ability.new(special_user)
    when :token_stream, :token_download, :token_expired, :token_revoked
      Ability.new(nil, { access_token: token_for(persona, result) })
    when :ip_in_range, :ip_out_of_range
      Ability.new(nil, { remote_ip: ip_address_for(persona) })
    end
  end

  def token_for(persona, result)
    result[:tokens][persona.to_s.sub('token_', '').to_sym]&.token
  end

  def ip_address_for(persona)
    persona == :ip_in_range ? ENV['IP_IN_RANGE_ADDRESS'] : ENV['IP_OUT_OF_RANGE_ADDRESS']
  end

  # Mirrors what CatalogController does to a search: run the access filters and see whether
  # the item survives them.
  def discoverable?(media_object, ability)
    builder = SearchBuilder.new([], CatalogController.new)
    allow(builder).to receive(:current_ability).and_return(ability)
    permissions = builder.send(:discovery_permissions)
    filters = SearchBuilder.avalon_solr_access_filters_logic.map do |filter|
      builder.send(filter, permissions, ability)
    end
    ActiveFedora::SolrService.query(%(id:"#{media_object.id}"), fq: filters, rows: 1).any?
  end

  described_class.all.each do |scenario|
    describe "#{scenario.slug} (#{scenario.description})" do
      let(:result) { provisioner.provision_scenario(scenario) }

      scenario.personas.each do |persona|
        expected = scenario.expectation_for(persona)
        # The IP personas need a real address to build an ability from. The scenario itself
        # is still provisioned and still probed from campus without one.
        next if persona.to_s.start_with?('ip_') && !described_class.ip_address_configured?

        it "grants #{persona} the declared access" do
          ability = ability_for(persona, result)
          media_object = result[:media_object]

          if expected.key?(:page)
            expect(ability.can?(:read, media_object)).to eq(expected[:page] == 200),
                                                          "expected the item page to be #{expected[:page]} for #{persona}"
          end

          if expected.key?(:stream)
            expect(ability.can?(:stream, media_object)).to eq(expected[:stream]),
                                                           "expected stream=#{expected[:stream]} for #{persona}"
          end

          next unless expected.key?(:browse)

          expect(discoverable?(media_object, ability)).to eq(expected[:browse] == :visible),
                                                          "expected browse=#{expected[:browse]} for #{persona}"
        end
      end
    end
  end

  describe 'definitions' do
    it 'gives every scenario a unique slug' do
      slugs = described_class::SCENARIOS.map(&:slug)
      expect(slugs.uniq).to eq(slugs)
    end

    it 'only declares personas the harness knows how to build' do
      declared = described_class::SCENARIOS.flat_map(&:personas).uniq
      expect(declared - described_class::PERSONAS).to be_empty
    end

    it 'covers the behaviors monitoring watches with canaries' do
      expect(described_class::SCENARIOS.select(&:canary?).map(&:slug))
        .to include('item-public-hidden', 'item-restricted-hidden', 'item-private-hidden')
    end
  end
end
# End UMD Customization
