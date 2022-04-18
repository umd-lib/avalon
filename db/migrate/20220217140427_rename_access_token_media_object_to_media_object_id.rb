class RenameAccessTokenMediaObjectToMediaObjectId < ActiveRecord::Migration[5.2]
  def change
    rename_column :access_tokens, :media_object, :media_object_id
  end
end
