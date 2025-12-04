class CreateCacheMetadata < ActiveRecord::Migration[8.0]
  def change
    create_table :cache_metadata, id: false do |t|
      t.string :table_id, primary_key: true
      t.string :pg_table_name, null: false
      t.jsonb :schema, default: {}
      t.integer :record_count, default: 0
      t.integer :ttl_seconds, default: 14400
      t.datetime :cached_at
      t.datetime :expires_at
    end
  end
end
