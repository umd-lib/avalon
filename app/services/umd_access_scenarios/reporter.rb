# frozen_string_literal: true

# UMD Customization
# Turns the provisioned scenarios into the three things that consume them: a markdown table
# for manual testing, a JSON manifest for the Cypress spec, and Probe CRDs for monitoring
# the canaries through the DevOps blackbox_exporter.
class UmdAccessScenarios
  class Reporter
    MANIFEST_PATH = Rails.root.join('spec/cypress/fixtures/access_scenarios.json')
    PROBES_PATH = Rails.root.join('umd_docs/monitoring/access_scenario_probes.yaml')

    PROBER = {
      'path' => '/probe',
      'url' => 'blackbox-exporter-prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115'
    }.freeze

    # Modules the DevOps blackbox_exporter offers today. Everything else this generates is
    # a module that has to be requested before the manifest can be deployed -- see
    # #unavailable_modules and the header the generated file carries.
    AVAILABLE_MODULES = %w[
      http_2xx_internet http_403_internet http_2xx_internal http_403_internal
    ].freeze

    def initialize(host: nil, namespace: nil, environment: nil, runbook: nil)
      @host = normalize_host(host.presence || Settings.domain&.host || 'http://av-local:3000')
      @namespace = namespace.presence || 'test'
      @environment = environment.presence || @namespace
      @runbook = runbook.presence
    end

    def markdown_table
      personas = entries.flat_map { |entry| entry[:expectations].keys }.uniq
      lines = [header_row(personas), separator_row(personas)]
      lines += entries.map { |entry| body_row(entry, personas) }
      ([legend] + lines).join("\n")
    end

    def write_manifest
      FileUtils.mkdir_p(File.dirname(MANIFEST_PATH))
      File.write(MANIFEST_PATH, JSON.pretty_generate(host: @host, scenarios: entries))
      MANIFEST_PATH
    end

    # Emits Probe CRDs for the canary items, to be committed to the stack repository.
    #
    # A blackbox_exporter module encodes both the expected status and the network vantage
    # point the request is made from, and one Probe carries exactly one module -- so the
    # canaries are grouped by module, each Probe listing every URL that should behave that
    # way from that vantage.
    def write_probes
      FileUtils.mkdir_p(File.dirname(PROBES_PATH))
      File.write(PROBES_PATH, probes_yaml)
      PROBES_PATH
    end

    # Modules this manifest needs that the blackbox_exporter does not define yet. Avalon
    # answers restricted content with 401, and there is no http_401_* module -- a
    # http_403_* probe would report a failure for a correct 401 -- so these have to be
    # requested from DevOps before the manifest can be deployed.
    def unavailable_modules
      probe_groups.keys.reject { |mod| AVAILABLE_MODULES.include?(mod) }
    end

    def entries
      @entries ||= UmdAccessScenarios.all.filter_map do |scenario|
        media_object = lookup(scenario)
        next if media_object.nil?

        { slug: scenario.slug, description: scenario.description, id: media_object.id,
          url: item_url(media_object), canary: scenario.canary?,
          token_urls: token_urls(media_object), expectations: scenario.expectations }
      end
    end

    private

      # Settings.domain.host carries no scheme, and a URL without one is useless to both
      # Cypress and blackbox_exporter.
      def normalize_host(host)
        host = host.to_s.sub(%r{/\z}, '')
        return host if host.match?(%r{\Ahttps?://})

        local = host.start_with?('localhost', '127.0.0.1', 'av-local', 'test.host')
        "#{local ? 'http' : 'https'}://#{host}"
      end

      def lookup(scenario)
        MediaObject.where(other_identifier_ssim: scenario.identifier).first ||
          MediaObject.where(title_tesi: scenario.title).first
      end

      def item_url(media_object)
        "#{@host}/media_objects/#{media_object.id}"
      end

      def token_urls(media_object)
        AccessToken.where(media_object_id: media_object.id).index_by { |token| token_kind(token) }
                   .transform_values { |token| "#{item_url(media_object)}?access_token=#{token.token}" }
      end

      def token_kind(token)
        return :revoked if token.revoked?
        return :expired if token.expiration.past?
        return :stream if token.allow_streaming?

        :download
      end

      def legend
        "Item page: 200 = renders, 401 = Restricted Content. " \
          "browse: visible/hidden in search results. Blank = not asserted.\n"
      end

      def header_row(personas)
        "| Scenario | URL | #{personas.join(' | ')} |"
      end

      def separator_row(personas)
        "| --- | --- | #{personas.map { '---' }.join(' | ')} |"
      end

      def body_row(entry, personas)
        cells = personas.map { |persona| format_outcome(entry[:expectations][persona]) }
        "| #{entry[:slug]} | #{entry[:url]} | #{cells.join(' | ')} |"
      end

      def format_outcome(outcome)
        return '' if outcome.blank?

        parts = []
        parts << outcome[:page].to_s if outcome.key?(:page)
        parts << "browse:#{outcome[:browse]}" if outcome.key?(:browse)
        parts << (outcome[:stream] ? 'stream' : 'no stream') if outcome.key?(:stream)
        parts << 'download' if outcome[:download]
        parts.join(', ')
      end

      # The vantage point each persona's expectation should be checked from. Anonymous is
      # what an internet-based user sees; the IP Manager personas are what the harness
      # cannot fake over HTTP, and are the reason for probing from a second network.
      PERSONA_VANTAGES = { anonymous: 'internet', ip_in_range: 'campus' }.freeze

      # module => [{slug:, url:, status:}]
      def probe_groups
        @probe_groups ||= UmdAccessScenarios.canaries.each_with_object({}) do |scenario, groups|
          entry = entries.find { |e| e[:slug] == scenario.slug }
          next if entry.nil?

          PERSONA_VANTAGES.each do |persona, vantage|
            status = scenario.expectation_for(persona)[:page]
            next if status.nil?

            (groups["http_#{status_family(status)}_#{vantage}"] ||= []) <<
              { slug: scenario.slug, url: entry[:url], status: status }
          end

          add_token_target(groups, scenario, entry)
        end
      end

      # The point of the token canary is that the token URL still works, which is a
      # different URL from the item -- without this it would only ever be probed
      # anonymously, checking the 401 it shares with every other hidden item.
      def add_token_target(groups, scenario, entry)
        status = scenario.expectation_for(:token_stream)[:page]
        url = entry[:token_urls][:stream]
        return if status.nil? || url.blank?

        (groups["http_#{status_family(status)}_internet"] ||= []) <<
          { slug: "#{scenario.slug} (token URL)", url: url, status: status }
      end

      def status_family(status)
        status.between?(200, 299) ? '2xx' : status.to_s
      end

      def probes_yaml
        documents = probe_groups.map { |mod, targets| probe(mod, targets).to_yaml.sub(/\A---\n/, '') }
        ([probes_header] + documents).join("---\n")
      end

      def probes_header
        warning = if unavailable_modules.any?
                    <<~WARN
                      #
                      # REQUIRES NEW MODULES: #{unavailable_modules.join(', ')}
                      #
                      # Avalon answers restricted content with 401, and the blackbox_exporter defines
                      # only 2xx and 403 modules, so these have to be requested from DevOps before
                      # this manifest can be deployed. A http_403_* probe would report a failure for
                      # a correct 401.
                    WARN
                  else
                    ''
                  end
        <<~HEADER
          # Generated by `rails umd:access_scenarios:report FORMAT=probes` -- do not edit by hand.
          #
          # Probe CRDs for the access control canaries (LIBAVALON-554). Commit these to the
          # Avalon stack repository so the checks deploy with the stack.
          #
          # One Probe carries one module, and a module encodes both the expected status and the
          # network the request is made from -- so each Probe below lists every canary URL that
          # should answer that way from that vantage. Failures are told apart by the `instance`
          # label, which carries the URL.
          #{warning}#
          # See umd_docs/AccessScenarioHarness.md.
        HEADER
      end

      def probe(mod, targets)
        {
          'kind' => 'Probe',
          'apiVersion' => 'monitoring.coreos.com/v1',
          'metadata' => probe_metadata(mod, targets),
          'spec' => probe_spec(mod, targets)
        }
      end

      def probe_metadata(mod, targets)
        { 'labels' => { 'part-of' => 'avalon' },
          'name' => "avalon-access-#{mod.tr('_', '-')}",
          'namespace' => @namespace,
          'annotations' => { 'lib.umd.edu/description' => description_for(mod, targets) } }
      end

      def description_for(mod, targets)
        expectation = targets.first[:status] == 200 ? 'be viewable' : "answer #{targets.first[:status]}"
        vantage = vantage_of(mod)
        article = vantage.start_with?('i') ? 'an' : 'a'
        "Avalon access control canaries that should #{expectation} from #{article} #{vantage}-based " \
          "user: #{targets.map { |t| t[:slug] }.join(', ')}. LIBAVALON-554."
      end

      def vantage_of(mod)
        mod.split('_').last
      end

      def probe_spec(mod, targets)
        { 'interval' => '60s', 'scrapeTimeout' => '15s',
          'jobName' => "#{@environment}-avalon-access-#{mod.tr('_', '-')}",
          'module' => mod, 'prober' => PROBER.dup,
          'targets' => { 'staticConfig' => static_config(targets) } }
      end

      def static_config(targets)
        labels = { 'part-of' => 'avalon', 'component' => 'access-control' }
        labels['runbook'] = @runbook if @runbook
        { 'labels' => labels, 'static' => targets.map { |t| t[:url] } }
      end
  end
end
# End UMD Customization
