class RemoveBatchEntriesPayloadLimit < ActiveRecord::Migration
  def change
    change_column :batch_entries, :payload, :text, limit: nil
  end
end
