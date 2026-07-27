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

module TranscriptionProviders
  # Shared naming helpers for AWS Transcribe resources (transcription jobs,
  # custom vocabularies) created by this app. Lets deployments sharing one
  # AWS account across multiple environments (e.g. sandbox/test/qa on the
  # same EKS cluster) scope each environment's IAM policy Resource pattern
  # to only the resources it creates.
  module AwsNaming
    # Defaults to "avalon" — the original, unprefixed-by-environment behavior.
    def self.job_name_prefix
      Settings.transcription.aws.job_name_prefix.presence || 'avalon'
    end
  end
end
