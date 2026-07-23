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
  class UnknownProvider < StandardError; end

  # Maps a TranscriptionRequest#provider identifier to its adapter class.
  # AssemblyAI (and any future provider) is added here once its adapter is
  # implemented against the same Base contract.
  class Registry
    ADAPTERS = {
      'aws_transcribe' => 'TranscriptionProviders::AwsTranscribe'
    }.freeze

    def self.for(provider)
      class_name = ADAPTERS.fetch(provider.to_s) do
        raise UnknownProvider, "Unknown transcription provider: #{provider}"
      end
      class_name.constantize.new
    end
  end
end
