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

RSpec.describe TranscriptionVocabulary, type: :model do
  let(:collection) { FactoryBot.create(:collection) }

  def build_vocabulary(**attrs)
    TranscriptionVocabulary.new({ collection_id: collection.id, phrases: "Archelon\nfoobar" }.merge(attrs))
  end

  describe 'validations' do
    it 'is valid with a collection_id and phrases' do
      expect(build_vocabulary).to be_valid
    end

    it 'requires collection_id' do
      vocabulary = build_vocabulary(collection_id: nil)
      expect(vocabulary).not_to be_valid
      expect(vocabulary.errors[:collection_id]).to include('field is required.')
    end

    it 'requires the collection to exist' do
      vocabulary = build_vocabulary(collection_id: 'nonexistent')
      expect(vocabulary).not_to be_valid
      expect(vocabulary.errors[:collection_id]).to include('not found')
    end

    it 'requires phrases' do
      vocabulary = build_vocabulary(phrases: '')
      expect(vocabulary).not_to be_valid
    end

    it 'requires a language AWS Transcribe custom vocabularies support' do
      vocabulary = build_vocabulary(language: 'xyz')
      expect(vocabulary).not_to be_valid
    end

    it 'defaults state to pending' do
      expect(build_vocabulary.state).to eq('pending')
    end

    it 'enforces one vocabulary per collection at the database level' do
      build_vocabulary.save!
      # aws_vocabulary_name and language are normally derived/defaulted by
      # before_validation callbacks, which save!(validate: false) skips along
      # with the uniqueness check this test is targeting — set them
      # explicitly so only the DB constraint is exercised.
      duplicate = build_vocabulary(aws_vocabulary_name: "avalon-vocab-#{collection.id}", language: 'eng')

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#set_aws_vocabulary_name' do
    it 'derives a deterministic name from the job_name_prefix and collection id on create' do
      vocabulary = build_vocabulary.tap(&:save!)
      expect(vocabulary.aws_vocabulary_name).to eq("avalon-vocab-#{collection.id}")
    end

    it 'sanitizes characters AWS vocabulary names disallow' do
      vocabulary = TranscriptionVocabulary.new(collection_id: 'abc:123', phrases: 'foo')
      vocabulary.valid?
      expect(vocabulary.aws_vocabulary_name).to eq('avalon-vocab-abc-123')
    end

    it 'does not change the name on update' do
      vocabulary = build_vocabulary.tap(&:save!)
      original_name = vocabulary.aws_vocabulary_name

      vocabulary.update!(phrases: 'updated phrase list')

      expect(vocabulary.aws_vocabulary_name).to eq(original_name)
    end
  end

  describe '#phrase_list' do
    it 'splits phrases on newlines, stripping whitespace and blank lines' do
      vocabulary = build_vocabulary(phrases: " Archelon \n\n foobar\r\n  \nbaz ")
      expect(vocabulary.phrase_list).to eq(['Archelon', 'foobar', 'baz'])
    end
  end

  describe '#collection' do
    it 'resolves the owning Admin::Collection' do
      vocabulary = build_vocabulary.tap(&:save!)
      expect(vocabulary.collection).to eq(collection)
    end
  end
end
