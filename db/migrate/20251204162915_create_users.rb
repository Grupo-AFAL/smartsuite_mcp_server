class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :smartsuite_api_key, null: false
      t.string :smartsuite_account_id, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
