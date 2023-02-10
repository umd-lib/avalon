# frozen_string_literal: true

class UmdIpManager
  # Prefix for UMD IP Manager groups, so that they can be identified
  # in the collection/media_object "read_groups"
  GROUP_PREFIX = 'umd.ip.manager:'

  def api
    @api ||= API.new
  end

  # Returns a GroupResult containing all the IP Manager groups that match
  # the given IP address. If no IP address is given, all IP Manager groups
  # are returned.
  def groups(ip_address: nil)
    groups = ip_address.nil? ? api.all_groups : api.groups_for_ip(ip_address)
    GroupsResult.new(groups: groups)
  rescue StandardError => e
    Rails.logger.error(e)
    GroupsResult.new(errors: [e.message])
  end

  class API
    def initialize
      @connection = Faraday.new(ENV['IP_MANAGER_SERVER_URL']) do |connection|
        connection.response :json
        connection.adapter :net_http
      end
    end

    # Returns an array of UmdIpManager::Group, or raises an exception
    def all_groups
      response = @connection.get('/groups')
      raise APIError, 'unable to retrieve list of groups from IPManager' unless response.success?

      response.body['groups'].map do |group|
        Group.new(key: group['key'], name: group['name'])
      end
    end

    # Returns all the groups in IP Manager that contain the given IP address.
    def groups_for_ip(ip_address)
      response = @connection.get('/check', ip: ip_address)
      raise APIError, response.body['detail'] unless response.success?

      response.body['checks'].select { |c| c['contained'] }.map do |check|
        Group.new(key: check['group']['key'], name: check['group']['name'])
      end
    end
  end

  class APIError < StandardError; end

  class Group
    PREFIX = UmdIpManager::GROUP_PREFIX

    attr_reader :prefixed_key, :name

    def initialize(key:, name:)
      raise ArgumentError, "invalid argument: key='#{key}'" unless key.present?
      raise ArgumentError, "invalid argument: name='#{name}'" unless name.present?
      @key = key
      @name = name
      @prefixed_key = Group.as_prefixed_key(key)
    end

    # Returns the prefixed key for the given IP Manager key.
    def self.as_prefixed_key(key)
      raise ArgumentError, "invalid argument: key='#{key}'" unless key.present?
      "#{PREFIX}#{key}"
    end

    # Returns true if the given prefixed_key is a valid prefixed key, false
    # otherwise
    def self.valid_prefixed_key?(prefixed_key)
      return false if prefixed_key.nil?
      prefixed_key.starts_with?(PREFIX)
    end
  end

  # Encapsulates the response from the IP Manager, in a protocol-neutral way
  class GroupsResult
    include Enumerable

    attr_reader :groups, :errors

    def initialize(groups: [], errors: [])
      @groups = groups
      @errors = errors
    end

    def each(&block)
      @groups.each(&block)
    end

    # Returns true if no errors occurred, false otherwise.
    def success?
      @errors.empty?
    end
  end
end
