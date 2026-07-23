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
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze

  # Allowed status transitions. Terminal statuses have no outgoing
  # transitions; retrying a failed/cancelled request means creating a new record.
  TRANSITIONS = {
    'pending' => %w[submitted cancelled failed],
    'submitted' => %w[in_progress completed failed cancelled],
    'in_progress' => %w[completed failed cancelled],
    'completed' => [],
    'failed' => [],
    'cancelled' => []
  }.freeze

  enum :status, {
    pending: 'pending',
    submitted: 'submitted',
    in_progress: 'in_progress',
    completed: 'completed',
    failed: 'failed',
    cancelled: 'cancelled'
  }, default: 'pending', validate: true

  validates :master_file_id, presence: true
  validate :master_file_must_exist
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validate :only_one_active_request_per_master_file, on: :create

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

  def only_one_active_request_per_master_file
    return if master_file_id.blank?
    if TranscriptionRequest.active.where(master_file_id: master_file_id).where.not(id: id).exists?
      errors.add(:master_file_id, 'already has an active transcription request')
    end
  end
end
