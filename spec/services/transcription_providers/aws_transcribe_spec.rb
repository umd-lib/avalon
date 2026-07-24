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
        context.params[:key] == 'job-1.json' ? { body: transcript_json.to_json } : { body: vtt_body }
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
  end

  describe '#cancel' do
    it 'requests deletion of the provider job' do
      client.stub_responses(:delete_transcription_job, {})
      expect { adapter.cancel('job-1') }.not_to raise_error
    end
  end
end
