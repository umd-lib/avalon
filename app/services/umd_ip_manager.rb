# frozen_string_literal: true

class UmdIPManager
  GROUP_PREFIX = 'umd.ip.manager:'

  def initialize
    @connection = Faraday.new(ENV['IP_MANAGER_SERVER']) do |connection|
      connection.response :json
      connection.adapter :net_http
    end
  end

  def groups
    groups = retrieve_groups
    GroupsResult.new(groups: groups)
  rescue StandardError => e
    GroupsResult.new(errors: [e.message])
  end

  def check_ip(group_base_key:, ip_address:)
    raise ArgumentError, "invalid argument: group_base_key='#{group_base_key}'" unless group_base_key.present?
    raise ArgumentError, "invalid argument: ip_address='#{ip_address}'" unless ip_address.present?

    begin
      ip_is_member = do_check_ip(group_base_key: group_base_key, ip_address: ip_address)
      CheckIPResult.new(ip_is_member: ip_is_member)
    rescue StandardError => e
      CheckIPResult.new(errors: [e.message])
    end
  end

  # Returns an array of UmdIPManager::Group, or raises an exception
  def retrieve_groups
    response = @connection.get('/groups')
    raise APIError, 'unable to retrieve list of groups from IPManager' unless response.success?

    response.body['groups'].map do |group|
      Group.new(base_key: group['key'], name: group['name'])
    end
  end

  # Returns true, if the given IP Address is in the given group,
  # false otherwise. Raise an exception if an error occurs
  def do_check_ip(group_base_key:, ip_address:)
    response = @connection.get('/check', ip: ip_address, group: group_base_key)
    raise APIError, response.body['detail'] unless response.success?

    response.body['contained']
  end

  class APIError < StandardError; end

  class Group
    PREFIX = UmdIPManager::GROUP_PREFIX

    attr_reader :base_key, :prefixed_key, :name

    def initialize(base_key:, name:)
      raise ArgumentError, "invalid argument: base_key='#{base_key}'" unless base_key.present?
      raise ArgumentError, "invalid argument: name='#{name}'" unless name.present?
      @base_key = base_key
      @name = name
      @prefixed_key = Group.as_prefixed_key(base_key)
    end

    # Returns the prefixed key for the given base key.
    def self.as_prefixed_key(base_key)
      raise ArgumentError, "invalid argument: base_key='#{base_key}'" unless base_key.present?
      "#{PREFIX}#{base_key}"
    end

    # Returns the base key for the given prefixed key.
    def self.as_base_key(prefixed_key)
      raise ArgumentError, 'prefixed_key does not start with expected prefix' unless prefixed_key&.starts_with?(PREFIX)
      prefixed_key.delete_prefix(PREFIX)
    end

    # Returns true if the given prefixed_key is a valid prefixed key, false
    # otherwise
    def self.valid_prefixed_key?(prefixed_key)
      return false if prefixed_key.nil?
      prefixed_key.starts_with?(PREFIX)
    end
  end

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

  class CheckIPResult
    attr_reader :errors

    def initialize(ip_is_member: false, errors: [])
      @ip_is_member = ip_is_member
      @errors = errors
    end

    def ip_is_member?
      @ip_is_member
    end

    def success?
      @errors.empty?
    end
  end
end
