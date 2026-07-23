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

require 'aws-sdk-transcribeservice'

module TranscriptionProviders
  # AWS Transcribe adapter. AWS Transcribe reads media directly from S3, so
  # this adapter only supports MasterFiles whose resolved media source is an
  # s3:// URI (see MasterFile#input_path) — local filesystem sources raise
  # UnsupportedMediaSource.
  class AwsTranscribe < Base
    # Maps Avalon's 3-letter ISO 639-2 language codes to AWS Transcribe's
    # BCP-47 LanguageCode values, for the common cases. A language with no
    # mapping falls back to AWS Transcribe's automatic language identification.
    LANGUAGE_CODE_MAP = {
      'eng' => 'en-US',
      'spa' => 'es-US',
      'fre' => 'fr-FR',
      'fra' => 'fr-FR',
      'ger' => 'de-DE',
      'deu' => 'de-DE',
      'ita' => 'it-IT',
      'jpn' => 'ja-JP',
      'kor' => 'ko-KR',
      'chi' => 'zh-CN',
      'zho' => 'zh-CN',
      'por' => 'pt-BR',
      'rus' => 'ru-RU',
      'ara' => 'ar-SA'
    }.freeze

    def initialize(client: Aws::TranscribeService::Client.new)
      @client = client
    end

    def submit(master_file:, language: nil)
      params = {
        transcription_job_name: job_name_for(master_file),
        media: { media_file_uri: media_file_uri(master_file) },
        output_bucket_name: Settings.transcription.aws.output_bucket,
        # AWS Transcribe generates the VTT cues itself (proper reading-speed
        # and line-length handling) — no need to build them from the raw
        # word-level output ourselves.
        subtitles: { formats: ['vtt'] }
      }
      language_code = LANGUAGE_CODE_MAP[language]
      language_code ? params[:language_code] = language_code : params[:identify_language] = true

      resp = @client.start_transcription_job(**params)
      resp.transcription_job.transcription_job_name
    end

    def fetch_status(provider_job_id)
      resp = @client.get_transcription_job(transcription_job_name: provider_job_id)
      status = case resp.transcription_job.transcription_job_status
               when 'COMPLETED' then :completed
               when 'FAILED' then :failed
               else :in_progress
               end

      StatusResult.new(status: status, raw_response: resp.to_h)
    end

    def fetch_transcript(provider_job_id)
      resp = @client.get_transcription_job(transcription_job_name: provider_job_id)
      job = resp.transcription_job
      transcript_uri = job.transcript&.transcript_file_uri
      raise TranscriptNotAvailable, "No transcript file available for #{provider_job_id}" unless transcript_uri

      transcript_json = JSON.parse(URI.parse(transcript_uri).open.read)
      vtt_uri = job.subtitles&.subtitle_file_uris&.first

      TranscriptResult.new(
        transcript_text: extract_transcript_text(transcript_json),
        caption_vtt: vtt_uri ? URI.parse(vtt_uri).open.read : nil,
        raw_response: transcript_json
      )
    end

    def cancel(provider_job_id)
      @client.delete_transcription_job(transcription_job_name: provider_job_id)
    end

    private

    def job_name_for(master_file)
      "avalon-#{master_file.id}-#{SecureRandom.hex(4)}"
    end

    def media_file_uri(master_file)
      uri = master_file.input_path
      unless uri.start_with?('s3://')
        raise UnsupportedMediaSource, "AWS Transcribe requires an S3 media source, got: #{uri}"
      end

      uri
    end

    def extract_transcript_text(transcript_json)
      transcript_json.dig('results', 'transcripts', 0, 'transcript').to_s
    end
  end
end
