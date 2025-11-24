# Testing Guidelines

Comprehensive testing standards for SmartSuite MCP Server.

## Overview

We use Minitest (Ruby standard library) for all testing. Tests ensure code quality, prevent regressions, and document expected behavior.

**Current Coverage:** 93.23% (target: 90% - exceeded!)

---

## Test Structure

### Location

All tests are in the `test/` directory:

```
test/
├── test_smartsuite_server.rb      # MCP server tests
├── test_cache_metadata.rb          # Cache metadata tests
├── test_cache_query.rb             # Cache query builder tests
├── test_record_operations.rb       # Record CRUD tests
├── test_comment_operations.rb      # Comment tests
└── test_response_formatter.rb      # Response formatting tests
```

### Test File Naming

- Prefix with `test_`
- Match the file being tested
- Example: `lib/smartsuite_client.rb` → `test/test_smartsuite_client.rb`

---

## Running Tests

### Run All Tests

```bash
# Standard run
bundle exec rake test

# With verbose output
bundle exec rake test TESTOPTS="-v"
```

### Run Specific Test File

```bash
ruby test/test_smartsuite_server.rb
```

### Run Specific Test

```bash
ruby test/test_smartsuite_server.rb -n test_handle_initialize
```

### Run Multiple Specific Tests

```bash
ruby test/test_cache_query.rb -n "/test_where/"
```

This runs all tests with "test_where" in the name.

---

## Writing Tests

### Test Method Naming

Use descriptive names that explain what is being tested:

**Good:**
```ruby
def test_list_solutions_returns_formatted_response
def test_get_table_handles_missing_table_id
def test_cache_hit_returns_cached_data_without_api_call
```

**Avoid:**
```ruby
def test_solutions
def test_table
def test1
```

### Test Structure: Arrange-Act-Assert

Follow the AAA pattern for clarity:

```ruby
def test_create_record_returns_created_record_with_id
  # Arrange - Set up test data and dependencies
  client = SmartSuiteClient.new('test_key', 'test_account')
  data = {status: 'Active', title: 'Test Task'}

  mock_response = {'id' => 'rec_123', 'status' => 'Active', 'title' => 'Test Task'}
  client.define_singleton_method(:api_request) { mock_response }

  # Act - Execute the code being tested
  result = client.create_record('tbl_abc123', data)

  # Assert - Verify the results
  assert_equal 'rec_123', result['id']
  assert_equal 'Active', result['status']
  assert_equal 'Test Task', result['title']
end
```

---

## Mocking and Stubbing

### Mock HTTP Responses

Mock `api_request` to avoid real API calls:

```ruby
def test_list_tables_formats_response_correctly
  client = SmartSuiteClient.new('test_key', 'test_account')

  # Mock API response
  mock_response = {
    'items' => [
      {'id' => 'tbl_1', 'name' => 'Tasks', 'solution_id' => 'sol_abc'},
      {'id' => 'tbl_2', 'name' => 'Projects', 'solution_id' => 'sol_abc'}
    ]
  }

  client.define_singleton_method(:api_request) { mock_response }

  # Test
  result = client.list_tables

  assert_equal 2, result['count']
  assert_equal 'tbl_1', result['tables'][0]['id']
end
```

### Mock StringIO for stdin/stdout

Test MCP protocol communication:

```ruby
def test_handle_initialize_returns_success
  # Arrange - Mock stdin/stdout
  input = StringIO.new(JSON.generate({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {}
  }))
  output = StringIO.new

  server = SmartSuiteServer.new(input, output)

  # Act
  server.handle_request

  # Assert
  output.rewind
  response = JSON.parse(output.read)

  assert_equal '2.0', response['jsonrpc']
  assert_equal 1, response['id']
  assert response['result']['capabilities']
end
```

---

## Assertions

### Common Assertions

```ruby
# Equality
assert_equal expected, actual
refute_equal not_expected, actual

# Truthiness
assert value
refute value
assert_nil value
refute_nil value

# Type checks
assert_instance_of String, value
assert_kind_of Numeric, value

# Collections
assert_empty array
refute_empty array
assert_includes array, item

# Hash keys
assert_includes hash, :key
assert_equal value, hash[:key]

# Exceptions
assert_raises(ArgumentError) { dangerous_method }
```

### Custom Error Messages

Provide helpful messages for failing assertions:

```ruby
assert_equal 10, result['count'],
  "Expected 10 records, got #{result['count']}"

assert_includes result, 'id',
  "Response missing required 'id' field. Keys: #{result.keys}"
```

---

## Test Coverage

### What to Test

1. **Public API Methods**
   - All public methods must have tests
   - Cover happy path and edge cases

2. **Error Handling**
   - Test how code handles errors
   - Invalid inputs, missing data, API errors

3. **Edge Cases**
   - Nil values
   - Empty arrays/hashes
   - Boundary conditions

4. **Integration Points**
   - MCP protocol compliance
   - API request formatting
   - Response parsing

### What NOT to Test

1. **Ruby Standard Library**
   - Don't test `Array#map`, `Hash#merge`, etc.

2. **External APIs**
   - Mock SmartSuite API responses
   - Don't make real HTTP calls in tests

3. **Private Implementation Details**
   - Test behavior, not implementation
   - Focus on public API

---

## Test Examples

### Testing Success Cases

```ruby
def test_client_list_solutions_formats_hash_response
  client = SmartSuiteClient.new('test_key', 'test_account')

  mock_response = {
    'items' => [
      {'id' => 'sol_1', 'name' => 'Solution 1', 'logo_icon' => 'star'}
    ]
  }

  client.define_singleton_method(:api_request) { mock_response }
  result = client.list_solutions

  assert_equal 1, result['count']
  assert_equal 'sol_1', result['solutions'][0]['id']
end
```

### Testing Error Handling

```ruby
def test_get_table_returns_error_when_table_id_missing
  client = SmartSuiteClient.new('test_key', 'test_account')

  result = client.get_table(nil)

  assert result.is_a?(Hash)
  assert_includes result, 'error'
  assert_match(/required/i, result['error'])
end
```

### Testing Edge Cases

```ruby
def test_list_records_handles_empty_response
  client = SmartSuiteClient.new('test_key', 'test_account')

  mock_response = {'items' => []}
  client.define_singleton_method(:api_request) { mock_response }

  result = client.list_records('tbl_123', 10, 0, fields: ['status'])

  assert_equal 0, result['count']
  assert_empty result['records']
end
```

### Testing Private Methods

Use `call_private_method` helper:

```ruby
def call_private_method(obj, method_name, *args)
  obj.send(method_name, *args)
end

def test_format_solution_filters_fields_correctly
  client = SmartSuiteClient.new('test_key', 'test_account')

  input = {
    'id' => 'sol_1',
    'name' => 'Test',
    'internal_field' => 'should_be_removed'
  }

  result = call_private_method(client, :format_solution, input)

  assert_includes result, 'id'
  assert_includes result, 'name'
  refute_includes result, 'internal_field'
end
```

---

## Testing Best Practices

### 1. One Assertion Per Test (When Possible)

**Good:**
```ruby
def test_create_record_returns_record_id
  result = client.create_record('tbl_123', {status: 'Active'})
  assert_equal 'rec_123', result['id']
end

def test_create_record_preserves_status
  result = client.create_record('tbl_123', {status: 'Active'})
  assert_equal 'Active', result['status']
end
```

**Acceptable (related assertions):**
```ruby
def test_create_record_returns_complete_record
  result = client.create_record('tbl_123', {status: 'Active', title: 'Test'})

  assert_equal 'rec_123', result['id']
  assert_equal 'Active', result['status']
  assert_equal 'Test', result['title']
end
```

### 2. Make Tests Independent

Each test should run successfully in isolation:

**Good:**
```ruby
def test_cache_stores_data
  cache = Cache::Layer.new
  cache.set('key', 'value')
  assert_equal 'value', cache.get('key')
end

def test_cache_returns_nil_for_missing_key
  cache = Cache::Layer.new  # Fresh cache
  assert_nil cache.get('nonexistent')
end
```

**Avoid:**
```ruby
def test_cache_stores_data
  @cache.set('key', 'value')  # Depends on setup
  assert_equal 'value', @cache.get('key')
end

def test_cache_has_stored_value
  # Assumes previous test ran first!
  assert_equal 'value', @cache.get('key')
end
```

### 3. Use Setup and Teardown

For common test setup:

```ruby
class CacheTest < Minitest::Test
  def setup
    @cache = Cache::Layer.new
    @test_db = '/tmp/test_cache.db'
  end

  def teardown
    File.delete(@test_db) if File.exist?(@test_db)
  end

  def test_cache_initialization
    assert_instance_of Cache::Layer, @cache
  end
end
```

### 4. Test Error Messages

Verify error messages are helpful:

```ruby
def test_missing_api_key_provides_helpful_error
  client = SmartSuiteClient.new(nil, 'account_id')

  result = client.list_solutions

  assert_includes result, 'error'
  assert_match(/API key/i, result['error'])
  assert_match(/required/i, result['error'])
end
```

### 5. Use Descriptive Test Data

Make test data self-documenting:

**Good:**
```ruby
def test_filters_active_users
  users = [
    {'id' => 'user_1', 'status' => 'active'},
    {'id' => 'user_2', 'status' => 'inactive'},
    {'id' => 'user_3', 'status' => 'active'}
  ]

  result = filter_active_users(users)

  assert_equal 2, result.length
end
```

**Avoid:**
```ruby
def test_filters_active_users
  users = [
    {'id' => 'u1', 's' => 'a'},
    {'id' => 'u2', 's' => 'i'}
  ]
  # ...
end
```

---

## Testing MCP Protocol

### Test Request Handling

```ruby
def test_handle_tool_call_list_solutions
  input = StringIO.new(JSON.generate({
    jsonrpc: '2.0',
    id: 1,
    method: 'tools/call',
    params: {
      name: 'list_solutions',
      arguments: {include_activity_data: true}
    }
  }))
  output = StringIO.new

  server = SmartSuiteServer.new(input, output)
  server.handle_request

  output.rewind
  response = JSON.parse(output.read)

  assert_equal '2.0', response['jsonrpc']
  assert_equal 1, response['id']
  assert_includes response, 'result'
end
```

### Test Tool Schemas

```ruby
def test_tool_registry_includes_list_solutions
  registry = ToolRegistry.new
  tools = registry.list_tools

  list_solutions_tool = tools.find { |t| t[:name] == 'list_solutions' }

  refute_nil list_solutions_tool
  assert_equal 'List all solutions', list_solutions_tool[:description]
  assert_includes list_solutions_tool[:inputSchema][:properties], :include_activity_data
end
```

---

## Performance Testing

### Measure Execution Time

```ruby
def test_cache_query_performance
  cache = populate_large_cache(10_000)  # Helper method

  start_time = Time.now
  result = cache.query('table_id', {field: 'status', value: 'Active'})
  duration = Time.now - start_time

  assert duration < 0.1, "Query took #{duration}s, expected < 0.1s"
end
```

---

## Test Output

### Verbose Output

```bash
$ bundle exec rake test TESTOPTS="-v"

SmartSuiteServerTest#test_handle_initialize = 0.01 s = .
SmartSuiteServerTest#test_handle_tool_call_list_solutions = 0.02 s = .
SmartSuiteServerTest#test_invalid_method = 0.00 s = .

Finished in 0.123s
42 tests, 89 assertions, 0 failures, 0 errors, 0 skips
```

### Coverage Report

Current baseline: **93.23%** (exceeded 90% target!)

```
Coverage report:
  1057 tests, 3100 assertions
  Line Coverage: 93.23% (2932 / 3145)
```

---

## Continuous Integration

Tests run automatically on GitHub Actions:

```yaml
# .github/workflows/test.yml
- name: Run tests
  run: bundle exec rake test

- name: Check coverage
  run: bundle exec rake test:coverage
```

---

## Troubleshooting Tests

### Tests Failing Locally

1. **Clear test artifacts:**
   ```bash
   rm -rf /tmp/test_*.db
   ```

2. **Update dependencies:**
   ```bash
   bundle install
   ```

3. **Check Ruby version:**
   ```bash
   ruby --version  # Should be 3.0+
   ```

### Debugging Tests

Add debugging output:

```ruby
def test_complex_operation
  result = client.some_method

  puts "\n=== DEBUG ==="
  puts "Result: #{result.inspect}"
  puts "Type: #{result.class}"
  puts "============\n"

  assert_equal expected, result
end
```

---

## Test Maintenance

### Keep Tests Fast

- Mock external calls
- Use in-memory databases for tests
- Avoid sleeps and timeouts
- Target: All tests complete in < 5 seconds

### Refactor Tests Like Code

- Extract common setup to helper methods
- Remove duplicate test code
- Keep tests DRY (but readable)

### Update Tests with Code

When changing functionality:
1. Update tests FIRST (TDD approach)
2. Or update tests IMMEDIATELY after code changes
3. Never leave tests broken

---

## See Also

- **[Code Style Guide](code-style.md)** - Coding standards
- **[Documentation Standards](documentation.md)** - Documentation requirements
- **[CONTRIBUTING.md](../../CONTRIBUTING.md)** - General contribution guide

---

## Need Help?

- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
