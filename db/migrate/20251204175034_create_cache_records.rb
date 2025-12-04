class CreateCacheRecords < ActiveRecord::Migration[8.0]
  def change
    # Single table for all cached records using JSONB
    create_table :cache_records, id: false do |t|
      t.string :table_id, null: false
      t.string :record_id, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    add_index :cache_records, [:table_id, :record_id], unique: true
    add_index :cache_records, [:table_id, :expires_at]
    add_index :cache_records, :expires_at

    # GIN index for JSONB queries
    execute "CREATE INDEX idx_cache_records_data ON cache_records USING GIN (data)"

    # Cached solutions
    create_table :cache_solutions, id: false do |t|
      t.string :solution_id, primary_key: true
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    add_index :cache_solutions, :expires_at

    # Cached tables (applications)
    create_table :cache_tables, id: false do |t|
      t.string :table_id, primary_key: true
      t.string :solution_id
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    add_index :cache_tables, :solution_id
    add_index :cache_tables, :expires_at

    # Cached members
    create_table :cache_members, id: false do |t|
      t.string :member_id, primary_key: true
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    add_index :cache_members, :expires_at

    # Cached teams
    create_table :cache_teams, id: false do |t|
      t.string :team_id, primary_key: true
      t.jsonb :data, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    add_index :cache_teams, :expires_at

    # Table schema cache (stores structure for each SmartSuite table)
    create_table :cache_table_schemas, id: false do |t|
      t.string :table_id, primary_key: true
      t.jsonb :structure, null: false, default: {}
      t.datetime :cached_at, null: false
      t.datetime :expires_at, null: false
    end

    # Create fuzzy_match function for PostgreSQL
    execute <<-SQL
      CREATE OR REPLACE FUNCTION fuzzy_match(text_value TEXT, query TEXT)
      RETURNS BOOLEAN AS $$
      BEGIN
        IF text_value IS NULL OR query IS NULL THEN
          RETURN FALSE;
        END IF;
        -- Simple case-insensitive contains match
        -- For more sophisticated fuzzy matching, consider pg_trgm extension
        RETURN LOWER(text_value) LIKE '%' || LOWER(query) || '%';
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    SQL
  end
end
