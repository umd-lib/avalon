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

RSpec.describe TranscriptionProviders::AwsTranscribe do
  let(:client) { Aws::TranscribeService::Client.new(stub_responses: true, region: 'us-east-1') }
  let(:s3_client) { Aws::S3::Client.new(stub_responses: true, region: 'us-east-1') }
  let(:adapter) { described_class.new(client: client, s3_client: s3_client) }
  let(:master_file) { FactoryBot.build(:master_file, id: 'abc123') }

  before do
    allow(master_file).to receive(:input_path).and_return('s3://avalon-masterfiles/path/to/video.mp4')
    allow(Settings.transcription.aws).to receive(:output_bucket).and_return('avalon-transcribe-output')
  end

  describe '#submit' do
    it 'starts a transcription job and returns the provider job id' do
      client.stub_responses(:start_transcription_job, transcription_job: { transcription_job_name: 'avalon-abc123-xyz' })

      expect(adapter.submit(master_file: master_file, language: 'eng')).to eq('avalon-abc123-xyz')
    end

    it 'passes a mapped BCP-47 language code for a known language' do
      expect(client).to receive(:start_transcription_job).with(hash_including(language_code: 'en-US')).and_call_original
      adapter.submit(master_file: master_file, language: 'eng')
    end

    it 'falls back to automatic language identification for an unmapped language' do
      expect(client).to receive(:start_transcription_job).with(hash_including(identify_language: true)).and_call_original
      adapter.submit(master_file: master_file, language: 'haw')
    end

    it 'raises UnsupportedMediaSource for a non-S3 media source' do
      allow(master_file).to receive(:input_path).and_return('file:///masterfiles/video.mp4')
      expect { adapter.submit(master_file: master_file) }.to raise_error(TranscriptionProviders::UnsupportedMediaSource)
    end

    it 'requests a VTT subtitle file from AWS Transcribe' do
      expect(client).to receive(:start_transcription_job).with(hash_including(subtitles: { formats: ['vtt'] })).and_call_original
      adapter.submit(master_file: master_file, language: 'eng')
    end

    it 'names the job using the default "avalon" prefix when job_name_prefix is not configured' do
      allow(Settings.transcription.aws).to receive(:job_name_prefix).and_return(nil)
      expect(client).to receive(:start_transcription_job)
        .with(hash_including(transcription_job_name: a_string_matching(/\Aavalon-abc123-[0-9a-f]{8}\z/)))
        .and_call_original
      adapter.submit(master_file: master_file)
    end

    it 'names the job using a configured job_name_prefix, e.g. to scope IAM policies per environment' do
      allow(Settings.transcription.aws).to receive(:job_name_prefix).and_return('avalon-sandbox')
      expect(client).to receive(:start_transcription_job)
        .with(hash_including(transcription_job_name: a_string_matching(/\Aavalon-sandbox-abc123-[0-9a-f]{8}\z/)))
        .and_call_original
      adapter.submit(master_file: master_file)
    end

    it 'does not set output_key when no output_prefix is configured' do
      allow(Settings.transcription.aws).to receive(:output_prefix).and_return(nil)
      expect(client).to receive(:start_transcription_job).with(hash_excluding(:output_key)).and_call_original
      adapter.submit(master_file: master_file)
    end

    it 'sets output_key to the configured prefix, segmenting Transcribe output within a shared bucket' do
      allow(Settings.transcription.aws).to receive(:output_prefix).and_return('transcribe-output')
      expect(client).to receive(:start_transcription_job).with(hash_including(output_key: 'transcribe-output/')).and_call_original
      adapter.submit(master_file: master_file)
    end

    it 'does not add a second trailing slash if the configured prefix already has one' do
      allow(Settings.transcription.aws).to receive(:output_prefix).and_return('transcribe-output/')
      expect(client).to receive(:start_transcription_job).with(hash_including(output_key: 'transcribe-output/')).and_call_original
      adapter.submit(master_file: master_file)
    end

    it 'does not request speaker diarization when disabled (the default)' do
      expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
      adapter.submit(master_file: master_file)
    end

    it 'requests speaker diarization with the configured max_speakers when enabled' do
      allow(Settings.transcription.aws.diarization).to receive_messages(enabled: true, max_speakers: 6)
      expect(client).to receive(:start_transcription_job)
        .with(hash_including(settings: { show_speaker_labels: true, max_speaker_labels: 6 }))
        .and_call_original
      adapter.submit(master_file: master_file)
    end

    context 'when the master file belongs to a collection with its own diarization override' do
      let(:collection) { instance_double(Admin::Collection, id: 'collection-1') }
      let(:media_object) { instance_double(MediaObject, collection: collection) }

      before { allow(master_file).to receive(:media_object).and_return(media_object) }

      it "uses the collection's max_speakers even when it differs from the global default" do
        allow(collection).to receive_messages(diarization_enabled?: true, diarization_max_speakers: 4)

        expect(client).to receive(:start_transcription_job)
          .with(hash_including(settings: { show_speaker_labels: true, max_speaker_labels: 4 }))
          .and_call_original
        adapter.submit(master_file: master_file)
      end

      it 'lets the collection disable diarization even when the global default is enabled' do
        allow(Settings.transcription.aws.diarization).to receive_messages(enabled: true, max_speakers: 6)
        allow(collection).to receive(:diarization_enabled?).and_return(false)

        expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
        adapter.submit(master_file: master_file)
      end

      it "lets the collection enable diarization even when the global default is disabled" do
        allow(collection).to receive_messages(diarization_enabled?: true, diarization_max_speakers: 3)

        expect(client).to receive(:start_transcription_job)
          .with(hash_including(settings: { show_speaker_labels: true, max_speaker_labels: 3 }))
          .and_call_original
        adapter.submit(master_file: master_file)
      end
    end

    context 'custom vocabulary' do
      it 'does not set vocabulary_name when the master file has no owning collection' do
        expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
        adapter.submit(master_file: master_file, language: 'eng')
      end

      context "when the master file belongs to a collection with an Avalon-managed vocabulary" do
        let(:collection) { FactoryBot.create(:collection) }
        let(:media_object) { instance_double(MediaObject, collection: collection) }

        before { allow(master_file).to receive(:media_object).and_return(media_object) }

        it 'does not set vocabulary_name when the collection has none configured' do
          expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
          adapter.submit(master_file: master_file, language: 'eng')
        end

        it 'does not set vocabulary_name while the vocabulary is still pending sync' do
          TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng', state: 'pending')

          expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
          adapter.submit(master_file: master_file, language: 'eng')
        end

        it 'does not set vocabulary_name when the vocabulary failed to sync' do
          TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng', state: 'failed', error_message: 'boom')

          expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
          adapter.submit(master_file: master_file, language: 'eng')
        end

        it 'sets vocabulary_name once the vocabulary is ready and its language matches the job' do
          TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng', state: 'ready')

          expect(client).to receive(:start_transcription_job)
            .with(hash_including(settings: { vocabulary_name: "avalon-vocab-#{collection.id}" }))
            .and_call_original
          adapter.submit(master_file: master_file, language: 'eng')
        end

        it "does not set vocabulary_name when the ready vocabulary's language doesn't match the job" do
          TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'spa', state: 'ready')

          expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
          adapter.submit(master_file: master_file, language: 'eng')
        end

        it 'does not set vocabulary_name when the job falls back to automatic language identification' do
          TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng', state: 'ready')

          expect(client).to receive(:start_transcription_job).with(hash_excluding(:settings)).and_call_original
          adapter.submit(master_file: master_file, language: 'haw')
        end

        it 'combines a ready vocabulary with diarization settings when both are configured' do
          allow(Settings.transcription.aws.diarization).to receive_messages(enabled: true, max_speakers: 6)
          TranscriptionVocabulary.create!(collection_id: collection.id, phrases: 'Archelon', language: 'eng', state: 'ready')

          expect(client).to receive(:start_transcription_job)
            .with(hash_including(settings: { show_speaker_labels: true, max_speaker_labels: 6, vocabulary_name: "avalon-vocab-#{collection.id}" }))
            .and_call_original
          adapter.submit(master_file: master_file, language: 'eng')
        end
      end
    end
  end

  describe '#fetch_status' do
    it 'maps COMPLETED to :completed' do
      client.stub_responses(:get_transcription_job, transcription_job: { transcription_job_status: 'COMPLETED' })
      expect(adapter.fetch_status('job-1').status).to eq(:completed)
    end

    it 'maps FAILED to :failed' do
      client.stub_responses(:get_transcription_job, transcription_job: { transcription_job_status: 'FAILED' })
      expect(adapter.fetch_status('job-1').status).to eq(:failed)
    end

    it 'maps IN_PROGRESS to :in_progress' do
      client.stub_responses(:get_transcription_job, transcription_job: { transcription_job_status: 'IN_PROGRESS' })
      expect(adapter.fetch_status('job-1').status).to eq(:in_progress)
    end
  end

  describe '#fetch_transcript' do
    # AWS Transcribe returns plain (non-presigned) https://s3.../<bucket>/<key>
    # links when writing to a customer-owned output bucket, so the adapter
    # must fetch them via its own authenticated S3 client, not a raw HTTP GET.
    let(:transcript_uri) { 'https://s3.amazonaws.com/avalon-transcribe-output/job-1.json' }
    let(:vtt_uri) { 'https://s3.amazonaws.com/avalon-transcribe-output/job-1.vtt' }
    let(:transcript_json) do
      { 'results' => { 'transcripts' => [{ 'transcript' => 'Hello world.' }] } }
    end
    let(:vtt_body) { "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello world.\n" }

    before do
      allow(Settings.transcription.aws).to receive(:output_bucket).and_return('avalon-transcribe-output')
      s3_client.stub_responses(:get_object, lambda { |context|
        context.params[:key].end_with?('.json') ? { body: transcript_json.to_json } : { body: vtt_body }
      })
    end

    context 'when AWS Transcribe generated a subtitle file' do
      before do
        client.stub_responses(:get_transcription_job, transcription_job: {
                                 transcript: { transcript_file_uri: transcript_uri },
                                 subtitles: { subtitle_file_uris: [vtt_uri] }
                               })
      end

      it 'returns the normalized transcript text' do
        expect(adapter.fetch_transcript('job-1').transcript_text).to eq('Hello world.')
      end

      it 'downloads the AWS-generated VTT as-is, without building its own cues' do
        expect(adapter.fetch_transcript('job-1').caption_vtt).to eq(vtt_body)
      end

      it 'fetches the transcript via the S3 client using the bucket and key, not a raw HTTP request' do
        expect(s3_client).to receive(:get_object).with(bucket: 'avalon-transcribe-output', key: 'job-1.json').and_call_original
        expect(s3_client).to receive(:get_object).with(bucket: 'avalon-transcribe-output', key: 'job-1.vtt').and_call_original
        adapter.fetch_transcript('job-1')
      end
    end

    context 'when no subtitle file was generated' do
      before do
        client.stub_responses(:get_transcription_job, transcription_job: { transcript: { transcript_file_uri: transcript_uri } })
      end

      it 'returns a nil caption_vtt but still returns the transcript text' do
        result = adapter.fetch_transcript('job-1')
        expect(result.caption_vtt).to be_nil
        expect(result.transcript_text).to eq('Hello world.')
      end
    end

    it 'raises TranscriptNotAvailable when no transcript uri is present' do
      client.stub_responses(:get_transcription_job, transcription_job: {})
      expect { adapter.fetch_transcript('job-1') }.to raise_error(TranscriptionProviders::TranscriptNotAvailable)
    end

    context 'when output_prefix segments the output within a shared bucket' do
      let(:transcript_uri) { 'https://s3.amazonaws.com/avalon-transcribe-output/transcribe-output/job-1.json' }
      let(:vtt_uri) { 'https://s3.amazonaws.com/avalon-transcribe-output/transcribe-output/job-1.vtt' }

      before do
        client.stub_responses(:get_transcription_job, transcription_job: {
                                 transcript: { transcript_file_uri: transcript_uri },
                                 subtitles: { subtitle_file_uris: [vtt_uri] }
                               })
      end

      it 'still resolves the correct key, prefix included, from the returned URI' do
        expect(s3_client).to receive(:get_object).with(bucket: 'avalon-transcribe-output', key: 'transcribe-output/job-1.json').and_call_original
        expect(s3_client).to receive(:get_object).with(bucket: 'avalon-transcribe-output', key: 'transcribe-output/job-1.vtt').and_call_original
        adapter.fetch_transcript('job-1')
      end
    end
  end

  describe '#cancel' do
    it 'requests deletion of the provider job' do
      client.stub_responses(:delete_transcription_job, {})
      expect { adapter.cancel('job-1') }.not_to raise_error
    end
  end
end
