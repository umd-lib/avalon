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

module TranscriptionVocabularyJobs
  module Logging
    PREFIX = '[TranscriptionVocabularyJobs]'

    def log_vocabulary(level, message, vocabulary: nil, **extra)
      context = {
        job: self.class.name,
        transcription_vocabulary_id: vocabulary&.id,
        collection_id: vocabulary&.collection_id,
        aws_vocabulary_name: vocabulary&.aws_vocabulary_name
      }.merge(extra).compact

      formatted_context = context.map { |k, v| "#{k}=#{v}" }.join(' ')
      Rails.logger.public_send(level, "#{PREFIX} #{message} #{formatted_context}".strip)
    end
  end
end
