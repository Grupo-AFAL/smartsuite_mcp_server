class CreateCacheViewsAndDeletedRecords < ActiveRecord::Migration[8.0]
  def change
    # Cached views (reports) - was previously created on-demand in postgres_layer.rb
    create_table :cache_views, id: false do |t|
      t.string :id, primary_key: true
      t.string :solution_id
      t.string :application_id
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    add_index :cache_views, :application_id, name: "idx_cache_views_application"
    add_index :cache_views, :solution_id, name: "idx_cache_views_solution"
    add_index :cache_views, :expires_at, name: "idx_cache_views_expires"

    # Cached deleted records - was previously created on-demand in postgres_layer.rb
    create_table :cache_deleted_records, id: false do |t|
      t.string :solution_id, primary_key: true
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end
  end
end
