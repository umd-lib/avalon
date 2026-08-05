# frozen_string_literal: true

# UMD Customization
# Provision, report on and tear down the access-control scenarios declared in
# UmdAccessScenarios. See umd_docs/AccessScenarioHarness.md.
namespace :umd do
  namespace :access_scenarios do
    desc 'Create the access control test scenarios (collections, items, access tokens)'
    task provision: :environment do
      guard_environment!

      results = UmdAccessScenarios::Provisioner.new(media: media_options, logger: Logger.new($stdout))
                                               .provision
      puts "Provisioned #{results.count} scenarios."
      puts 'Items are metadata-only (METADATA_ONLY=true).' if media_options == false
      puts "Skipped IP scenarios: set IP_GROUP_KEY and IP_IN_RANGE_ADDRESS to include them." unless UmdAccessScenarios.ip_scenarios_configured?
    end

    desc 'Print the scenario expectation table, and write the Cypress manifest'
    task report: :environment do
      reporter = UmdAccessScenarios::Reporter.new(host: ENV['HOST'], namespace: ENV['PROBE_NAMESPACE'],
                                                  environment: ENV['PROBE_ENVIRONMENT'],
                                                  runbook: ENV['PROBE_RUNBOOK'])

      case ENV['FORMAT']
      when 'probes'
        path = reporter.write_probes
        puts "Wrote Probe CRDs to #{path}"
        if reporter.unavailable_modules.any?
          puts "These modules do not exist in the blackbox_exporter yet and must be requested " \
               "from DevOps: #{reporter.unavailable_modules.join(', ')}"
        end
      when 'json'
        path = reporter.write_manifest
        puts "Wrote Cypress manifest to #{path}"
      else
        puts reporter.markdown_table
        puts
        puts "Cypress manifest: #{reporter.write_manifest}"
      end
    end

    desc 'Destroy the access control test scenarios (canaries survive unless INCLUDE_CANARIES=true)'
    task teardown: :environment do
      guard_environment!

      include_canaries = ActiveModel::Type::Boolean.new.cast(ENV['INCLUDE_CANARIES'])
      destroyed = UmdAccessScenarios::Provisioner.new(logger: Logger.new($stdout))
                                                 .teardown(include_canaries: include_canaries)
      puts "Destroyed #{destroyed} scenario items."
      puts 'Canary items were left in place (INCLUDE_CANARIES=true to remove them).' unless include_canaries
    end
  end
end

# Provisioning writes real content, so anywhere but development has to be asked for
# explicitly.
def guard_environment!
  return if Rails.env.development? || Rails.env.test?
  return if ActiveModel::Type::Boolean.new.cast(ENV['ALLOW_ACCESS_SCENARIOS'])

  abort("Refusing to run in #{Rails.env}. Set ALLOW_ACCESS_SCENARIOS=true to proceed.")
end

# nil lets the provisioner use the videoshort fixtures the rest of the suite already uses;
# false asks for metadata-only items.
def media_options
  return false if ActiveModel::Type::Boolean.new.cast(ENV['METADATA_ONLY'])
  return nil if ENV['MASTER_FILE_PATH'].blank?

  { master_file_path: ENV['MASTER_FILE_PATH'],
    derivative_path: ENV['DERIVATIVE_PATH'],
    derivative_hls_url: ENV['DERIVATIVE_HLS_URL'] }
end
# End UMD Customization
