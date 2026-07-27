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

class CreateTranscriptionVocabularies < ActiveRecord::Migration[8.0]
  def change
    create_table :transcription_vocabularies do |t|
      t.string :collection_id, null: false
      t.string :aws_vocabulary_name, null: false
      t.string :language, null: false
      t.text :phrases, null: false
      t.string :state, null: false, default: 'pending'
      t.text :error_message
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :transcription_vocabularies, :collection_id, unique: true
  end
end
