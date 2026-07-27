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

RSpec.describe TranscriptionProviders::AwsTranscribeVocabulary do
  let(:client) { Aws::TranscribeService::Client.new(stub_responses: true, region: 'us-east-1') }
  let(:service) { described_class.new(client: client) }
  let(:vocabulary) do
    TranscriptionVocabulary.new(
      aws_vocabulary_name: 'avalon-vocab-abc123',
      language: 'eng',
      phrases: "Archelon\nfoobar"
    )
  end

  describe '#create_or_update' do
    it 'creates the vocabulary in AWS when it has never been synced before' do
      expect(client).to receive(:create_vocabulary).with(
        vocabulary_name: 'avalon-vocab-abc123',
        language_code: 'en-US',
        phrases: ['Archelon', 'foobar']
      ).and_call_original

      service.create_or_update(vocabulary)
    end

    it 'updates the vocabulary in AWS when it has been synced before' do
      vocabulary.last_synced_at = Time.current

      expect(client).to receive(:update_vocabulary).with(
        vocabulary_name: 'avalon-vocab-abc123',
        language_code: 'en-US',
        phrases: ['Archelon', 'foobar']
      ).and_call_original

      service.create_or_update(vocabulary)
    end
  end

  describe '#fetch_state' do
    it 'maps READY to :ready' do
      client.stub_responses(:get_vocabulary, vocabulary_state: 'READY')
      expect(service.fetch_state('avalon-vocab-abc123').state).to eq(:ready)
    end

    it 'maps FAILED to :failed along with the failure reason' do
      client.stub_responses(:get_vocabulary, vocabulary_state: 'FAILED', failure_reason: 'Invalid phrase')
      result = service.fetch_state('avalon-vocab-abc123')

      expect(result.state).to eq(:failed)
      expect(result.failure_reason).to eq('Invalid phrase')
    end

    it 'maps PENDING to :pending' do
      client.stub_responses(:get_vocabulary, vocabulary_state: 'PENDING')
      expect(service.fetch_state('avalon-vocab-abc123').state).to eq(:pending)
    end
  end

  describe '#delete' do
    it 'requests deletion of the AWS vocabulary' do
      client.stub_responses(:delete_vocabulary, {})
      expect { service.delete('avalon-vocab-abc123') }.not_to raise_error
    end
  end
end
