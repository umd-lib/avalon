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
require 'aws-sdk-s3'
require 'addressable/uri'
require 'avalon/webvtt_speaker_labeler'

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

    def initialize(client: Aws::TranscribeService::Client.new, s3_client: Aws::S3::Client.new)
      @client = client
      @s3_client = s3_client
    end

    def submit(master_file:, language: nil)
      collection = master_file.media_object&.collection
      params = {
        transcription_job_name: job_name_for(master_file),
        media: { media_file_uri: media_file_uri(master_file) },
        output_bucket_name: Settings.transcription.aws.output_bucket,
        # AWS Transcribe generates the VTT cues itself (proper reading-speed
        # and line-length handling) — no need to build them from the raw
        # word-level output ourselves.
        subtitles: { formats: ['vtt'] }
      }
      params[:output_key] = output_key_prefix if output_key_prefix
      language_code = LANGUAGE_CODE_MAP[language]
      settings = job_settings(collection, language_code)
      params[:settings] = settings if settings.present?
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

      transcript_json = JSON.parse(download_from_output_bucket(transcript_uri))
      vtt_uri = job.subtitles&.subtitle_file_uris&.first
      caption_vtt = vtt_uri ? download_from_output_bucket(vtt_uri) : nil
      # AWS Transcribe's generated subtitle files never include speaker
      # attribution, even with diarization on — only the JSON transcript
      # does (results.items[].speaker_label, per word). A no-op when
      # diarization wasn't requested or only one speaker was detected.
      caption_vtt = Avalon::WebvttSpeakerLabeler.apply(caption_vtt, transcript_json) if caption_vtt

      TranscriptResult.new(
        transcript_text: extract_transcript_text(transcript_json),
        caption_vtt: caption_vtt,
        raw_response: transcript_json
      )
    end

    def cancel(provider_job_id)
      @client.delete_transcription_job(transcription_job_name: provider_job_id)
    end

    private

    def job_name_for(master_file)
      "#{job_name_prefix}-#{master_file.id}-#{SecureRandom.hex(4)}"
    end

    def job_name_prefix
      AwsNaming.job_name_prefix
    end

    # When output_bucket is shared with other content (e.g. reused from
    # SupplementalFile's own S3 storage), output_prefix keeps Transcribe's
    # job output (transcript JSON + VTT) segmented under its own "directory"
    # instead of landing at the bucket root. A prefix ending in "/" tells
    # Transcribe to auto-name the output file under it; nil/blank leaves the
    # bucket root behavior unchanged.
    def output_key_prefix
      prefix = Settings.transcription.aws.output_prefix
      return nil if prefix.blank?

      "#{prefix.chomp('/')}/"
    end

    # Builds the StartTranscriptionJob "settings" hash — speaker diarization
    # and/or a custom vocabulary — from whichever is in effect for the
    # master file's owning collection, falling back to the global Settings
    # directly for diarization when there's no collection at all (e.g. an
    # orphaned record). Admin::Collection's own diarization readers
    # (diarization_enabled?/diarization_max_speakers) already fall back to
    # Settings.transcription.aws.* when the collection hasn't set its own
    # value, so this only needs the extra no-collection branch on top of
    # that. Custom vocabulary has no such global fallback — it's Avalon-managed
    # per collection only (TranscriptionVocabulary), so an orphaned record
    # simply gets no vocabulary.
    def job_settings(collection, language_code)
      settings = {}

      diarization_enabled = collection ? collection.diarization_enabled? : Settings.transcription.aws.diarization&.enabled
      if diarization_enabled
        settings[:show_speaker_labels] = true
        settings[:max_speaker_labels] = collection ? collection.diarization_max_speakers : Settings.transcription.aws.diarization&.max_speakers
      end

      # A vocabulary is only applied once it's actually READY (not
      # pending/failed) and its language matches this job's resolved
      # language — AWS requires an explicit LanguageCode for a vocabulary,
      # so a job falling back to automatic language identification (no
      # language_code) never gets one.
      if collection && language_code
        vocabulary = TranscriptionVocabulary.find_by(collection_id: collection.id, state: 'ready')
        if vocabulary && LANGUAGE_CODE_MAP[vocabulary.language] == language_code
          settings[:vocabulary_name] = vocabulary.aws_vocabulary_name
        end
      end

      settings
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

    # AWS Transcribe writes job output (transcript JSON, subtitle files) to
    # our own S3 bucket, not an AWS-managed one, so the URIs it returns are
    # plain https://s3.<region>.amazonaws.com/<bucket>/<key> links — NOT
    # pre-signed. Fetching them with a raw unauthenticated HTTP GET would
    # 403 against any bucket that isn't publicly readable, so we resolve the
    # key from the URI and fetch it via our own S3 credentials instead.
    def download_from_output_bucket(https_uri)
      bucket = Settings.transcription.aws.output_bucket
      path = Addressable::URI.parse(https_uri).path
      key = path.sub(%r{\A/#{Regexp.escape(bucket)}/}, '')

      @s3_client.get_object(bucket: bucket, key: key).body.read
    end
  end
end
