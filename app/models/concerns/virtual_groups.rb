# Copyright 2011-2024, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

# module Avalon
#   module AccessControls
    module VirtualGroups
      extend ActiveSupport::Concern

      def local_read_groups
        self.read_groups.select {|g| Admin::Group.exists? g}
      end

      def ip_read_groups
        self.read_groups.select {|g| IPAddr.new(g) rescue false }
      end

      # UMD Customization
      def umd_ip_manager_read_groups
        self.read_groups.select {|g| UmdIpManager::Group.valid_prefixed_key?(g) }
      end
      # End UMD Customization

      def virtual_read_groups
        # UMD Customization
        self.read_groups - represented_visibility - local_read_groups - ip_read_groups - umd_ip_manager_read_groups
        # End UMD Customization
      end
    end
#   end
# end
