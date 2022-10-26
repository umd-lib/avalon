require 'rails_helper'

def mock_ip_check_response(ip_address:, group:, contained:)
  {
    '@id': "http://ipmanager-local:3001/check?ip=#{ip_address}&group=#{group}",
    group: {
      '@id': "http://ipmanager-local:3001/groups/#{group}",
      key: group,
      name: "#{group.capitalize} Group"
    },
    ip: ip_address,
    contained: contained
  }
end

def mock_ip_check_list_response(ip_address:, groups: {})
  {
    '@id': "http://ipmanager-local:3001/check?ip=#{ip_address}",
    ip: ip_address,
    checks: groups.map do |key, contained|
      mock_ip_check_response(ip_address: ip_address, group: key.to_s, contained: contained)
    end
  }
end

def stub_ip_check_list_request(ip_address:, groups: {})
  stub_request(:get, 'ipmanager-local:3001/check').
    with(query: {ip: ip_address}).
    to_return(
      headers: {'Content-Type': 'application/json'},
      body: JSON.dump(
        mock_ip_check_list_response(ip_address: ip_address, groups: groups)
      )
    )
end

describe UmdIpManager do
  before(:each) do
    disable_umd_ip_manager_mock
  end

  let(:ip_manager) {
    ENV['IP_MANAGER_SERVER_URL'] = 'http://ipmanager-local:3001'
    described_class.new
  }

  context '#groups' do
    it 'returns a GroupsResult with a list of UmdIpManager::Groups on success' do
      test_group = UmdIpManager::Group.new(key: 'test-group', name: 'Test Group')
      allow(ip_manager.api).to receive(:all_groups) {
        [test_group]
      }

      groups_result = ip_manager.groups

      expect(groups_result.success?).to be(true)
      expect(groups_result.groups).to contain_exactly(test_group)
    end

    it 'returns a GroupsResult with errors on failure' do
      allow(ip_manager.api).to receive(:all_groups) { raise StandardError, "An error occurred" }

      groups_result = ip_manager.groups
      expect(groups_result.success?).to be(false)
    end

    it 'returns a GroupResult with a limited list of groups when checking an IP' do
      stub_ip_check_list_request(
        ip_address: '127.0.0.1',
        groups: {
          test1: true,
          test2: false,
          test3: false,
          test4: true
        }
      )
      result = ip_manager.groups(ip_address: '127.0.0.1')
      expect(result.success?).to be(true)
      expect(result.groups.length).to eq(2)
      expected_prefixed_keys = [ UmdIpManager::Group.as_prefixed_key('test1'), UmdIpManager::Group.as_prefixed_key('test4') ]
      expect(result.groups.map {|g| g.prefixed_key}).to match_array(expected_prefixed_keys)
    end
  end
end

describe UmdIpManager::GroupsResult do
  context '#success?' do
    it 'returns true when there are no errors' do
      groups_result = described_class.new
      expect(groups_result.success?).to be(true)
      expect(groups_result.errors.length).to eq(0)
    end

    it 'returns false when there are errors' do
      groups_result = described_class.new(errors: ['An error occurred!'])
      expect(groups_result.success?).to be(false)
      expect(groups_result.errors.length).to eq(1)
    end
  end

  it 'returns a list of provided groups' do
    group1 = UmdIpManager::Group.new(key: 'group-1', name: 'Group 1')
    group2 = UmdIpManager::Group.new(key: 'group-2', name: 'Group 2')
    groups = [group1, group2]

    groups_result = described_class.new(groups: groups)
    expect(groups_result.groups).to contain_exactly(group1, group2)
  end

  it 'may return an empty list of groups' do
    groups_result = described_class.new
    expect(groups_result.groups).to be_empty
    expect(groups_result.success?).to be(true)
  end
end

describe UmdIpManager::Group do
  EXPECTED_PREFIX = 'umd.ip.manager:'

  it 'provides the prefixed_key for a group' do
    group = described_class.new(key: 'test-key', name: 'Test')
    expect(group.prefixed_key).to eq("#{EXPECTED_PREFIX}test-key")
  end

  it 'provides the name of the group' do
    group = described_class.new(key: 'test-key', name: 'Test')
    expect(group.name).to eq('Test')
  end

  context '#initialize' do
    it 'raises an ArgumentError when given invalid parameters' do
      expect { described_class.new }.to raise_error(ArgumentError)
      expect { described_class.new(name: '') }.to raise_error(ArgumentError)
      expect { described_class.new(key: '') }.to raise_error(ArgumentError)
      expect { described_class.new(key: '', name: '') }.to raise_error(ArgumentError)
      expect { described_class.new(key: 'foo', name: '') }.to raise_error(ArgumentError)
      expect { described_class.new(key: '', name: 'Foo') }.to raise_error(ArgumentError)
    end

    it 'is properly constructed when given valid parameters' do
      group = described_class.new(key: 'test-key', name: 'Test')
      expect(group.name).to eq('Test')
      expect(group.prefixed_key).to eq("#{EXPECTED_PREFIX}test-key")
    end
  end

  context '.as_prefixed_key' do
    context 'raises an ArgumentError' do
      it 'when given a nil key' do
        expect { described_class.as_prefixed_key(nil) }.to raise_error(ArgumentError)
      end

      it 'when given an empty key' do
        expect { described_class.as_prefixed_key('') }.to raise_error(ArgumentError)
      end

      it 'when given an key of only whitespace' do
        expect { described_class.as_prefixed_key("  \t  ") }.to raise_error(ArgumentError)
      end
    end

    it 'returns the given key prefixed with UmdIpManager::Group.PREFIX' do
      expect(described_class.as_prefixed_key('foo')).to eq("#{EXPECTED_PREFIX}foo")
    end
  end

  context '.valid_prefixed_key?' do
    context 'returns false' do
      it 'when given a nil prefixed_key' do
        expect(described_class.valid_prefixed_key?(nil)).to be(false)
      end

      it 'when given an empty prefixed_key' do
        expect(described_class.valid_prefixed_key?('')).to be(false)
      end

      it 'when given a prefixed_key without the expected prefix' do
        expect(described_class.valid_prefixed_key?("UNEXPECTED_PREFIX:test")).to be(false)
      end
    end

    it 'returns true when given prefixed_key with the expected prefix' do
      expect(described_class.valid_prefixed_key?("#{EXPECTED_PREFIX}foo")).to be(true)
    end
  end
end
