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

# Tracks a single async transcription request for one MasterFile section,
# from provider submission through completion/failure/cancellation.
class TranscriptionRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  # Provider adapters supported by the transcription pipeline. AWS is the
  # only fully implemented adapter for the POC; assembly_ai is reserved for
  # the follow-on phase and not yet backed by a working adapter.
  PROVIDERS = %w[aws_transcribe assembly_ai].freeze

  ACTIVE_STATUSES = %w[pending submitted in_progress].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled rejected].freeze

  # Allowed status transitions. Terminal statuses have no outgoing
  # transitions; retrying a failed/cancelled request means creating a new record.
  #
  # in_review is deliberately excluded from ACTIVE_STATUSES: the provider job
  # is already done (that's how we got here — see
  # TranscriptionJobs::CompleteTranscriptionRequestJob), so
  # PollTranscriptionRequestsJob must not keep polling it (it would just
  # re-observe :completed and re-enqueue completion materialization,
  # duplicating SupplementalFile artifacts). It's also excluded from
  # TERMINAL_STATUSES since a human still needs to act — see
  # TranscriptionReviewsController#approve/#reject, which transition a
  # matching in_review request to completed/rejected once that happens.
  TRANSITIONS = {
    'pending' => %w[submitted cancelled failed],
    'submitted' => %w[in_progress completed in_review failed cancelled],
    'in_progress' => %w[completed in_review failed cancelled],
    'in_review' => %w[completed rejected],
    'completed' => [],
    'failed' => [],
    'cancelled' => [],
    'rejected' => []
  }.freeze

  enum :status, {
    pending: 'pending',
    submitted: 'submitted',
    in_progress: 'in_progress',
    in_review: 'in_review',
    completed: 'completed',
    failed: 'failed',
    cancelled: 'cancelled',
    rejected: 'rejected'
  }, default: 'pending', validate: true

  validates :master_file_id, presence: true
  validate :master_file_must_exist
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :language, inclusion: { in: LanguageTerm::Iso6392.map.keys }, allow_nil: true
  validate :only_one_active_request_per_master_file, on: :create

  before_validation :set_default_language, on: :create
  before_validation :set_media_object_id, on: :create

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }

  # Moves this request to new_status, raising InvalidTransition if that move
  # isn't allowed from the current status. Stamps submitted_at/finished_at
  # as appropriate. Any additional attributes (e.g. transcript_text,
  # raw_response, error_message) are saved in the same update.
  def transition_to!(new_status, attributes = {})
    new_status = new_status.to_s
    allowed = TRANSITIONS.fetch(status, [])
    unless allowed.include?(new_status)
      raise InvalidTransition, "cannot transition TranscriptionRequest##{id} from #{status} to #{new_status}"
    end

    attributes = attributes.merge(status: new_status)
    attributes[:submitted_at] ||= Time.current if new_status == 'submitted'
    attributes[:finished_at] ||= Time.current if TERMINAL_STATUSES.include?(new_status)

    update!(attributes)
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def master_file
    @master_file ||= MasterFile.find(master_file_id)
  end

  private

  def master_file_must_exist
    return if master_file_id.blank?
    errors.add(:master_file_id, 'not found') unless MasterFile.exists?(master_file_id)
  end

  # Prefers the MediaObject's own cataloged language (MODS languageTerm,
  # e.g. set via the item's descriptive metadata) over the global
  # Settings.caption_default.language fallback — a French item should be
  # transcribed as French, not silently default to English. Only used when
  # it resolves to a code TranscriptionRequest itself considers valid (the
  # `language` inclusion validation below); an unrecognized/legacy MODS
  # code falls back to the global default rather than failing validation.
  def set_default_language
    self.language ||= media_object_language_code || Settings.caption_default.language
  end

  def media_object_language_code
    return nil if master_file_id.blank? || !MasterFile.exists?(master_file_id)

    # MediaObject#language (app/models/concerns/media_object_mods.rb) returns
    # [{code:, text:}, ...] from its MODS languageTerm elements — there's no
    # plain language_code reader on the model itself, only the datastream's.
    code = MasterFile.find(master_file_id).media_object&.language&.first&.[](:code).presence
    code if code && LanguageTerm::Iso6392.map.key?(code)
  end

  def set_media_object_id
    return if master_file_id.blank? || media_object_id.present?
    return unless MasterFile.exists?(master_file_id)

    self.media_object_id = MasterFile.find(master_file_id).media_object_id
  end

  def only_one_active_request_per_master_file
    return if master_file_id.blank?
    if TranscriptionRequest.active.where(master_file_id: master_file_id).where.not(id: id).exists?
      errors.add(:master_file_id, 'already has an active transcription request')
    end
  end
end
