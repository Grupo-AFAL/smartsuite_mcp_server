class CreateAPIKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :name
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :api_keys, :token, unique: true
  end
end
