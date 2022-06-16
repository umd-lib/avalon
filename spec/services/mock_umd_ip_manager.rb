# Enables a mock of the UmdIPManager, preventing any network calls.
# This method is typically called from "rails_helper.rb", so that
# tests can run without having to individually mock out UmdIPManager calls
def enable_umd_ip_manager_mock
  allow_any_instance_of(UmdIPManager).to receive(:api).and_return(UmdIPManager::MockAPI.new)
end

# Disables UmdIPManager mock set by the "enable_umd_ip_manager_mock" method,
# allowing the actual UmdIPManager network calls to be tested. The network
# calls themselves will typically be mocked as part of the test setup.
def disable_umd_ip_manager_mock
  allow_any_instance_of(UmdIPManager).to receive(:api).and_call_original
end

# Mock implementation of the UmdManager::API class
class UmdIPManager::MockAPI
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
