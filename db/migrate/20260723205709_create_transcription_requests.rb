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

class CreateTranscriptionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :transcription_requests do |t|
      t.string :master_file_id, null: false
      t.string :media_object_id
      t.string :status, null: false, default: 'pending'
      t.string :provider, null: false
      t.string :provider_job_id
      t.string :language
      t.text :raw_response
      t.text :transcript_text
      t.text :error_message
      t.datetime :submitted_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :transcription_requests, :master_file_id
    add_index :transcription_requests, :media_object_id
    add_index :transcription_requests, :provider_job_id

    # Prevent more than one active (non-terminal) request per master file.
    add_index :transcription_requests, :master_file_id,
              unique: true,
              where: "status NOT IN ('completed', 'failed', 'cancelled')",
              name: 'index_transcription_requests_on_active_master_file_id'
  end
end