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

RSpec.describe TranscriptionJobs do
  let(:master_file) { FactoryBot.create(:master_file) }
  let(:provider) { instance_double(TranscriptionProviders::AwsTranscribe) }

  before do
    allow(TranscriptionProviders::Registry).to receive(:for).with('aws_transcribe').and_return(provider)
  end

  describe TranscriptionJobs::SubmitTranscriptionRequestJob do
    let(:request) { TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe') }

    it 'submits to the provider and transitions to submitted' do
      allow(provider).to receive(:submit).with(master_file: kind_of(MasterFile), language: request.language).and_return('provider-job-1')

      described_class.perform_now(request.id)

      request.reload
      expect(request.status).to eq('submitted')
      expect(request.provider_job_id).to eq('provider-job-1')
      expect(request.submitted_at).to be_present
    end

    it 'transitions to failed and records the error if submission raises' do
      allow(provider).to receive(:submit).and_raise(StandardError, 'boom')

      described_class.perform_now(request.id)

      request.reload
      expect(request.status).to eq('failed')
      expect(request.error_message).to eq('boom')
    end

    it 'does nothing if the request is not pending' do
      request.transition_to!('submitted', provider_job_id: 'already-submitted')
      expect(provider).not_to receive(:submit)

      described_class.perform_now(request.id)
    end

    it 'does nothing if the request no longer exists' do
      expect(provider).not_to receive(:submit)
      expect { described_class.perform_now(-1) }.not_to raise_error
    end

    it 'does not mark the request failed on a transient provider error — ActiveJob retries it instead' do
      allow(provider).to receive(:submit).and_raise(Aws::TranscribeService::Errors::InternalFailureException.new(nil, 'try again'))

      expect { described_class.perform_now(request.id) }.to have_enqueued_job(described_class).with(request.id)
      expect(request.reload.status).to eq('pending')
    end

    describe '.fail_after_retries' do
      it 'marks the request failed once ActiveJob gives up retrying' do
        described_class.fail_after_retries(request.id, StandardError.new('network still down'))

        request.reload
        expect(request.status).to eq('failed')
        expect(request.error_message).to include('Gave up after retries')
        expect(request.error_message).to include('network still down')
      end

      it 'does nothing if the request is already terminal' do
        request.transition_to!('submitted', provider_job_id: 'x')
        request.transition_to!('cancelled')

        expect { described_class.fail_after_retries(request.id, StandardError.new('boom')) }.not_to raise_error
        expect(request.reload.status).to eq('cancelled')
      end
    end
  end

  describe TranscriptionJobs::PollTranscriptionRequestsJob do
    let(:request) { TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe') }

    before { request.transition_to!('submitted', provider_job_id: 'provider-job-1') }

    it 'moves an in-progress provider job to in_progress' do
      allow(provider).to receive(:fetch_status).with('provider-job-1')
                                                 .and_return(TranscriptionProviders::StatusResult.new(status: :in_progress, raw_response: { foo: 'bar' }))

      described_class.perform_now

      expect(request.reload.status).to eq('in_progress')
    end

    it 'enqueues completion materialization when the provider job is completed' do
      allow(provider).to receive(:fetch_status).with('provider-job-1')
                                                 .and_return(TranscriptionProviders::StatusResult.new(status: :completed, raw_response: {}))

      expect { described_class.perform_now }.to have_enqueued_job(TranscriptionJobs::CompleteTranscriptionRequestJob).with(request.id)
    end

    it 'transitions to failed when the provider reports failure' do
      allow(provider).to receive(:fetch_status).with('provider-job-1')
                                                 .and_return(TranscriptionProviders::StatusResult.new(status: :failed, raw_response: {}))

      described_class.perform_now

      expect(request.reload.status).to eq('failed')
    end

    it 'skips requests that have not been submitted to a provider yet' do
      other_master_file = FactoryBot.create(:master_file)
      TranscriptionRequest.create!(master_file_id: other_master_file.id, provider: 'aws_transcribe')
      expect(provider).to receive(:fetch_status).once
                                                  .and_return(TranscriptionProviders::StatusResult.new(status: :in_progress, raw_response: {}))

      described_class.perform_now
    end

    it 'marks the request failed when a permanent error occurs while polling' do
      allow(provider).to receive(:fetch_status).and_raise(StandardError, 'boom')

      expect { described_class.perform_now }.not_to raise_error
      expect(request.reload.status).to eq('failed')
      expect(request.error_message).to eq('boom')
    end

    it 'leaves the request untouched when a transient error occurs while polling (retried next sweep)' do
      allow(provider).to receive(:fetch_status).and_raise(Aws::TranscribeService::Errors::InternalFailureException.new(nil, 'try again'))

      expect { described_class.perform_now }.not_to raise_error
      expect(request.reload.status).to eq('submitted')
    end
  end

  describe TranscriptionJobs::CompleteTranscriptionRequestJob do
    let(:transcript_result) do
      TranscriptionProviders::TranscriptResult.new(
        transcript_text: 'Hello world.',
        caption_vtt: "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello world.\n",
        raw_response: { 'ok' => true }
      )
    end

    context 'with a master file that belongs to a media object' do
      let(:master_file) { FactoryBot.create(:master_file, :with_media_object) }
      let(:request) { TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe') }

      before { request.transition_to!('submitted', provider_job_id: 'provider-job-1') }

      it 'creates a single caption+transcript SupplementalFile artifact and marks the request completed' do
        allow(provider).to receive(:fetch_transcript).with('provider-job-1').and_return(transcript_result)

        expect { described_class.perform_now(request.id) }.to change(SupplementalFile, :count).by(1)

        request.reload
        expect(request.status).to eq('completed')
        expect(request.transcript_text).to eq('Hello world.')
        expect(request.finished_at).to be_present

        artifact = SupplementalFile.where(parent_id: master_file.id).first

        expect(artifact.caption?).to eq(true)
        expect(artifact.transcript?).to eq(true)
        expect(artifact.machine_generated?).to eq(true)
        expect(artifact.language).to eq(request.language)

        # Not just findable by parent_id — registered on the MasterFile's own
        # supplemental_files_json list, which is what the "Transcribe" button's
        # eligibility check and the Section Files UI actually read from.
        master_file.reload
        expect(master_file.supplemental_files(tag: 'caption')).to include(artifact)
        expect(master_file.supplemental_files(tag: 'transcript')).to include(artifact)
      end

      context 'when the master file is audio-only' do
        let(:master_file) { FactoryBot.create(:master_file, :audio, :with_media_object) }

        it 'tags the artifact transcript only — never caption, which only applies to video' do
          allow(provider).to receive(:fetch_transcript).with('provider-job-1').and_return(transcript_result)

          described_class.perform_now(request.id)

          artifact = SupplementalFile.where(parent_id: master_file.id).first
          expect(artifact.transcript?).to eq(true)
          expect(artifact.caption?).to eq(false)
          expect(artifact.label).to eq('Machine-generated Transcript')
        end
      end

      it 'falls back to a transcript-only artifact when the provider returns no VTT' do
        allow(provider).to receive(:fetch_transcript).with('provider-job-1')
                                                       .and_return(TranscriptionProviders::TranscriptResult.new(
                                                                     transcript_text: 'Hello world.', caption_vtt: nil, raw_response: {}
                                                                   ))

        expect { described_class.perform_now(request.id) }.to change(SupplementalFile, :count).by(1)

        artifact = SupplementalFile.where(parent_id: master_file.id).first
        expect(artifact.transcript?).to eq(true)
        expect(artifact.caption?).to eq(false)
      end

      it 'enqueues a MediaObjectIndexingJob for the parent media object' do
        allow(provider).to receive(:fetch_transcript).and_return(transcript_result)
        expect(MediaObjectIndexingJob).to receive(:perform_later).with(request.media_object_id)

        described_class.perform_now(request.id)
      end

      it 'creates an artifact immediately visible, with no review_status, when the collection does not require review' do
        allow(provider).to receive(:fetch_transcript).and_return(transcript_result)
        described_class.perform_now(request.id)

        artifact = SupplementalFile.where(parent_id: master_file.id).first
        expect(artifact.review_status).to be_nil
        expect(artifact.tags).not_to include('private')
        expect(request.reload.status).to eq('completed')
      end

      context 'when the collection requires human review' do
        before { master_file.media_object.collection.update!(review_required: true) }

        it 'creates the artifact as pending_review and private, and leaves the request in_review' do
          allow(provider).to receive(:fetch_transcript).and_return(transcript_result)
          described_class.perform_now(request.id)

          artifact = SupplementalFile.where(parent_id: master_file.id).first
          expect(artifact.review_status).to eq('pending_review')
          expect(artifact.tags).to include('private')
          expect(request.reload.status).to eq('in_review')
        end
      end

      it 'transitions to failed if materialization raises' do
        allow(provider).to receive(:fetch_transcript).and_raise(StandardError, 'boom')

        described_class.perform_now(request.id)

        request.reload
        expect(request.status).to eq('failed')
        expect(request.error_message).to eq('boom')
      end

      it 'does not mark the request failed on a transient provider error — ActiveJob retries it instead' do
        allow(provider).to receive(:fetch_transcript).and_raise(Aws::TranscribeService::Errors::InternalFailureException.new(nil, 'try again'))

        expect { described_class.perform_now(request.id) }.to have_enqueued_job(described_class).with(request.id)
        expect(request.reload.status).to eq('submitted')
      end

      it '.fail_after_retries marks the request failed once ActiveJob gives up retrying' do
        described_class.fail_after_retries(request.id, StandardError.new('network still down'))

        request.reload
        expect(request.status).to eq('failed')
        expect(request.error_message).to include('Gave up after retries')
      end
    end

    it 'is a no-op if the request is already terminal' do
      request = TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe')
      request.transition_to!('cancelled')
      expect(provider).not_to receive(:fetch_transcript)

      described_class.perform_now(request.id)
    end
  end

  describe TranscriptionJobs::CancelTranscriptionRequestJob do
    let(:request) { TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe') }

    it 'cancels a pending request without calling the provider' do
      expect(provider).not_to receive(:cancel)

      described_class.perform_now(request.id)

      expect(request.reload.status).to eq('cancelled')
    end

    it 'asks the provider to cancel a submitted request' do
      request.transition_to!('submitted', provider_job_id: 'provider-job-1')
      expect(provider).to receive(:cancel).with('provider-job-1')

      described_class.perform_now(request.id)

      expect(request.reload.status).to eq('cancelled')
    end

    it 'still cancels locally even if the provider cancel call raises' do
      request.transition_to!('submitted', provider_job_id: 'provider-job-1')
      allow(provider).to receive(:cancel).and_raise(StandardError, 'boom')

      described_class.perform_now(request.id)

      expect(request.reload.status).to eq('cancelled')
    end

    it 'is a no-op if the request is already terminal' do
      request.transition_to!('cancelled')

      expect { described_class.perform_now(request.id) }.not_to raise_error
    end
  end
end
