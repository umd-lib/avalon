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
require 'avalon/webvtt_speaker_labeler'

describe Avalon::WebvttSpeakerLabeler do
  def item(content, start_time, end_time, speaker)
    { 'type' => 'pronunciation', 'start_time' => start_time.to_s, 'end_time' => end_time.to_s,
      'speaker_label' => speaker, 'alternatives' => [{ 'content' => content }] }
  end

  describe '.apply' do
    let(:vtt) do
      "WEBVTT\n\n" \
        "00:00:00.000 --> 00:00:01.000\nHello world.\n\n" \
        "00:00:01.000 --> 00:00:02.000\nHi there.\n"
    end

    context 'with two speakers' do
      let(:transcript_json) do
        {
          'results' => {
            'speaker_labels' => { 'speakers' => 2 },
            'items' => [
              item('Hello', '0.0', '0.5', 'spk_0'),
              item('world.', '0.5', '1.0', 'spk_0'),
              item('Hi', '1.0', '1.5', 'spk_1'),
              item('there.', '1.5', '2.0', 'spk_1')
            ]
          }
        }
      end

      it 'prefixes each cue with the speaker active at its start' do
        result = described_class.apply(vtt, transcript_json)
        cues = Avalon::WebvttCueEditor.new(result).cues

        expect(cues[0].text).to eq('[Speaker 1] Hello world.')
        expect(cues[1].text).to eq('[Speaker 2] Hi there.')
      end

      it 'leaves cue timing and everything else byte-identical' do
        result = described_class.apply(vtt, transcript_json)
        cues = Avalon::WebvttCueEditor.new(result).cues

        expect(cues[0].timing).to eq('00:00:00.000 --> 00:00:01.000')
        expect(cues[1].timing).to eq('00:00:01.000 --> 00:00:02.000')
      end

      it 'preserves multi-line cue text after the prefix' do
        multiline_vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\nworld.\n"
        result = described_class.apply(multiline_vtt, transcript_json)
        cue = Avalon::WebvttCueEditor.new(result).cues.first

        expect(cue.text).to eq("[Speaker 1] Hello\nworld.")
      end
    end

    context 'with only one speaker detected' do
      let(:transcript_json) do
        {
          'results' => {
            'speaker_labels' => { 'speakers' => 1 },
            'items' => [item('Hello', '0.0', '0.5', 'spk_0'), item('world.', '0.5', '1.0', 'spk_0')]
          }
        }
      end

      it 'returns the VTT unchanged — labeling one speaker is just noise' do
        expect(described_class.apply(vtt, transcript_json)).to eq(vtt)
      end
    end

    context 'when diarization was not enabled for the job (no speaker data at all)' do
      let(:transcript_json) { { 'results' => { 'transcripts' => [{ 'transcript' => 'Hello world. Hi there.' }] } } }

      it 'returns the VTT unchanged' do
        expect(described_class.apply(vtt, transcript_json)).to eq(vtt)
      end
    end

    context 'when a cue has no overlapping word items (e.g. a silence/music-only cue)' do
      let(:transcript_json) do
        {
          'results' => {
            'speaker_labels' => { 'speakers' => 2 },
            'items' => [item('Hi', '5.0', '5.5', 'spk_1'), item('there.', '5.5', '6.0', 'spk_1')]
          }
        }
      end

      it 'leaves that cue unlabeled instead of guessing' do
        result = described_class.apply(vtt, transcript_json)
        cues = Avalon::WebvttCueEditor.new(result).cues

        expect(cues[0].text).to eq('Hello world.')
        expect(cues[1].text).to eq('Hi there.')
      end
    end
  end
end
