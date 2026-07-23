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

require 'rails_helper'

RSpec.describe TranscriptionRequest, type: :model do
  let(:master_file) { FactoryBot.create(:master_file) }

  def build_request(**attrs)
    TranscriptionRequest.new({ master_file_id: master_file.id, provider: 'aws_transcribe' }.merge(attrs))
  end

  describe 'validations' do
    it 'is valid with a master_file_id and provider' do
      expect(build_request).to be_valid
    end

    it 'requires master_file_id' do
      request = build_request(master_file_id: nil)
      expect(request).not_to be_valid
      expect(request.errors[:master_file_id]).to include('field is required.')
    end

    it 'requires the master_file to exist' do
      request = build_request(master_file_id: 'nonexistent')
      expect(request).not_to be_valid
      expect(request.errors[:master_file_id]).to include('not found')
    end

    it 'requires a provider' do
      request = build_request(provider: nil)
      expect(request).not_to be_valid
    end

    it 'rejects an unsupported provider' do
      request = build_request(provider: 'unsupported_provider')
      expect(request).not_to be_valid
    end

    it 'defaults status to pending' do
      expect(build_request.status).to eq('pending')
    end

    it 'prevents a second active request for the same master file' do
      build_request.save!
      duplicate = build_request

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:master_file_id]).to include('already has an active transcription request')
    end

    it 'allows a new request once the prior request for that master file reaches a terminal state' do
      first = build_request
      first.save!
      first.transition_to!('submitted')
      first.transition_to!('failed', error_message: 'boom')

      expect(build_request).to be_valid
    end

    it 'also enforces the active-request constraint at the database level' do
      build_request.save!
      duplicate = build_request

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#transition_to!' do
    subject(:request) { build_request.tap(&:save!) }

    it 'moves pending -> submitted and stamps submitted_at' do
      expect { request.transition_to!('submitted') }.to change { request.status }.from('pending').to('submitted')
      expect(request.submitted_at).to be_present
    end

    it 'moves submitted -> in_progress -> completed, stamping finished_at and saving extra attributes' do
      request.transition_to!('submitted')
      request.transition_to!('in_progress')
      request.transition_to!('completed', transcript_text: 'hello world')

      expect(request.finished_at).to be_present
      expect(request.transcript_text).to eq('hello world')
    end

    it 'raises InvalidTransition for a disallowed move' do
      expect { request.transition_to!('in_progress') }.to raise_error(TranscriptionRequest::InvalidTransition)
    end

    it 'raises InvalidTransition once the request is in a terminal state' do
      request.transition_to!('cancelled')
      expect { request.transition_to!('submitted') }.to raise_error(TranscriptionRequest::InvalidTransition)
    end
  end

  describe '#active? and #terminal?' do
    it 'reports active for pending/submitted/in_progress' do
      request = build_request
      expect(request.active?).to eq(true)
      expect(request.terminal?).to eq(false)
    end

    it 'reports terminal for completed/failed/cancelled' do
      request = build_request.tap(&:save!)
      request.transition_to!('failed', error_message: 'x')

      expect(request.terminal?).to eq(true)
      expect(request.active?).to eq(false)
    end
  end

  describe 'scopes' do
    it 'filters active vs terminal requests' do
      active_request = build_request.tap(&:save!)

      other_master_file = FactoryBot.create(:master_file)
      terminal_request = TranscriptionRequest.create!(master_file_id: other_master_file.id, provider: 'aws_transcribe')
      terminal_request.transition_to!('cancelled')

      expect(TranscriptionRequest.active).to include(active_request)
      expect(TranscriptionRequest.active).not_to include(terminal_request)
      expect(TranscriptionRequest.terminal).to include(terminal_request)
      expect(TranscriptionRequest.terminal).not_to include(active_request)
    end
  end
end
