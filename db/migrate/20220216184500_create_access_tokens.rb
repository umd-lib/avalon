class CreateAccessTokens < ActiveRecord::Migration[5.2]
  def change
    create_table :access_tokens do |t|
      t.string :token
      t.string :media_object
      t.datetime :expiration
      t.boolean :allow_streaming
      t.boolean :allow_download
      t.string :description
      t.boolean :revoked
      t.boolean :expired
      t.references :user, foreign_key: true

      t.timestamps
    end
  end
end
