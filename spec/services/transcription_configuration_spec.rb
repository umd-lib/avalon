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

RSpec.describe TranscriptionConfiguration do
  describe '.validate!' do
    context 'when transcription is disabled' do
      before { allow(Settings.transcription).to receive(:enabled).and_return(false) }

      it 'does not raise, regardless of provider config' do
        expect { described_class.validate! }.not_to raise_error
      end
    end

    context 'when transcription is enabled' do
      before { allow(Settings.transcription).to receive(:enabled).and_return(true) }

      context 'with a valid aws_transcribe configuration' do
        before do
          allow(Settings.transcription).to receive(:default_provider).and_return('aws_transcribe')
          allow(Settings.transcription.aws).to receive(:output_bucket).and_return('some-bucket')
        end

        it 'does not raise' do
          expect { described_class.validate! }.not_to raise_error
        end
      end

      context 'with an unknown default_provider' do
        before { allow(Settings.transcription).to receive(:default_provider).and_return('not_a_real_provider') }

        it 'raises' do
          expect { described_class.validate! }.to raise_error(/Invalid Settings.transcription.default_provider/)
        end
      end

      context 'with aws_transcribe but no output_bucket configured' do
        before do
          allow(Settings.transcription).to receive(:default_provider).and_return('aws_transcribe')
          allow(Settings.transcription.aws).to receive(:output_bucket).and_return(nil)
        end

        it 'raises' do
          expect { described_class.validate! }.to raise_error(/output_bucket must be set/)
        end
      end
    end
  end
end
