# frozen_string_literal: true

# UMD Customization
# Creates and removes the access-control scenario fixtures declared in
# UmdAccessScenarios. Kept out of the rake task so that
# spec/services/umd_access_scenarios_spec.rb can exercise the same code that operators run.
#
# Provisioning is idempotent: an existing item for a scenario is updated in place rather
# than duplicated, so the task can be re-run after a definition changes.
class UmdAccessScenarios
  class Provisioner
    attr_reader :results

    # The repository already ships a short video and its three quality renditions, so the
    # harness uses those unless told otherwise -- items come out with a real section and
    # derivatives, and nobody has to supply files to get a player on the page.
    FIXTURE_MASTER_FILE = Rails.root.join('spec/fixtures/videoshort.mp4')
    FIXTURE_DERIVATIVES = {
      'high' => Rails.root.join('spec/fixtures/videoshort.high.mp4'),
      'medium' => Rails.root.join('spec/fixtures/videoshort.medium.mp4'),
      'low' => Rails.root.join('spec/fixtures/videoshort.low.mp4')
    }.freeze

    # media: optional hash of :master_file_path, :derivatives (quality => path) and
    # :derivative_hls_url. Pass media: false for metadata-only items, which is enough for
    # every discoverability and page-access check but leaves no player to look at.
    def initialize(media: nil, logger: Rails.logger)
      @media = media.nil? ? default_media : media.presence
      @logger = logger
      @results = []
    end

    def provision
      unit = find_or_create_unit
      collections = provision_collections(unit)

      UmdAccessScenarios.all.each do |scenario|
        collection = collections[scenario.collection]
        if collection.nil?
          @logger.warn("[access_scenarios] skipping #{scenario.slug}: its collection could not be created")
          next
        end
        @results << build(scenario, collection)
      end

      @results
    end

    # Provisions a single scenario and the collection it needs. Used by the specs, which
    # keep each example independent rather than sharing one expensive setup.
    def provision_scenario(scenario)
      spec = UmdAccessScenarios.collection_spec(scenario)
      collection = upsert_collection(spec, unit_for(spec, find_or_create_unit))
      build(scenario, collection)
    end

    # Destroys everything the harness created. Canary items are left standing unless asked
    # for, since external monitoring probes them continuously.
    def teardown(include_canaries: false)
      destroyed = 0

      harness_collections.each do |collection|
        collection.media_objects.to_a.each do |media_object|
          next if !include_canaries && canary?(media_object)

          AccessToken.where(media_object_id: media_object.id).destroy_all
          media_object.destroy
          destroyed += 1
        end
        collection.reload
        collection.destroy if collection.media_objects.empty?
      end

      unit = Admin::Unit.where(name_ssi: UNIT_NAME).first
      unit.destroy if unit && unit.collections.empty?
      destroyed
    end

    def harness_collections
      Admin::Collection.all.to_a.select { |c| c.name.to_s.start_with?(COLLECTION_PREFIX) }
    end

    private

      def build(scenario, collection)
        media_object = provision_media_object(scenario, collection)
        { scenario: scenario, collection: collection, media_object: media_object,
          tokens: provision_tokens(scenario, media_object) }
      end

      def canary?(media_object)
        slug = media_object.title.to_s.sub("#{COLLECTION_PREFIX} ", '')
        UmdAccessScenarios.find(slug)&.canary? == true
      end

      def find_or_create_unit
        Admin::Unit.where(name_ssi: UNIT_NAME).first ||
          Admin::Unit.create!(name: UNIT_NAME, description: 'Access control test scenarios',
                              unit_admins: [manager_user.user_key])
      end

      # Course Reserves scenarios must live in the real Streaming Reserves unit --
      # Ability.course_reserves_collection assumes there is exactly one, so the harness
      # never creates a second. Where that unit does not exist (a bare development stack),
      # those scenarios are skipped rather than failing the whole run.
      def unit_for(collection_spec, harness_unit)
        return harness_unit unless collection_spec.course_reserves?

        unit = Admin::Unit.where(name_ssi: Settings.streaming_reserves.unit_name).first
        if unit.nil?
          @logger.warn("[access_scenarios] no '#{Settings.streaming_reserves.unit_name}' unit; " \
                       'skipping the Course Reserves scenarios')
        end
        unit
      end

      def provision_collections(harness_unit)
        by_slug = UmdAccessScenarios.collection_specs.index_by(&:slug).filter_map do |slug, spec|
          unit = unit_for(spec, harness_unit)
          [slug, upsert_collection(spec, unit)] if unit
        end.to_h
        map_collections_to_keys(by_slug)
      end

      def map_collections_to_keys(by_slug)
        COLLECTIONS.transform_values { |spec| by_slug[spec.slug] }.compact
      end

      def upsert_collection(spec, unit)
        collection = Admin::Collection.where(name_ssi: spec.name).first ||
                     Admin::Collection.new(name: spec.name, unit: unit)
        collection.unit = unit
        collection.description = 'Access control test scenario collection'
        collection.managers = [manager_user.user_key]
        collection.default_visibility = spec.default_visibility
        collection.default_hidden = spec.default_hidden
        collection.default_read_users = UmdAccessScenarios.resolve(spec.default_read_users) || []
        collection.default_read_groups = UmdAccessScenarios.resolve(spec.default_read_groups) || []
        collection.save!
        collection
      end

      def provision_media_object(scenario, collection)
        media_object = find_media_object(scenario) || MediaObject.new
        apply_metadata(media_object, scenario, collection)
        apply_access(media_object, scenario)
        media_object.save!
        # section_ids rather than sections: this only needs to know whether media is
        # already attached, and loading the sections fails noisily if a previous run left
        # a half-written one behind.
        attach_media(media_object) if @media && media_object.section_ids.empty?
        @logger.info("[access_scenarios] #{scenario.slug} -> #{media_object.id}")
        media_object
      end

      def find_media_object(scenario)
        harness_collections.lazy.flat_map { |c| c.media_objects.to_a }
                           .find { |mo| mo.title == scenario.title }
      end

      def apply_metadata(media_object, scenario, collection)
        media_object.title = scenario.title
        media_object.creator = ['UMD Access Scenario Harness']
        media_object.date_issued = Time.zone.today.edtf.to_s
        media_object.abstract = scenario.description
        media_object.collection = collection
        media_object.governing_policies = [collection]
        media_object.other_identifier = [{ id: scenario.identifier, source: IDENTIFIER_SOURCE }]
        media_object.avalon_publisher = scenario.published? ? 'access scenario harness' : nil
      end

      # Order matters: visibility= rewrites read_groups, so special access has to be added
      # afterwards or it is silently dropped.
      def apply_access(media_object, scenario)
        media_object.visibility = scenario.visibility
        media_object.hidden = scenario.hidden
        media_object.disable_inheritance = scenario.disable_inheritance
        media_object.read_users = UmdAccessScenarios.resolve(scenario.read_users) || []
        extra_groups = UmdAccessScenarios.resolve(scenario.read_groups) || []
        media_object.read_groups += extra_groups if extra_groups.any?
      end

      def provision_tokens(scenario, media_object)
        kinds = Array(scenario.tokens)
        return {} if kinds.empty?

        # Re-provisioning replaces tokens rather than accumulating them.
        AccessToken.where(media_object_id: media_object.id).destroy_all
        kinds.index_with { |kind| build_token(kind, media_object) }
      end

      def build_token(kind, media_object)
        token = AccessToken.new(media_object_id: media_object.id, user: manager_user)
        token.allow_streaming = %i[stream expired revoked].include?(kind)
        token.allow_download = %i[download expired revoked].include?(kind)
        token.expiration = kind == :expired ? 1.day.ago : 1.year.from_now
        token.revoked = (kind == :revoked)
        token.save!(validate: kind != :expired)
        token
      end

      def manager_user
        @manager_user ||= find_or_create_user(ENV['HARNESS_MANAGER_USER'].presence ||
                                              'zz-axs-manager@example.com')
      end

      def find_or_create_user(username)
        User.find_by(username: username) || User.find_by(email: username) ||
          User.create!(username: username, email: username,
                       password: SecureRandom.urlsafe_base64(16))
      end

      # Falls back to the fixtures the rest of the suite already uses. Absent (a deployment
      # built without spec/), items are metadata-only rather than a failed provision.
      def default_media
        return nil unless File.exist?(FIXTURE_MASTER_FILE)

        { master_file_path: FIXTURE_MASTER_FILE.to_s,
          derivatives: FIXTURE_DERIVATIVES.select { |_q, path| File.exist?(path) }
                                          .transform_values(&:to_s) }
      end

      # Attaches the master file and its derivatives directly, bypassing ActiveEncode --
      # the harness is testing access control, not transcoding.
      def attach_media(media_object)
        master_file = build_master_file(media_object)
        master_file.derivatives += derivative_paths.map { |quality, path| build_derivative(quality, path) }
        master_file.save!
        # Assign rather than append: the getter resolves the existing section ids, which
        # raises if an interrupted run left one behind. Harness items have a single section.
        media_object.sections = [master_file]
        media_object.save!
      end

      def derivative_paths
        @media[:derivatives].presence ||
          { 'high' => @media[:derivative_path] }.compact
      end

      # The media object is associated *after* creation on purpose. Passing media_object:
      # into MasterFile.create! leaves a resource in Fedora with no model triple: it comes
      # back as a bare ActiveFedora::Base, MasterFile.count stays 0, nothing indexes, and
      # every item page 500s trying to load its sections.
      def build_master_file(media_object)
        master_file = MasterFile.create!(
          file_location: @media[:master_file_path], file_format: 'Moving image',
          workflow_name: 'avalon', duration: '6120', display_aspect_ratio: '1.7777777777777777',
          original_frame_size: '1024x768', width: '1024', height: '768',
          date_digitized: Time.now.utc.iso8601, workflow_id: SecureRandom.uuid
        )
        master_file.media_object = media_object
        master_file.save!
        record_completed_encode(master_file)
        master_file
      end

      # percent_complete and status_code are read-only on MasterFile, derived from the
      # associated encode record -- so a finished-looking section needs the record, not
      # attribute assignment. Same approach as the :master_file factory.
      def record_completed_encode(master_file)
        global_id = "gid://ActiveEncode/#{master_file.encoder_class}/#{master_file.workflow_id}"
        return if ActiveEncode::EncodeRecord.exists?(global_id: global_id)

        ActiveEncode::EncodeRecord.create!(
          global_id: global_id, state: 'completed', adapter: 'ffmpeg', progress: 100,
          title: master_file.id, display_title: master_file.id,
          # errors and current_operations have to be present: MasterFile#error reads
          # raw_encode_record['errors'].first without guarding against nil, and #to_solr
          # calls it on every save.
          raw_object: { state: 'completed', percent_complete: 100, errors: [],
                        current_operations: [], output: [] }.to_json,
          create_options: { master_file_id: master_file.id }.to_json
        )
      end

      def build_derivative(quality, path)
        Derivative.create!(
          quality: quality, duration: '6120', track_id: "track-#{quality}",
          hls_track_id: "track-#{quality}-hls", width: '1024', height: '768',
          location_url: path, hls_url: hls_url_for(path), derivativeFile: "file://#{path}"
        )
      end

      def hls_url_for(path)
        base = @media[:derivative_hls_url].presence
        return "file://#{path}" if base.nil?

        "#{base.sub(%r{/\z}, '')}/#{File.basename(path)}.m3u8"
      end
  end
end
# End UMD Customization
