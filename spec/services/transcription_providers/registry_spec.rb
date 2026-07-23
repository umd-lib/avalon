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

RSpec.describe TranscriptionProviders::Registry do
  describe '.for' do
    it 'returns an AwsTranscribe adapter for aws_transcribe' do
      expect(described_class.for('aws_transcribe')).to be_a(TranscriptionProviders::AwsTranscribe)
    end

    it 'accepts a symbol provider identifier' do
      expect(described_class.for(:aws_transcribe)).to be_a(TranscriptionProviders::AwsTranscribe)
    end

    it 'raises UnknownProvider for an unrecognized provider' do
      expect { described_class.for('not_a_real_provider') }.to raise_error(TranscriptionProviders::UnknownProvider)
    end
  end
end
