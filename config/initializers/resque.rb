rails_root = ENV['RAILS_ROOT'] || File.dirname(__FILE__) + '/../..'
rails_env = ENV['RAILS_ENV'] || 'development'

Resque.redis = "#{Settings.redis.host}:#{Settings.redis.port}"

Resque.logger = Logger.new(rails_root + "/log/resque.log")

# Enable schedule tab in Resque web ui
require 'resque-scheduler'
require 'resque/scheduler/server'
