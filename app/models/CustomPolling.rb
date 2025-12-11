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

# frozen_string_literal: true
require 'active_support/core_ext/integer/time'
require 'active_model/callbacks'

module CustomPolling
  extend ActiveSupport::Concern

  CALLBACKS = [
      :after_status_update, :after_failed, :after_cancelled, :after_completed
  ].freeze

  included do
    extend ActiveModel::Callbacks

    define_model_callbacks :status_update, :failed, :cancelled, :completed, only: :after

    after_create do |encode|
      # Noop
    end
  end
end

