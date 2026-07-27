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

RSpec.describe TranscriptionVocabularyJobs do
  let(:collection) { FactoryBot.create(:collection) }
  let(:service) { instance_double(TranscriptionProviders::AwsTranscribeVocabulary) }

  before do
    allow(TranscriptionProviders::AwsTranscribeVocabulary).to receive(:new).and_return(service)
  end

  describe TranscriptionVocabularyJobs::SyncVocabularyJob do
    let(:vocabulary) { TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng') }

    it 'syncs to the provider and stamps last_synced_at' do
      allow(service).to receive(:create_or_update).with(vocabulary)

      described_class.perform_now(vocabulary.id)

      vocabulary.reload
      expect(vocabulary.last_synced_at).to be_present
      expect(vocabulary.state).to eq('pending')
    end

    it 'transitions to failed and records the error if syncing raises' do
      allow(service).to receive(:create_or_update).and_raise(StandardError, 'boom')

      described_class.perform_now(vocabulary.id)

      vocabulary.reload
      expect(vocabulary.state).to eq('failed')
      expect(vocabulary.error_message).to eq('boom')
    end

    it 'does nothing if the vocabulary no longer exists' do
      expect(service).not_to receive(:create_or_update)
      expect { described_class.perform_now(-1) }.not_to raise_error
    end

    it 'does not mark the vocabulary failed on a transient provider error — ActiveJob retries it instead' do
      allow(service).to receive(:create_or_update).and_raise(Aws::TranscribeService::Errors::InternalFailureException.new(nil, 'try again'))

      expect { described_class.perform_now(vocabulary.id) }.to have_enqueued_job(described_class).with(vocabulary.id)
      expect(vocabulary.reload.state).to eq('pending')
    end

    describe '.fail_after_retries' do
      it 'marks the vocabulary failed once ActiveJob gives up retrying' do
        described_class.fail_after_retries(vocabulary.id, StandardError.new('network still down'))

        vocabulary.reload
        expect(vocabulary.state).to eq('failed')
        expect(vocabulary.error_message).to include('Gave up after retries')
        expect(vocabulary.error_message).to include('network still down')
      end
    end
  end

  describe TranscriptionVocabularyJobs::PollVocabulariesJob do
    let(:vocabulary) { TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng', state: 'pending') }

    it 'moves a pending vocabulary to ready' do
      allow(service).to receive(:fetch_state).with(vocabulary.aws_vocabulary_name)
                                              .and_return(TranscriptionProviders::AwsTranscribeVocabulary::StateResult.new(state: :ready))

      described_class.perform_now

      expect(vocabulary.reload.state).to eq('ready')
    end

    it 'moves a pending vocabulary to failed, recording the failure reason' do
      allow(service).to receive(:fetch_state).with(vocabulary.aws_vocabulary_name)
                                              .and_return(TranscriptionProviders::AwsTranscribeVocabulary::StateResult.new(state: :failed, failure_reason: 'Invalid phrase'))

      described_class.perform_now

      vocabulary.reload
      expect(vocabulary.state).to eq('failed')
      expect(vocabulary.error_message).to eq('Invalid phrase')
    end

    it 'leaves a still-pending vocabulary untouched' do
      allow(service).to receive(:fetch_state).with(vocabulary.aws_vocabulary_name)
                                              .and_return(TranscriptionProviders::AwsTranscribeVocabulary::StateResult.new(state: :pending))

      expect { described_class.perform_now }.not_to change { vocabulary.reload.state }
    end

    it 'only polls pending vocabularies' do
      ready = TranscriptionVocabulary.create!(collection_id: FactoryBot.create(:collection).id, phrases: 'foo', language: 'eng', state: 'ready')
      vocabulary
      expect(service).to receive(:fetch_state).once.with(vocabulary.aws_vocabulary_name)
                                                .and_return(TranscriptionProviders::AwsTranscribeVocabulary::StateResult.new(state: :pending))

      described_class.perform_now
      expect(ready.reload.state).to eq('ready')
    end

    it 'marks the vocabulary failed when a permanent error occurs while polling' do
      vocabulary # force creation before perform_now queries TranscriptionVocabulary.pending
      allow(service).to receive(:fetch_state).and_raise(StandardError, 'boom')

      expect { described_class.perform_now }.not_to raise_error
      vocabulary.reload
      expect(vocabulary.state).to eq('failed')
      expect(vocabulary.error_message).to eq('boom')
    end

    it 'leaves the vocabulary untouched when a transient error occurs while polling (retried next sweep)' do
      vocabulary # force creation before perform_now queries TranscriptionVocabulary.pending
      allow(service).to receive(:fetch_state).and_raise(Aws::TranscribeService::Errors::InternalFailureException.new(nil, 'try again'))

      expect { described_class.perform_now }.not_to raise_error
      expect(vocabulary.reload.state).to eq('pending')
    end
  end

  describe TranscriptionVocabularyJobs::DeleteVocabularyJob do
    let(:vocabulary) { TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng') }

    it 'deletes the AWS vocabulary and destroys the local record' do
      expect(service).to receive(:delete).with(vocabulary.aws_vocabulary_name)

      described_class.perform_now(vocabulary.id)

      expect(TranscriptionVocabulary.exists?(vocabulary.id)).to eq(false)
    end

    it 'still destroys the local record even if the provider delete call raises' do
      allow(service).to receive(:delete).and_raise(StandardError, 'boom')

      described_class.perform_now(vocabulary.id)

      expect(TranscriptionVocabulary.exists?(vocabulary.id)).to eq(false)
    end

    it 'does nothing if the vocabulary no longer exists' do
      expect(service).not_to receive(:delete)
      expect { described_class.perform_now(-1) }.not_to raise_error
    end
  end
end
