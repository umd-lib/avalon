# Enables a mock of the UmdIpManager, preventing any network calls.
# This method is typically called from "rails_helper.rb", so that
# tests can run without having to individually mock out UmdIpManager calls
def enable_umd_ip_manager_mock
  allow_any_instance_of(UmdIpManager).to receive(:api).and_return(UmdIpManager::MockAPI.new)
end

# Disables UmdIpManager mock set by the "enable_umd_ip_manager_mock" method,
# allowing the actual UmdIpManager network calls to be tested. The network
# calls themselves will typically be mocked as part of the test setup.
def disable_umd_ip_manager_mock
  allow_any_instance_of(UmdIpManager).to receive(:api).and_call_original
end

# Mock implementation of the UmdManager::API class
class UmdIpManager::MockAPI
  def initialize
  end

  def all_groups
    []
  end

  def ip_in_group?(group_key:, ip_address:)
    false
  end

  def groups_for_ip(ip_address)
    []
  end
end
