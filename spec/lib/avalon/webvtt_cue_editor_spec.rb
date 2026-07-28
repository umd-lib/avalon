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
require 'avalon/webvtt_cue_editor'

describe Avalon::WebvttCueEditor do
  describe 'parsing spec/fixtures/captions.vtt' do
    let(:raw) { Rails.root.join('spec', 'fixtures', 'captions.vtt').read }
    subject { described_class.new(raw) }

    it 'parses the single cue' do
      expect(subject.cues.size).to eq(1)
      cue = subject.cues.first
      expect(cue.index).to eq(0)
      expect(cue.identifier).to eq('1')
      expect(cue.timing).to eq('00:00:03.500 --> 00:00:05.000')
      expect(cue.text).to eq('Example captions')
    end
  end

  describe 'parsing spec/fixtures/captions.srt' do
    let(:raw) { Rails.root.join('spec', 'fixtures', 'captions.srt').read }
    subject { described_class.new(raw) }

    it 'parses the single cue, comma-separated timestamps and all' do
      expect(subject.cues.size).to eq(1)
      cue = subject.cues.first
      expect(cue.identifier).to eq('1')
      expect(cue.timing).to eq('00:00:03,498 --> 00:00:05,000')
      expect(cue.text).to eq('- Example Captions')
    end

    it 'edits cue text without reformatting the timestamps to VTT-style periods' do
      result = subject.apply({ 0 => 'Corrected captions' })

      expect(result).to include('00:00:03,498 --> 00:00:05,000')
      expect(result).to include('Corrected captions')
      expect(result).not_to include('.498')
      expect(result).not_to include('.000')
    end
  end

  describe 'parsing spec/fixtures/chunk_test.vtt' do
    let(:raw) { Rails.root.join('spec', 'fixtures', 'chunk_test.vtt').read }
    subject { described_class.new(raw) }

    it 'finds exactly the 10 cues, skipping STYLE/NOTE blocks' do
      expect(subject.cues.size).to eq(10)
    end

    it 'preserves settings on a timing line and parses cue text with inline markup' do
      cue = subject.cues.first
      expect(cue.identifier).to eq('1')
      expect(cue.timing).to eq('00:00:01.200 --> 00:00:21.000 position:50%,line-left align:center size: 40%')
      expect(cue.text).to eq('[<i>music</i>]')
    end

    it 'preserves a non-numeric identifier and multi-line text' do
      cue = subject.cues[1]
      expect(cue.identifier).to eq('2 - Speech Begins')
      expect(cue.text).to eq("Just before lunch one day, a puppet show \nwas put on at school.")
    end

    it 'parses the final cue correctly (no trailing newline leaking into text)' do
      cue = subject.cues.last
      expect(cue.identifier).to eq('10')
      expect(cue.text).to eq("Even though this made the children laugh, \nno one thought that was a fair thing to do.")
    end
  end

  describe '#apply' do
    let(:raw) { Rails.root.join('spec', 'fixtures', 'chunk_test.vtt').read }
    subject { described_class.new(raw) }

    it 'returns the original content unchanged when there are no edits' do
      expect(subject.apply({})).to eq(raw.gsub("\r\n", "\n"))
    end

    it 'changes only the targeted cue, leaving everything else byte-identical' do
      result = subject.apply({ 2 => 'It was called "Mr. Bungle Goes to Lunch".' })

      expect(result).to include('It was called "Mr. Bungle Goes to Lunch".')
      expect(result).not_to include('Mister Bungle Goes to Lunch')

      reparsed = described_class.new(result)
      expect(reparsed.cues.size).to eq(10)
      reparsed.cues.each_with_index do |cue, i|
        next if i == 2

        expect(cue.text).to eq(subject.cues[i].text)
        expect(cue.timing).to eq(subject.cues[i].timing)
        expect(cue.identifier).to eq(subject.cues[i].identifier)
      end
    end

    it 'is a no-op (returns the original string) when the edit matches the existing text' do
      expect(subject.apply({ 0 => subject.cues[0].text })).to eq(raw.gsub("\r\n", "\n"))
    end

    it 'accepts string keys, as form params would submit' do
      result = subject.apply({ '3' => 'It was fun to watch!' })
      expect(described_class.new(result).cues[3].text).to eq('It was fun to watch!')
    end

    it 'strips a leading/trailing blank line, as a textarea submission would include' do
      result = subject.apply({ 3 => "\nIt was fun to watch.\n\n" })
      expect(described_class.new(result).cues[3].text).to eq('It was fun to watch.')
    end

    it 'collapses an internal blank line so it cannot be mistaken for a cue boundary' do
      result = subject.apply({ 3 => "Line one\n\nLine two" })
      reparsed = described_class.new(result)

      expect(reparsed.cues.size).to eq(10)
      expect(reparsed.cues[3].text).to eq("Line one\nLine two")
    end

    it 'raises InvalidCueText when the sanitized replacement is blank' do
      expect { subject.apply({ 0 => "\n\n  " }) }.to raise_error(Avalon::WebvttCueEditor::InvalidCueText)
    end

    it 'raises ArgumentError for an edit targeting an unknown cue index' do
      expect { subject.apply({ 99 => 'no such cue' }) }.to raise_error(ArgumentError)
    end

    it 'applies edits to multiple cues in the same call' do
      result = subject.apply({ 0 => 'first fixed', 9 => 'last fixed' })
      reparsed = described_class.new(result)

      expect(reparsed.cues.first.text).to eq('first fixed')
      expect(reparsed.cues.last.text).to eq('last fixed')
      expect(reparsed.cues.size).to eq(10)
    end
  end
end
