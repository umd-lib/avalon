HealthCheck.setup do |config|
  # exclude smtp check
  config.standard_checks -= [ 'emailconf' ]
end