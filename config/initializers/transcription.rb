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
if Settings.transcription&.enabled
  provider = Settings.transcription.default_provider.to_s

  unless TranscriptionRequest::PROVIDERS.include?(provider)
    raise "Invalid Settings.transcription.default_provider: #{provider.inspect}. " \
          "Must be one of: #{TranscriptionRequest::PROVIDERS.join(', ')}"
  end

  if provider == 'aws_transcribe' && Settings.transcription.aws.output_bucket.blank?
    raise 'Settings.transcription.aws.output_bucket must be set when transcription is enabled with the aws_transcribe provider'
  end
end
