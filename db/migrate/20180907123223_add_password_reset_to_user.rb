class AddPasswordResetToUser < ActiveRecord::Migration
  def change
    change_table :users do |t|
      t.datetime :reset_password_sent_at
      t.string :reset_password_token
    end
    add_index :users, :reset_password_token, unique: true 
  end
end
