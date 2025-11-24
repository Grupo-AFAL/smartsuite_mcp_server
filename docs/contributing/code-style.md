# Code Style Guide

Ruby coding standards and style guidelines for SmartSuite MCP Server.

## Overview

We follow standard Ruby conventions with some project-specific guidelines. Consistency is key to maintaining readable, maintainable code.

---

## General Principles

### 1. Use 2 Spaces for Indentation

**Always use 2 spaces, never tabs.**

**Good:**
```ruby
def list_solutions
  response = api_request(:get, '/solutions/')

  if response.is_a?(Hash)
    format_solutions(response['items'])
  end
end
```

**Avoid:**
```ruby
def list_solutions
    response = api_request(:get, '/solutions/')  # 4 spaces

    if response.is_a?(Hash)
        format_solutions(response['items'])  # Inconsistent
    end
end
```

---

### 2. Keep Lines Under 100 Characters

Aim for 80-100 characters per line for readability.

**Good:**
```ruby
def create_record(table_id, data)
  api_request(:post, "/applications/#{table_id}/records/", body: data)
end
```

**Avoid:**
```ruby
def create_record(table_id, data)
  api_request(:post, "/applications/#{table_id}/records/", body: data, headers: {'Content-Type' => 'application/json', 'Authorization' => "Token #{@api_key}"})
end
```

**Better:**
```ruby
def create_record(table_id, data)
  api_request(
    :post,
    "/applications/#{table_id}/records/",
    body: data,
    headers: {
      'Content-Type' => 'application/json',
      'Authorization' => "Token #{@api_key}"
    }
  )
end
```

---

### 3. Use Descriptive Variable Names

Choose clear, meaningful names over abbreviations.

**Good:**
```ruby
user_hash = {'id' => 'user_123', 'name' => 'John'}
solution_count = solutions.length
table_structure = get_table(table_id)
```

**Avoid:**
```ruby
uh = {'id' => 'user_123', 'name' => 'John'}  # Unclear
sc = solutions.length  # What is sc?
ts = get_table(table_id)  # Ambiguous
```

---

### 4. Write Meaningful Comments

Comment complex logic, not obvious code.

**Good:**
```ruby
# Extract record IDs from hydrated linked field values
# Hydrated format: [{"id" => "rec_123", "title" => "Task 1"}]
# We need just the IDs for the cache query
record_ids = linked_records.map { |rec| rec['id'] }
```

**Avoid:**
```ruby
# Get IDs
record_ids = linked_records.map { |rec| rec['id'] }  # Too brief

# This line maps over linked_records and extracts the id from each
record_ids = linked_records.map { |rec| rec['id'] }  # Too obvious
```

---

### 5. Prefer Explicit Over Implicit

Be explicit with return values and intentions.

**Good:**
```ruby
def find_user(user_id)
  user = users.find { |u| u['id'] == user_id }
  return nil unless user

  user
end
```

**Acceptable:**
```ruby
def find_user(user_id)
  users.find { |u| u['id'] == user_id }
end
```

---

### 6. Use Guard Clauses to Reduce Nesting

Return early to keep code flat and readable.

**Good:**
```ruby
def process_record(record)
  return nil if record.nil?
  return nil unless record['status'] == 'Active'

  # Main logic here
  transform_record(record)
end
```

**Avoid:**
```ruby
def process_record(record)
  if record
    if record['status'] == 'Active'
      # Main logic here
      transform_record(record)
    end
  end
end
```

---

## Naming Conventions

### Methods

Use `snake_case` for method names:

```ruby
def list_solutions
def get_table_structure
def create_new_record
```

### Variables

Use `snake_case` for variables:

```ruby
api_key = ENV['SMARTSUITE_API_KEY']
table_id = 'tbl_abc123'
user_count = members.length
```

### Constants

Use `SCREAMING_SNAKE_CASE` for constants:

```ruby
DEFAULT_CACHE_TTL = 14400  # 4 hours in seconds
MAX_RECORDS_PER_PAGE = 1000
API_BASE_URL = 'https://app.smartsuite.com/api/v1'
```

### Classes and Modules

Use `PascalCase` for classes and modules:

```ruby
class SmartSuiteClient
module WorkspaceOperations
class ResponseFormatter
```

---

## Code Organization

### Method Order

Organize methods logically:

1. Public methods (API)
2. Private methods (helpers)

```ruby
class SmartSuiteClient
  # Public API
  def list_solutions
    # ...
  end

  def get_table(table_id)
    # ...
  end

  # Private helpers
  private

  def api_request(method, endpoint, **options)
    # ...
  end

  def format_response(data)
    # ...
  end
end
```

### Module Inclusion

Group related functionality in modules:

```ruby
class SmartSuiteClient
  include WorkspaceOperations
  include TableOperations
  include RecordOperations
  include FieldOperations
  include MemberOperations
  include CommentOperations
  include ViewOperations

  def initialize(api_key, account_id)
    # ...
  end
end
```

---

## Spacing and Formatting

### Blank Lines

Use blank lines to separate logical blocks:

**Good:**
```ruby
def list_records(table_id, limit = 10, offset = 0, **options)
  # Validate parameters
  return error('fields parameter required') unless options[:fields]

  # Check cache
  cache_key = "table_#{table_id}"
  cached_data = cache.get(cache_key)

  # Return cached or fetch fresh
  if cached_data
    query_cache(cached_data, limit, offset, options)
  else
    fetch_from_api(table_id, limit, offset, options)
  end
end
```

**Avoid:**
```ruby
def list_records(table_id, limit = 10, offset = 0, **options)
  return error('fields parameter required') unless options[:fields]
  cache_key = "table_#{table_id}"
  cached_data = cache.get(cache_key)
  if cached_data
    query_cache(cached_data, limit, offset, options)
  else
    fetch_from_api(table_id, limit, offset, options)
  end
end
```

### Spacing Around Operators

**Good:**
```ruby
sum = a + b
result = value * 2
is_valid = status == 'Active'
```

**Avoid:**
```ruby
sum=a+b
result=value*2
is_valid=status=='Active'
```

### Hash Formatting

**Single-line for short hashes:**
```ruby
user = {id: 'user_123', name: 'John'}
```

**Multi-line for complex hashes:**
```ruby
filter = {
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'priority', comparison: 'is', value: 'High'}
  ]
}
```

---

## String Formatting

### Prefer String Interpolation Over Concatenation

**Good:**
```ruby
message = "User #{user_id} not found"
url = "/api/v1/applications/#{table_id}/records/"
```

**Avoid:**
```ruby
message = "User " + user_id + " not found"
url = "/api/v1/applications/" + table_id + "/records/"
```

### Use Single Quotes for Static Strings

**Good:**
```ruby
status = 'Active'
message = 'Record created'
```

**Use double quotes when interpolating:**
```ruby
message = "Created record #{record_id}"
```

---

## Conditionals

### Prefer Positive Conditionals

**Good:**
```ruby
if user.active?
  process_user(user)
end
```

**Avoid:**
```ruby
unless user.inactive?
  process_user(user)
end
```

### Use Ternary for Simple Conditions

**Good:**
```ruby
status = active? ? 'Active' : 'Inactive'
```

**Avoid for complex logic:**
```ruby
# Too complex for ternary
result = condition1 ? (condition2 ? value1 : value2) : (condition3 ? value3 : value4)

# Better:
if condition1
  result = condition2 ? value1 : value2
else
  result = condition3 ? value3 : value4
end
```

---

## Error Handling

### Return Error Hashes Consistently

**Good:**
```ruby
def get_table(table_id)
  return {error: 'Table ID is required'} if table_id.nil?

  response = api_request(:get, "/applications/#{table_id}/")

  if response.is_a?(Hash) && response['error']
    {error: "API error: #{response['error']}"}
  else
    filter_table_structure(response)
  end
end
```

### Log Errors Appropriately

```ruby
def track_api_call(endpoint, method)
  # ... tracking logic ...
rescue => e
  $stderr.puts "[ApiStatsTracker] Error: #{e.message}"
  # Don't raise - tracking failures shouldn't break the app
end
```

---

## Method Signatures

### Use Keyword Arguments for Optional Parameters

**Good:**
```ruby
def list_records(table_id, limit = 10, offset = 0, **options)
  fields = options[:fields]
  filter = options[:filter]
  # ...
end
```

**Usage:**
```ruby
list_records('tbl_123', 10, 0, fields: ['status'], filter: {...})
```

---

## Documentation

### YARD Documentation

Document public methods with YARD:

```ruby
# Lists all solutions in the workspace
#
# @param include_activity_data [Boolean] Include usage metrics (default: false)
# @param fields [Array<String>] Specific fields to return (optional)
# @return [Hash] Hash containing solutions array and count
# @example
#   list_solutions(include_activity_data: true)
#   # => {solutions: [...], count: 42}
def list_solutions(include_activity_data: false, fields: nil)
  # Implementation
end
```

---

## Testing Style

### Test Method Names

Use descriptive test names:

**Good:**
```ruby
def test_list_solutions_returns_formatted_response
def test_get_table_handles_missing_table_id
def test_cache_hit_returns_cached_data
```

**Avoid:**
```ruby
def test_solutions
def test_table
def test_cache
```

### Test Structure

Follow Arrange-Act-Assert pattern:

```ruby
def test_create_record_success
  # Arrange
  client = SmartSuiteClient.new('test_key', 'test_account')
  data = {status: 'Active', title: 'Test'}

  # Act
  result = client.create_record('tbl_123', data)

  # Assert
  assert_equal 'rec_123', result['id']
  assert_equal 'Active', result['status']
end
```

---

## RuboCop Integration

We use RuboCop for automated style checking:

```bash
# Check all files
bundle exec rubocop

# Auto-fix violations
bundle exec rubocop -A

# Check specific file
bundle exec rubocop lib/smartsuite_client.rb
```

### Common RuboCop Rules

- `Layout/LineLength`: Keep lines under 100 characters
- `Style/StringLiterals`: Prefer single quotes
- `Layout/EmptyLines`: Use blank lines appropriately
- `Naming/MethodName`: Use snake_case for methods
- `Style/TrailingCommaInArrayLiteral`: Consistent trailing commas

---

## Examples

### Good Code Example

```ruby
# Lists records from a SmartSuite table with caching support
#
# @param table_id [String] Table identifier
# @param limit [Integer] Maximum records to return
# @param offset [Integer] Pagination offset
# @param options [Hash] Additional options
# @option options [Array<String>] :fields Required field slugs to return
# @option options [Hash] :filter SmartSuite filter criteria
# @return [Hash] Formatted response with records and metadata
def list_records(table_id, limit = 10, offset = 0, **options)
  # Validate required parameters
  return {error: 'fields parameter is required'} unless options[:fields]

  # Check cache first
  if cache_valid?(table_id)
    return query_cached_records(table_id, limit, offset, options)
  end

  # Fetch from API
  response = fetch_records_from_api(table_id, limit, offset, options)

  # Format and return
  format_records_response(response, limit, offset)
end

private

def cache_valid?(table_id)
  @cache.exists?(table_id) && !@cache.expired?(table_id)
end

def query_cached_records(table_id, limit, offset, options)
  records = @cache.query(table_id, options[:filter])
  paginated = records.drop(offset).take(limit)

  {
    records: paginated,
    count: paginated.length,
    total: records.length,
    cached: true
  }
end
```

---

## Tools

### Recommended Editor Settings

**VS Code (`.vscode/settings.json`):**
```json
{
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "[ruby]": {
    "editor.defaultFormatter": "rubocop"
  }
}
```

---

## See Also

- **[Testing Guidelines](testing.md)** - How to write tests
- **[Documentation Standards](documentation.md)** - Documentation requirements
- **[CONTRIBUTING.md](../../CONTRIBUTING.md)** - General contribution guide

---

## Need Help?

- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
