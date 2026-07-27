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

# Tracks an AWS Transcribe custom vocabulary managed by Avalon, one per
# Admin::Collection. AWS Transcribe processes Create/UpdateVocabulary calls
# asynchronously (PENDING -> READY/FAILED), so this mirrors TranscriptionRequest's
# submit-then-poll pattern rather than treating the sync call as complete on return.
class TranscriptionVocabulary < ApplicationRecord
  enum :state, { pending: 'pending', ready: 'ready', failed: 'failed' }, default: 'pending', validate: true

  validates :collection_id, presence: true
  validate :collection_must_exist
  validates :phrases, presence: true
  # Restricted to TranscriptionProviders::AwsTranscribe::LANGUAGE_CODE_MAP's
  # keys (not the full LanguageTerm::Iso6392 list, unlike TranscriptionRequest#language) —
  # a custom vocabulary requires an explicit AWS LanguageCode, so only
  # languages this app already knows how to map to one are valid here.
  validates :language, presence: true, inclusion: { in: TranscriptionProviders::AwsTranscribe::LANGUAGE_CODE_MAP.keys }
  validates :aws_vocabulary_name, presence: true

  before_validation :set_default_language, on: :create
  before_validation :set_aws_vocabulary_name, on: :create

  def collection
    @collection ||= Admin::Collection.find(collection_id)
  end

  def phrase_list
    phrases.to_s.lines.map(&:strip).reject(&:blank?)
  end

  private

  def collection_must_exist
    return if collection_id.blank?
    errors.add(:collection_id, 'not found') unless Admin::Collection.exists?(collection_id)
  end

  def set_default_language
    self.language ||= Settings.caption_default.language
  end

  # AWS vocabulary names can't be renamed after creation, so this is fixed
  # once and never recomputed on update.
  def set_aws_vocabulary_name
    return if aws_vocabulary_name.present? || collection_id.blank?

    sanitized_id = collection_id.to_s.gsub(/[^0-9a-zA-Z._-]/, '-')
    self.aws_vocabulary_name = "#{TranscriptionProviders::AwsNaming.job_name_prefix}-vocab-#{sanitized_id}"
  end
end
