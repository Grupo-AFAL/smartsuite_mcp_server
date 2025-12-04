class CreateApiCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :api_calls do |t|
      t.references :user, null: false, foreign_key: true
      t.string :tool_name, null: false
      t.string :solution_id
      t.string :table_id
      t.boolean :cache_hit, default: false
      t.integer :duration_ms

      t.datetime :created_at, null: false
    end

    add_index :api_calls, [ :user_id, :created_at ]
    add_index :api_calls, [ :user_id, :tool_name ]
  end
end
