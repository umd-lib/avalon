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

require 'avalon/webvtt_cue_editor'

module Avalon
  # AWS Transcribe's own generated subtitle (VTT/SRT) files never include
  # speaker attribution, even with diarization enabled — that data only
  # exists in the JSON transcript (results.items[].speaker_label,
  # per-word). This adds a "[Speaker N]" prefix to each VTT cue by matching
  # the cue's time range against the JSON's word-level speaker data, rather
  # than rebuilding cues from scratch — AWS's own cue timing/line-splitting
  # is kept as-is; only each cue's text gets a prefix, via the same
  # surgical-substitution Avalon::WebvttCueEditor#apply already uses for
  # the review-workflow cue editor.
  #
  # A cue that straddles a speaker change is labeled with whichever speaker
  # is talking at the cue's start — a known, accepted imprecision (see
  # umd_docs/TranscriptionAwsSetup.md), not a full re-timing.
  class WebvttSpeakerLabeler
    def self.apply(vtt_content, transcript_json)
      new(vtt_content, transcript_json).labeled_vtt
    end

    def initialize(vtt_content, transcript_json)
      @vtt_content = vtt_content
      @transcript_json = transcript_json
    end

    def labeled_vtt
      return @vtt_content if speaker_count <= 1 || timed_items.empty?

      editor = Avalon::WebvttCueEditor.new(@vtt_content)
      edits = {}
      item_index = 0

      editor.cues.each do |cue|
        start_sec, end_sec = parse_timing(cue.timing)
        next if start_sec.nil?

        item_index += 1 while item_index < timed_items.length && timed_items[item_index][1] <= start_sec
        speaker = speaker_at(item_index, end_sec)
        edits[cue.index] = "[#{speaker_display_name(speaker)}] #{cue.text}" if speaker
      end

      edits.empty? ? @vtt_content : editor.apply(edits)
    end

    private

    # AWS's own word items are already chronological, but sorting
    # defensively costs little relative to the size of a full transcript
    # and removes any dependency on that ordering being guaranteed.
    def timed_items
      @timed_items ||= Array(@transcript_json.dig('results', 'items')).filter_map { |item|
        next unless item['start_time'] && item['end_time'] && item['speaker_label']

        [item['start_time'].to_f, item['end_time'].to_f, item['speaker_label']]
      }.sort_by { |(start, _end, _speaker)| start }
    end

    def speaker_count
      @transcript_json.dig('results', 'speaker_labels', 'speakers').to_i
    end

    # item_index has already been advanced past every item whose end is at
    # or before the cue's start; the item there (if any) is the first
    # chronological candidate — real overlap still needs its start to fall
    # before the cue's own end.
    def speaker_at(item_index, cue_end_sec)
      return nil if item_index >= timed_items.length

      start_sec, _end_sec, speaker = timed_items[item_index]
      speaker if start_sec < cue_end_sec
    end

    def speaker_display_name(speaker_label)
      match = speaker_label.match(/(\d+)\z/)
      match ? "Speaker #{match[1].to_i + 1}" : speaker_label
    end

    def parse_timing(timing)
      start_str, rest = timing.to_s.split(' --> ', 2)
      return [nil, nil] unless rest

      end_str = rest.split(' ', 2).first
      [parse_time(start_str), parse_time(end_str)]
    end

    def parse_time(str)
      match = str.to_s.match(/\A(\d+):(\d{2}):(\d{2})[.,](\d{3})\z/)
      return nil unless match

      hours, minutes, seconds, millis = match.captures.map(&:to_i)
      (hours * 3600) + (minutes * 60) + seconds + (millis / 1000.0)
    end
  end
end
