# Copyright 2011-2026, The Trustees of Indiana University and Northwestern
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

# Fail fast on boot if transcription is enabled but misconfigured, rather
# than discovering it the first time an admin clicks "Transcribe" (or the
# first sidekiq-cron poll sweep runs). No-op when the feature flag is off.
#
# Wrapped in to_prepare (same pattern as the sidekiq-cron registration in
# config/initializers/sidekiq.rb) rather than run directly here: app classes
# like TranscriptionRequest aren't guaranteed autoloadable yet at plain
# initializer-load time, and referencing them directly here intermittently
# raises "NameError: uninitialized constant TranscriptionRequest" at boot.
Rails.application.config.to_prepare do
  TranscriptionConfiguration.validate!
end
