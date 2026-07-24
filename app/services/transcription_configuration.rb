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

# Validates Settings.transcription on boot. Called from
# config/initializers/transcription.rb inside a to_prepare block, since
# TranscriptionRequest isn't guaranteed to be autoloadable yet at plain
# initializer-load time (referencing app classes directly at the top level
# of config/initializers/*.rb is a well-known source of boot-time
# "uninitialized constant" errors — see the Rails autoloading guide).
module TranscriptionConfiguration
  def self.validate!
    return unless Settings.transcription&.enabled

    provider = Settings.transcription.default_provider.to_s

    unless TranscriptionRequest::PROVIDERS.include?(provider)
      raise "Invalid Settings.transcription.default_provider: #{provider.inspect}. " \
            "Must be one of: #{TranscriptionRequest::PROVIDERS.join(', ')}"
    end

    if provider == 'aws_transcribe' && Settings.transcription.aws.output_bucket.blank?
      raise 'Settings.transcription.aws.output_bucket must be set when transcription is enabled with the aws_transcribe provider'
    end
  end
end
