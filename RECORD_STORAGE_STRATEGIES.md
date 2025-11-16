# Record Storage Strategies: Refined Design

## Overview

This document refines the record caching strategy based on key requirements:
1. ✅ Raw SQLite (no ORM)
2. ✅ Flexible multi-criteria querying
3. ✅ Proper SQL types and indexes for performance
4. ✅ Easy DB GUI exploration
5. ✅ Fetch ALL records (no SmartSuite filter translation needed)

We'll compare two approaches:
- **Approach A**: Configurable Attribute Column Mapping
- **Approach B**: Dynamic Table Creation (One SQL table per SmartSuite table) ⭐

---

## Context: Aggressive Fetch Strategy

Since we're adopting an **aggressive fetch strategy** (fetch all records from a table):

```ruby
# Fetch ALL records from a SmartSuite table, no filters
def cache_table_records(table_id)
  # Fetch all records in batches (using 1000 to minimize API calls)
  offset = 0
  limit = 1000

  loop do
    records = api_request(
      :post,
      "applications/#{table_id}/records/list/",
      query_params: {limit: limit, offset: offset}
    )

    break if records.empty?

    # Store ALL records in cache
    cache_records(table_id, records)

    offset += limit
  end
end
```

**Implications:**
- No need to translate SmartSuite filters to SQL (we have all data locally)
- Filtering happens entirely in SQL against cache
- One-time fetch cost, unlimited local queries
- Must handle schema evolution (field additions/changes)

---

## Approach A: Configurable Attribute Column Mapping

### Concept

Create a fixed schema with **generic typed attribute columns**, then map them to specific fields per table via configuration.

### Schema Design

```sql
CREATE TABLE records (
  id TEXT PRIMARY KEY,
  table_id TEXT NOT NULL,

  -- Generic attribute columns (typed)
  attr_text_1 TEXT,
  attr_text_2 TEXT,
  attr_text_3 TEXT,
  attr_text_4 TEXT,
  attr_text_5 TEXT,

  attr_number_1 REAL,
  attr_number_2 REAL,
  attr_number_3 REAL,

  attr_date_1 INTEGER,
  attr_date_2 INTEGER,
  attr_date_3 INTEGER,

  attr_select_1 TEXT,
  attr_select_2 TEXT,

  attr_array_1 TEXT,  -- JSON
  attr_array_2 TEXT,  -- JSON

  -- Full data as JSON fallback
  data TEXT NOT NULL,

  -- Metadata
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,

  FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
);

CREATE INDEX idx_records_table ON records(table_id);
CREATE INDEX idx_records_attr_text_1 ON records(attr_text_1);
CREATE INDEX idx_records_attr_text_2 ON records(attr_text_2);
CREATE INDEX idx_records_attr_number_1 ON records(attr_number_1);
CREATE INDEX idx_records_attr_date_1 ON records(attr_date_1);
CREATE INDEX idx_records_attr_select_1 ON records(attr_select_1);
-- etc...
```

### Configuration Mapping

```ruby
# lib/smartsuite/cache_config.rb

class CacheConfig
  # Map attribute columns to SmartSuite fields per table
  ATTRIBUTE_MAPPINGS = {
    'table_abc123' => {  # Projects table
      attr_text_1: 'project_name',
      attr_text_2: 'customer_name',
      attr_select_1: 'status',
      attr_number_1: 'revenue',
      attr_date_1: 'due_date',
      attr_array_1: 'assigned_to'
    },
    'table_def456' => {  # Tasks table
      attr_text_1: 'task_title',
      attr_select_1: 'priority',
      attr_select_2: 'status',
      attr_date_1: 'due_date',
      attr_array_1: 'assigned_to'
    }
  }

  def self.get_mapping(table_id)
    ATTRIBUTE_MAPPINGS[table_id] || {}
  end

  def self.get_field_to_attr_map(table_id)
    # Reverse mapping: field_slug => attr_column
    get_mapping(table_id).invert
  end
end
```

### Storage Implementation

```ruby
def cache_record_with_mapping(table_id, record)
  mapping = CacheConfig.get_field_to_attr_map(table_id)

  # Build values for attribute columns
  attr_values = {}

  record.each do |field_slug, value|
    attr_column = mapping[field_slug]
    next unless attr_column  # Skip unmapped fields

    # Store in appropriate attribute column
    attr_values[attr_column] = serialize_value(value, attr_column)
  end

  # Insert record
  @db.execute(
    "INSERT OR REPLACE INTO records
     (id, table_id, attr_text_1, attr_text_2, attr_select_1, attr_number_1, attr_date_1, attr_array_1, data, cached_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    record['id'],
    table_id,
    attr_values[:attr_text_1],
    attr_values[:attr_text_2],
    attr_values[:attr_select_1],
    attr_values[:attr_number_1],
    attr_values[:attr_date_1],
    attr_values[:attr_array_1]&.to_json,
    record.to_json,
    Time.now.to_i,
    Time.now.to_i + 300
  )
end
```

### Querying Implementation

```ruby
# Flexible query builder
def query_records(table_id, criteria = {})
  mapping = CacheConfig.get_field_to_attr_map(table_id)

  where_clauses = ["table_id = ?"]
  params = [table_id]

  criteria.each do |field_slug, condition|
    attr_column = mapping[field_slug]

    if attr_column
      # Mapped field - use indexed column
      clause, field_params = build_condition(attr_column, condition)
      where_clauses << clause
      params.concat(field_params)
    else
      # Unmapped field - use JSON extraction
      clause, field_params = build_json_condition(field_slug, condition)
      where_clauses << clause
      params.concat(field_params)
    end
  end

  sql = "SELECT id, data FROM records WHERE #{where_clauses.join(' AND ')}"
  @db.execute(sql, params).map { |row| JSON.parse(row['data']) }
end

# Usage examples:
query_records('table_abc123', {
  'project_name' => {contains: 'Alpha'},      # Uses attr_text_1 (fast)
  'status' => {eq: 'Active'},                 # Uses attr_select_1 (fast)
  'revenue' => {gte: 50000},                  # Uses attr_number_1 (fast)
  'custom_field' => {eq: 'value'}             # Uses JSON (slower)
})
```

### Auto-Configuration Strategy

Instead of manual configuration, **automatically map most important fields**:

```ruby
def auto_generate_mapping(table_id)
  table_structure = get_table_structure(table_id)
  fields = table_structure['structure']

  mapping = {}
  attr_text_idx = 1
  attr_number_idx = 1
  attr_date_idx = 1
  attr_select_idx = 1
  attr_array_idx = 1

  # Priority 1: Primary field
  primary_field = fields.find { |f| f['primary'] }
  if primary_field && primary_field['field_type'].include?('text')
    mapping["attr_text_#{attr_text_idx}".to_sym] = primary_field['slug']
    attr_text_idx += 1
  end

  # Priority 2: Status/single-select fields
  fields.select { |f| f['field_type'] =~ /status|singleselect/ }.first(2).each do |field|
    mapping["attr_select_#{attr_select_idx}".to_sym] = field['slug']
    attr_select_idx += 1
  end

  # Priority 3: Date fields
  fields.select { |f| f['field_type'] =~ /date|duedate/ }.first(3).each do |field|
    mapping["attr_date_#{attr_date_idx}".to_sym] = field['slug']
    attr_date_idx += 1
  end

  # Priority 4: Assigned to / user fields
  assigned_field = fields.find { |f| f['field_type'] == 'assignedtofield' }
  if assigned_field
    mapping["attr_array_#{attr_array_idx}".to_sym] = assigned_field['slug']
    attr_array_idx += 1
  end

  # Priority 5: Numeric fields (revenue, amount, etc.)
  fields.select { |f| f['field_type'] =~ /number|currency|percent/ }.first(3).each do |field|
    mapping["attr_number_#{attr_number_idx}".to_sym] = field['slug']
    attr_number_idx += 1
  end

  # Priority 6: Other text fields
  fields.select { |f| f['field_type'] =~ /text|email|phone/ && !f['primary'] }.first(3).each do |field|
    if attr_text_idx <= 5
      mapping["attr_text_#{attr_text_idx}".to_sym] = field['slug']
      attr_text_idx += 1
    end
  end

  mapping
end

# Store mapping in database
def store_table_mapping(table_id, mapping)
  @db.execute(
    "INSERT OR REPLACE INTO table_attribute_mappings (table_id, mapping, created_at)
     VALUES (?, ?, ?)",
    table_id,
    mapping.to_json,
    Time.now.to_i
  )
end
```

### Pros:
- ✅ Fixed schema (no dynamic CREATE TABLE)
- ✅ Proper SQL types for common fields
- ✅ Indexed columns for fast queries
- ✅ Automatic mapping based on field priorities
- ✅ Fallback to JSON for unmapped fields
- ✅ Can query across different tables (same schema)

### Cons:
- ❌ **Limited attribute columns** (fixed number, e.g., 5 text, 3 number)
- ❌ **Configuration complexity** (which fields get mapped?)
- ❌ **Wasted columns** (not all tables use all attributes)
- ❌ **Collision risk** (what if table has 10 text fields but only 5 slots?)
- ❌ **Not intuitive in DB GUI** (attr_text_1 instead of "project_name")
- ❌ **Manual mapping maintenance** (when new important fields added)

---

## Approach B: Dynamic Table Creation ⭐ RECOMMENDED

### Concept

Create **one SQL table per SmartSuite table**, with columns matching the actual field structure. This mirrors SmartSuite's database structure in the cache.

### Schema Design

```sql
-- Metadata table to track dynamically-created tables
CREATE TABLE cached_table_schemas (
  table_id TEXT PRIMARY KEY,
  sql_table_name TEXT NOT NULL UNIQUE,
  structure TEXT NOT NULL,  -- JSON of SmartSuite table structure
  field_mapping TEXT NOT NULL,  -- JSON: {field_slug => sql_column_name}
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Example: For SmartSuite table "Projects" (id: abc123)
CREATE TABLE cache_records_abc123 (
  id TEXT PRIMARY KEY,

  -- SmartSuite fields mapped to proper SQL types
  project_name TEXT,
  customer_name TEXT,
  status TEXT,
  priority TEXT,
  revenue REAL,
  budget REAL,
  start_date INTEGER,
  due_date INTEGER,
  assigned_to TEXT,  -- JSON array
  tags TEXT,         -- JSON array
  description TEXT,

  -- Metadata
  created_on INTEGER,
  updated_on INTEGER,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX idx_cache_records_abc123_status ON cache_records_abc123(status);
CREATE INDEX idx_cache_records_abc123_due_date ON cache_records_abc123(due_date);
CREATE INDEX idx_cache_records_abc123_priority ON cache_records_abc123(priority);

-- Example: For SmartSuite table "Customers" (id: def456)
CREATE TABLE cache_records_def456 (
  id TEXT PRIMARY KEY,

  customer_name TEXT,
  industry TEXT,
  annual_revenue REAL,
  account_status TEXT,
  contract_start_date INTEGER,
  primary_contact TEXT,  -- JSON object

  created_on INTEGER,
  updated_on INTEGER,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX idx_cache_records_def456_industry ON cache_records_def456(industry);
CREATE INDEX idx_cache_records_def456_account_status ON cache_records_def456(account_status);
```

### Field Type Mapping

```ruby
# Map SmartSuite field types to SQLite types
FIELD_TYPE_MAP = {
  'textfield' => 'TEXT',
  'textarea' => 'TEXT',
  'emailfield' => 'TEXT',
  'phonefield' => 'TEXT',
  'addressfield' => 'TEXT',
  'linkfield' => 'TEXT',
  'fullnamefield' => 'TEXT',

  'numberfield' => 'REAL',
  'currencyfield' => 'REAL',
  'percentfield' => 'REAL',
  'ratingfield' => 'REAL',
  'durationfield' => 'REAL',

  'datefield' => 'INTEGER',
  'duedatefield' => 'INTEGER',
  'daterangefield' => 'TEXT',  # JSON: {from_date, to_date}
  'firstcreated' => 'INTEGER',
  'lastupdated' => 'INTEGER',

  'yesnofield' => 'INTEGER',  # 0 or 1

  'singleselectfield' => 'TEXT',
  'statusfield' => 'TEXT',

  'multipleselectfield' => 'TEXT',  # JSON array
  'assignedtofield' => 'TEXT',      # JSON array
  'linkedrecordfield' => 'TEXT',    # JSON array
  'filesfield' => 'TEXT',           # JSON array
  'imagesfield' => 'TEXT',          # JSON array

  'formulafield' => 'TEXT',  # Dynamic based on formula output
  'lookupfield' => 'TEXT',   # Dynamic based on linked field
  'countfield' => 'INTEGER',
  'subuserfield' => 'TEXT',
}

def map_field_type(field_type)
  FIELD_TYPE_MAP[field_type.downcase] || 'TEXT'
end
```

### Dynamic Table Creation Implementation

```ruby
def create_cache_table_for_smartsuite_table(table_id, structure)
  # Generate SQL-safe table name
  sql_table_name = "cache_records_#{sanitize_table_name(table_id)}"

  # Build column definitions
  columns = ["id TEXT PRIMARY KEY"]
  field_mapping = {}

  structure['structure'].each do |field|
    field_slug = field['slug']
    sql_column_name = sanitize_column_name(field_slug)
    sql_type = map_field_type(field['field_type'])

    columns << "#{sql_column_name} #{sql_type}"
    field_mapping[field_slug] = sql_column_name
  end

  # Add metadata columns
  columns << "created_on INTEGER"
  columns << "updated_on INTEGER"
  columns << "cached_at INTEGER NOT NULL"
  columns << "expires_at INTEGER NOT NULL"

  # Create table
  @db.execute("CREATE TABLE IF NOT EXISTS #{sql_table_name} (#{columns.join(', ')})")

  # Create indexes on commonly-filtered fields
  create_indexes_for_table(sql_table_name, structure, field_mapping)

  # Store schema metadata
  @db.execute(
    "INSERT OR REPLACE INTO cached_table_schemas
     (table_id, sql_table_name, structure, field_mapping, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)",
    table_id,
    sql_table_name,
    structure.to_json,
    field_mapping.to_json,
    Time.now.to_i,
    Time.now.to_i
  )

  sql_table_name
end

def create_indexes_for_table(sql_table_name, structure, field_mapping)
  # Create indexes on common query fields
  structure['structure'].each do |field|
    field_slug = field['slug']
    field_type = field['field_type']
    sql_column = field_mapping[field_slug]

    # Index these field types
    should_index = field_type =~ /status|select|date|duedate|assigned/i ||
                   field['primary'] == true

    if should_index
      index_name = "idx_#{sql_table_name}_#{sql_column}"
      @db.execute("CREATE INDEX IF NOT EXISTS #{index_name} ON #{sql_table_name}(#{sql_column})")
    end
  end
end

def sanitize_table_name(table_id)
  table_id.gsub(/[^a-zA-Z0-9_]/, '_')
end

def sanitize_column_name(field_slug)
  # Ensure SQL-safe column name
  field_slug.gsub(/[^a-zA-Z0-9_]/, '_').downcase
end
```

### Storage Implementation

```ruby
def cache_records_dynamic(table_id, records)
  # Get or create cache table
  schema = get_cached_table_schema(table_id)

  unless schema
    # First time caching this table - create it
    table_structure = get_table_structure(table_id)
    sql_table_name = create_cache_table_for_smartsuite_table(table_id, table_structure)
    schema = get_cached_table_schema(table_id)
  end

  sql_table_name = schema['sql_table_name']
  field_mapping = JSON.parse(schema['field_mapping'])

  # Prepare bulk insert
  records.each do |record|
    insert_record_into_cache_table(sql_table_name, field_mapping, record)
  end
end

def insert_record_into_cache_table(sql_table_name, field_mapping, record)
  # Build column list and values
  columns = ['id']
  values = [record['id']]
  placeholders = ['?']

  field_mapping.each do |field_slug, sql_column|
    next if field_slug == 'id'

    columns << sql_column
    values << serialize_field_value(record[field_slug])
    placeholders << '?'
  end

  # Add metadata
  columns.concat(['created_on', 'updated_on', 'cached_at', 'expires_at'])
  values.concat([
    record['created_on'],
    record['updated_on'],
    Time.now.to_i,
    Time.now.to_i + 300  # 5 min TTL
  ])
  placeholders.concat(['?', '?', '?', '?'])

  # Insert
  @db.execute(
    "INSERT OR REPLACE INTO #{sql_table_name} (#{columns.join(', ')})
     VALUES (#{placeholders.join(', ')})",
    *values
  )
end

def serialize_field_value(value)
  case value
  when Array, Hash
    value.to_json
  when nil
    nil
  else
    value
  end
end
```

### Flexible Querying Implementation

```ruby
# General-purpose query builder
class RecordQuery
  def initialize(cache, table_id)
    @cache = cache
    @table_id = table_id
    @schema = cache.get_cached_table_schema(table_id)
    @sql_table_name = @schema['sql_table_name']
    @field_mapping = JSON.parse(@schema['field_mapping'])
    @where_clauses = []
    @params = []
  end

  def where(conditions)
    conditions.each do |field_slug, condition|
      sql_column = @field_mapping[field_slug]
      raise "Unknown field: #{field_slug}" unless sql_column

      clause, params = build_condition(sql_column, condition)
      @where_clauses << clause
      @params.concat(params)
    end
    self
  end

  def order(field_slug, direction = 'ASC')
    sql_column = @field_mapping[field_slug]
    @order_clause = "ORDER BY #{sql_column} #{direction}"
    self
  end

  def limit(n)
    @limit_clause = "LIMIT #{n.to_i}"
    self
  end

  def execute
    sql = "SELECT * FROM #{@sql_table_name}"
    sql += " WHERE #{@where_clauses.join(' AND ')}" if @where_clauses.any?
    sql += " #{@order_clause}" if @order_clause
    sql += " #{@limit_clause}" if @limit_clause

    @cache.db.execute(sql, @params)
  end

  private

  def build_condition(column, condition)
    if condition.is_a?(Hash)
      # Complex condition: {eq: 'value'}, {gte: 100}, {contains: 'text'}
      op, value = condition.first

      case op
      when :eq
        ["#{column} = ?", [value]]
      when :ne
        ["#{column} != ?", [value]]
      when :gt
        ["#{column} > ?", [value]]
      when :gte
        ["#{column} >= ?", [value]]
      when :lt
        ["#{column} < ?", [value]]
      when :lte
        ["#{column} <= ?", [value]]
      when :contains
        ["#{column} LIKE ?", ["%#{value}%"]]
      when :starts_with
        ["#{column} LIKE ?", ["#{value}%"]]
      when :in
        placeholders = value.map { '?' }.join(',')
        ["#{column} IN (#{placeholders})", value]
      when :between
        ["#{column} BETWEEN ? AND ?", [value[:min], value[:max]]]
      when :is_null
        ["#{column} IS NULL", []]
      when :is_not_null
        ["#{column} IS NOT NULL", []]
      when :has_any_of  # For JSON arrays
        # Check if JSON array contains any of the values
        conditions = value.map { "json_extract(#{column}, '$') LIKE ?" }
        params = value.map { |v| "%\"#{v}\"%"  }
        ["(#{conditions.join(' OR ')})", params]
      end
    else
      # Simple equality
      ["#{column} = ?", [condition]]
    end
  end
end

# Usage examples:
cache.query('table_abc123')
  .where(status: 'Active', priority: {in: ['High', 'Critical']})
  .where(revenue: {gte: 50000})
  .order('due_date', 'ASC')
  .limit(10)
  .execute

cache.query('table_abc123')
  .where(project_name: {contains: 'Alpha'})
  .where(due_date: {between: {min: start_ts, max: end_ts}})
  .execute

cache.query('table_abc123')
  .where(assigned_to: {has_any_of: ['user_123', 'user_456']})
  .execute
```

### Schema Evolution (Field Changes)

```ruby
def handle_schema_evolution(table_id, new_structure)
  old_schema = get_cached_table_schema(table_id)
  return create_cache_table_for_smartsuite_table(table_id, new_structure) unless old_schema

  old_structure = JSON.parse(old_schema['structure'])
  old_fields = old_structure['structure'].map { |f| f['slug'] }.to_set
  new_fields = new_structure['structure'].map { |f| f['slug'] }.to_set

  added_fields = new_fields - old_fields
  removed_fields = old_fields - new_fields

  sql_table_name = old_schema['sql_table_name']
  field_mapping = JSON.parse(old_schema['field_mapping'])

  # Add new columns
  added_fields.each do |field_slug|
    field_info = new_structure['structure'].find { |f| f['slug'] == field_slug }
    sql_column = sanitize_column_name(field_slug)
    sql_type = map_field_type(field_info['field_type'])

    @db.execute("ALTER TABLE #{sql_table_name} ADD COLUMN #{sql_column} #{sql_type}")
    field_mapping[field_slug] = sql_column

    # Create index if needed
    if field_info['field_type'] =~ /status|select|date/
      @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{sql_column} ON #{sql_table_name}(#{sql_column})")
    end
  end

  # Note: SQLite doesn't support DROP COLUMN (before version 3.35.0)
  # Removed fields just become unused columns (acceptable trade-off)

  # Update schema metadata
  @db.execute(
    "UPDATE cached_table_schemas
     SET structure = ?, field_mapping = ?, updated_at = ?
     WHERE table_id = ?",
    new_structure.to_json,
    field_mapping.to_json,
    Time.now.to_i,
    table_id
  )
end
```

### DB GUI Exploration

With this approach, users can easily explore data using any SQLite GUI (DB Browser, TablePlus, etc.):

```sql
-- List all cached tables
SELECT * FROM cached_table_schemas;

-- Explore projects
SELECT * FROM cache_records_abc123 WHERE status = 'Active' ORDER BY due_date;

-- Find high-revenue projects
SELECT project_name, customer_name, revenue
FROM cache_records_abc123
WHERE revenue > 100000
ORDER BY revenue DESC;

-- Join across tables (if linked)
SELECT
  p.project_name,
  c.customer_name,
  c.industry
FROM cache_records_abc123 p
JOIN cache_records_def456 c ON json_extract(p.customer_id, '$[0]') = c.id;
```

### Pros:
- ✅ **Proper SQL types** for every field
- ✅ **Real column names** (project_name vs attr_text_1)
- ✅ **Easy DB GUI exploration** (intuitive table/column names)
- ✅ **Optimal indexes** per table's actual fields
- ✅ **Better query performance** (proper types, targeted indexes)
- ✅ **Smaller tables** (only relevant fields per table)
- ✅ **Natural SQL queries** (standard WHERE clauses)
- ✅ **Foreign key relationships** possible (linked records)
- ✅ **Mirrors SmartSuite structure** (familiar to users)

### Cons:
- ❌ **Dynamic schema** (CREATE TABLE at runtime)
- ❌ **Schema migration** complexity (ALTER TABLE when fields change)
- ❌ **More tables** in database (N tables for N SmartSuite tables)
- ❌ **Schema tracking** overhead (cached_table_schemas table)
- ❌ **SQLite column limit** (max ~2000 columns, unlikely to hit but possible)

---

## Comparison Matrix

| Aspect | Attribute Mapping (A) | Dynamic Tables (B) |
|--------|----------------------|-------------------|
| **Schema Complexity** | ✅ Fixed, simple | 🟡 Dynamic, moderate |
| **Query Performance** | 🟡 Good for mapped fields | ✅ Excellent (all fields) |
| **DB GUI Usability** | ❌ Cryptic (attr_text_1) | ✅ Intuitive (project_name) |
| **Scalability** | ❌ Limited attributes | ✅ Unlimited fields |
| **Type Safety** | 🟡 For mapped fields | ✅ All fields typed |
| **Index Strategy** | 🟡 Limited indexes | ✅ Optimal per table |
| **Schema Evolution** | ✅ Simple (just config) | 🟡 ALTER TABLE needed |
| **Implementation** | 🟡 Moderate | 🟡 Moderate |
| **Maintenance** | ❌ Manual config | ✅ Automatic |
| **Cross-table Queries** | ✅ Easier (same schema) | 🟡 Possible but complex |
| **Storage Efficiency** | ❌ Wasted columns | ✅ Compact |
| **SQL Naturalness** | ❌ Obscure column names | ✅ Natural SQL |

**Score: Dynamic Tables (B) wins 9-3**

---

## Recommendation: Dynamic Table Creation (Approach B) ⭐

### Why?

1. **Aligns perfectly with your requirements:**
   - ✅ Easy DB GUI exploration (column names = field names)
   - ✅ Proper SQL types and indexes
   - ✅ Better query performance
   - ✅ Natural, intuitive SQL queries

2. **Better developer experience:**
   ```ruby
   # Natural queries instead of cryptic attribute columns
   cache.query('table_abc123')
     .where(project_name: {contains: 'Alpha'})
     .where(status: 'Active')
     .order('due_date')
   ```

3. **Better user experience:**
   - Open SQLite file in DB Browser
   - See tables named after SmartSuite tables
   - See columns with actual field names
   - Write standard SQL queries

4. **Flexible and scalable:**
   - No limit on number of fields
   - Each table gets optimal schema
   - Proper types for every field
   - Targeted indexes

### Implementation Plan

**Phase 1: Core Dynamic Schema**
1. Implement field type mapping
2. Implement table creation from SmartSuite structure
3. Implement record insertion
4. Test with 2-3 different table types

**Phase 2: Query Builder**
1. Implement RecordQuery class
2. Support all comparison operators
3. Support ordering and limiting
4. Test complex queries

**Phase 3: Schema Evolution**
1. Detect field additions
2. Implement ALTER TABLE for new columns
3. Update schema metadata
4. Test with schema changes

**Phase 4: Optimization**
1. Analyze index usage
2. Add compound indexes if needed
3. Optimize JSON array queries
4. Performance testing

---

## Flexible Query Interface (Addresses Comment #2)

Instead of individual `find_records_by_[field]` methods, implement a **query builder** (shown above in Dynamic Tables approach).

### Key Features:

```ruby
# Chaining multiple criteria
cache.query(table_id)
  .where(field1: value1)
  .where(field2: {operator: value2})
  .order(field3)
  .limit(n)
  .execute

# Complex conditions
cache.query(table_id)
  .where(
    status: {in: ['Active', 'Pending']},
    revenue: {gte: 50000},
    due_date: {between: {min: start_date, max: end_date}},
    project_name: {contains: 'Alpha'}
  )
  .execute

# JSON array fields
cache.query(table_id)
  .where(assigned_to: {has_any_of: ['user_1', 'user_2']})
  .execute

# Raw SQL fallback for advanced cases
cache.execute_sql(
  "SELECT * FROM cache_records_abc123
   WHERE status = ? AND revenue > ?
   ORDER BY due_date
   LIMIT 10",
  'Active', 50000
)
```

---

## Summary & Next Steps

### Decisions:
1. ✅ **Raw SQLite** (no ORM)
2. ✅ **Dynamic table creation** (one SQL table per SmartSuite table)
3. ✅ **Flexible query builder** (multi-criteria, chainable)
4. ✅ **Aggressive fetch** (all records, no SmartSuite filter translation)

### Next Steps:
1. **Review this design** - Does it align with your vision?
2. **Begin implementation** - Start with Phase 1 (core dynamic schema)
3. **Test with real data** - Use your actual SmartSuite workspace
4. **Iterate** - Refine based on real-world usage

### Questions for You:
1. Does the dynamic table approach address your concerns about DB GUI exploration?
2. Any specific field types or edge cases we should handle specially?
3. Should we implement both approaches as plugins, or commit to dynamic tables?
4. Ready to start implementation?

---

*Design document v2.0 - Record Storage Strategies*
