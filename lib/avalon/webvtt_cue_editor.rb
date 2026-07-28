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

module Avalon
  # Parses a WebVTT file into its cues (identifier/timing preserved verbatim,
  # read-only) and lets an edited cue-text-only map be spliced back into the
  # original bytes. Deliberately narrow and separate from
  # Avalon::TranscriptParser, which is a one-way, lossy normalizer built for
  # Solr indexing (strips headers/identifiers/styling/NOTEs) and can't
  # round-trip a file. This class never touches timestamps, cue settings,
  # identifiers, or non-cue blocks (WEBVTT header, NOTE, STYLE, REGION) —
  # #apply substitutes only within a cue's recorded text_range, so everything
  # else in the file comes back byte-identical to the source.
  class WebvttCueEditor
    class InvalidCueText < StandardError; end

    Cue = Struct.new(:index, :identifier, :timing, :text, :text_range, keyword_init: true)

    TIMING_LINE = /\A\d{0,2}:?\d{2}:\d{2}\.\d{3} --> \d{0,2}:?\d{2}:\d{2}\.\d{3}.*\z/

    def initialize(raw_vtt)
      @raw = raw_vtt.to_s.gsub("\r\n", "\n")
      @cues = parse
    end

    attr_reader :cues

    # edits: Hash[Integer|String cue.index => String new_text]. Returns the
    # full new raw VTT string; apply({}) returns the original string
    # unchanged, byte for byte.
    def apply(edits)
      normalized_edits = edits.to_h { |index, text| [index.to_i, text] }

      unknown_index = normalized_edits.keys.find { |index| cues.none? { |cue| cue.index == index } }
      raise ArgumentError, "no cue at index #{unknown_index}" if unknown_index

      replacements = cues.filter_map do |cue|
        next unless normalized_edits.key?(cue.index)

        sanitized = sanitize(normalized_edits[cue.index])
        raise InvalidCueText, "cue #{cue.index} text cannot be blank" if sanitized.blank?
        next if sanitized == cue.text

        [cue.text_range, sanitized]
      end

      content = @raw.dup
      replacements.sort_by { |range, _text| -range.begin }.each do |range, text|
        content[range] = text
      end
      content
    end

    private

    def sanitize(text)
      text.to_s.gsub("\r\n", "\n").strip.gsub(/\n{2,}/, "\n")
    end

    def parse
      cues = []
      offset = 0
      index = 0

      @raw.split(/\n{2,}/).each do |raw_block|
        block_start = @raw.index(raw_block, offset)
        offset = block_start + raw_block.length

        # Only the file's final block can carry a trailing "\n" here (a
        # single newline at EOF doesn't match the \n{2,} split boundary) —
        # trim it so a last cue's #text doesn't end with a stray blank line.
        block = raw_block.sub(/\n+\z/, '')
        lines = block.split("\n")
        if lines.first =~ TIMING_LINE
          header_lines = 1
          identifier = nil
          timing = lines.first
        elsif lines[1] =~ TIMING_LINE
          header_lines = 2
          identifier = lines.first
          timing = lines[1]
        else
          next
        end

        header_length = lines.first(header_lines).sum { |line| line.length + 1 }
        text_start = block_start + header_length
        text_end = block_start + block.length
        text = block.split("\n", header_lines + 1).last.to_s

        cues << Cue.new(index: index, identifier: identifier, timing: timing, text: text, text_range: (text_start...text_end))
        index += 1
      end

      cues
    end
  end
end
