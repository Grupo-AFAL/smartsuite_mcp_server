# AGENTS.md - Reference for AI Coding Agents

Quick reference for AI agents working on the SmartSuite MCP Server codebase.

## Project Overview

Ruby MCP server enabling AI assistants to interact with SmartSuite via JSON-RPC over stdin/stdout. Key features: SQLite caching, token optimization, modular API operations.

**Tech Stack:** Ruby 3.0+, SQLite, MCP Protocol, SmartSuite REST API

---

## Essential Commands

```bash
# Testing
bundle exec rake test                          # Run all tests
ruby test/test_<name>.rb                       # Run single test file
ruby test/test_<name>.rb -n test_method_name   # Run single test method
bundle exec rake test TESTOPTS="-v"            # Verbose output

# Code Quality (run before committing)
bundle exec rubocop -A                         # Auto-fix lint issues
bundle exec reek                               # Check code smells
bundle exec yard stats --list-undoc            # Check documentation coverage

# Manual Testing
ruby smartsuite_server.rb                      # Run server
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby smartsuite_server.rb
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  SmartSuiteServer (smartsuite_server.rb)                        │
│  └─ JSON-RPC protocol handler, routes to registries             │
├─────────────────────────────────────────────────────────────────┤
│  MCP Layer (lib/smartsuite/mcp/)                                │
│  ├─ ToolRegistry    (26 tools, schemas)                         │
│  ├─ PromptRegistry  (8 filter examples)                         │
│  └─ ResourceRegistry                                            │
├─────────────────────────────────────────────────────────────────┤
│  API Layer (lib/smartsuite/api/)                                │
│  ├─ HttpClient           - HTTP requests, auth                  │
│  ├─ WorkspaceOperations  - Solutions, usage analysis            │
│  ├─ TableOperations      - Table CRUD                           │
│  ├─ RecordOperations     - Record CRUD, bulk ops, files         │
│  ├─ FieldOperations      - Schema management                    │
│  ├─ MemberOperations     - Users, teams                         │
│  ├─ CommentOperations    - Comments                             │
│  └─ ViewOperations       - Views/reports                        │
├─────────────────────────────────────────────────────────────────┤
│  Cache Layer (lib/smartsuite/cache/)                            │
│  ├─ Layer       - Core caching, dynamic tables                  │
│  ├─ Metadata    - TTL config, schema management                 │
│  ├─ Query       - Chainable SQL query builder                   │
│  ├─ Performance - Hit/miss tracking                             │
│  └─ Migrations  - Schema migrations                             │
├─────────────────────────────────────────────────────────────────┤
│  Formatters (lib/smartsuite/formatters/)                        │
│  └─ ResponseFormatter - Plain text output, field filtering      │
├─────────────────────────────────────────────────────────────────┤
│  Supporting                                                     │
│  ├─ SmartSuiteClient (lib/smartsuite_client.rb) - Includes all  │
│  ├─ ApiStatsTracker  (lib/api_stats_tracker.rb) - Usage stats   │
│  ├─ FilterBuilder    (lib/smartsuite/filter_builder.rb)         │
│  └─ FuzzyMatcher     (lib/smartsuite/fuzzy_matcher.rb)          │
└─────────────────────────────────────────────────────────────────┘
```

**Key Files:**

- `smartsuite_server.rb` - Main entry point
- `lib/smartsuite_client.rb` - Thin wrapper including all API modules
- `lib/smartsuite/mcp/tool_registry.rb` - All 26 tool definitions
- `lib/smartsuite/api/*.rb` - API operations by domain
- `lib/smartsuite/cache/*.rb` - Caching system components

---

## Code Style (RuboCop enforced)

### Formatting

- 2 spaces indentation, 140 char line max
- Single quotes `'text'` (double only for `"#{interpolation}"`)
- Hash syntax: `{key: value}` (Ruby 1.9+ style)
- `# frozen_string_literal: true` at top of all files

### Naming

- `snake_case` for methods/variables
- `CamelCase` for classes/modules
- `SCREAMING_SNAKE_CASE` for constants

### Patterns

- `require_relative` for local files
- Guard clauses over nested conditionals
- Include modules in classes (no inheritance for API ops)
- Error handling: rescue `StandardError`, return Hash via helpers

### Error Response Pattern

```ruby
def some_operation(param)
  return error_response('param is required') if param.nil?

  # ... operation logic ...

  operation_response(data: result, message: 'Success')
rescue StandardError => e
  error_response("Operation failed: #{e.message}")
end
```

---

## Testing Guidelines

### Test Structure

- Location: `test/test_<name>.rb`
- Pattern: Arrange-Act-Assert
- Naming: `test_<what>_<expected_behavior>`

### Example Test

```ruby
def test_list_solutions_returns_formatted_response
  # Arrange
  client = SmartSuiteClient.new('test_key', 'test_account')
  mock_response = {'items' => [{'id' => 'sol_1', 'name' => 'Test'}]}
  client.define_singleton_method(:api_request) { mock_response }

  # Act
  result = client.list_solutions

  # Assert
  assert_equal 1, result['count']
  assert_equal 'sol_1', result['solutions'][0]['id']
end
```

### Private Method Testing

```ruby
def call_private_method(obj, method_name, *args)
  obj.send(method_name, *args)
end

result = call_private_method(client, :format_solution, input)
```

### Coverage

- Current: **97.47%** (exceeded 90% target!)
- Test public APIs, error handling, edge cases
- Mock external dependencies (API calls)

---

## Caching System

### How It Works

1. **Cache-first strategy**: Queries check SQLite cache before API
2. **Dynamic tables**: One SQLite table per SmartSuite table
3. **Table-based TTL**: All records expire together (default: 4 hours)
4. **No mutation invalidation**: Cache expires naturally by TTL

### Cache Flow

```
Query → Check cache validity →
  ├─ VALID: Query SQLite (5-20ms)
  └─ INVALID: Fetch ALL records → Store → Query (500-2000ms first time)
```

### Key Cache Files

- `lib/smartsuite/cache/layer.rb` - Core interface
- `lib/smartsuite/cache/query.rb` - SQL query builder
- `lib/smartsuite/cache/metadata.rb` - TTL, schema tracking
- Database: `~/.smartsuite_mcp_cache.db`

### Bypass Cache

```ruby
list_records('tbl_123', 10, 0, fields: ['status'], bypass_cache: true)
```

---

## Adding New Features

### Adding a New Tool

1. Add schema to `lib/smartsuite/mcp/tool_registry.rb`
2. Add handler in `smartsuite_server.rb` → `handle_tool_call`
3. Implement operation in appropriate `lib/smartsuite/api/*_operations.rb`
4. Add tests in `test/test_*.rb`
5. Update docs if user-facing

### Adding API Operations

1. Create/edit module in `lib/smartsuite/api/`
2. Ensure included in `SmartSuiteClient`
3. Use `HttpClient` for requests
4. Follow error handling pattern
5. Add tests

### Tool Schema Example

```ruby
{
  name: 'tool_name',
  description: 'What the tool does',
  inputSchema: {
    type: 'object',
    properties: {
      param1: {type: 'string', description: 'Description'},
      param2: {type: 'integer', description: 'Description'}
    },
    required: ['param1']
  }
}
```

---

## SmartSuite API Notes

### Required Environment Variables

```bash
SMARTSUITE_API_KEY=your_api_key
SMARTSUITE_ACCOUNT_ID=your_account_id
```

### API Parameter Placement

- **Query params (URL)**: `limit`, `offset`, `fields`, `solution`
- **Body params (JSON)**: `filter`, `sort`

### Common Endpoints

```ruby
# Records
POST /api/v1/applications/{table_id}/records/list/?limit=10&offset=0
# Body: {"filter": {...}, "sort": [...]}

# Members/Teams (NOT under /applications/)
POST /api/v1/members/list/?limit=100&offset=0
POST /api/v1/teams/list/?limit=1000&offset=0

# Tables
GET /api/v1/applications/?solution=sol_123&fields=name&fields=id
```

### Rate Limits

- Standard: 5 requests/second
- Overage: 2 requests/second at 100%+ monthly usage
- Hard limit: Denied at 125%

---

## Pre-Commit Checklist (REQUIRED)

```bash
# 1. Run tests
bundle exec rake test

# 2. Fix lint issues
bundle exec rubocop -A
bundle exec reek

# 3. Check docs (optional but recommended)
bundle exec yard stats --list-undoc
```

### Documentation Requirements

- **ALWAYS update CHANGELOG.md** under `[Unreleased]` (CI enforced)
- Update `docs/` for user-facing changes
- Update ROADMAP.md if affects milestones
- Add YARD docs for new public methods

### Commit Message Format

```
<type>: <description>

<optional body>

Types: feat, fix, docs, style, refactor, test, chore
```

---

## Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `refactor/` - Code improvements
- `docs/` - Documentation

---

## File Reference

| File                                         | Purpose                | Lines  |
| -------------------------------------------- | ---------------------- | ------ |
| `smartsuite_server.rb`                       | MCP server entry point | ~262   |
| `lib/smartsuite_client.rb`                   | Client wrapper         | ~30    |
| `lib/smartsuite/mcp/tool_registry.rb`        | Tool schemas           | ~633   |
| `lib/smartsuite/mcp/prompt_registry.rb`      | Prompt templates       | ~447   |
| `lib/smartsuite/api/record_operations.rb`    | Record CRUD            | ~528   |
| `lib/smartsuite/api/workspace_operations.rb` | Solutions              | ~344   |
| `lib/smartsuite/cache/layer.rb`              | Core caching           | varies |
| `lib/smartsuite/cache/query.rb`              | SQL builder            | varies |

---

## Common Pitfalls

1. **Linked record filters**: Use `has_any_of` with record IDs, NOT `is`
2. **Date filters**: Require `{date_mode: 'exact_date', date_mode_value: '2025-01-01'}`
3. **Members endpoint**: `/members/list/` NOT `/applications/members/records/list/`
4. **list_records**: `fields` parameter is REQUIRED
5. **Solutions API**: `/solutions/` ignores `fields` param - client-side filtering needed

---

## Quick Links

- **Full docs**: `docs/README.md`
- **Architecture**: `docs/architecture/overview.md`
- **API reference**: `docs/api/README.md`
- **Filter guide**: `docs/guides/filtering-guide.md`
- **Cache guide**: `docs/guides/caching-guide.md`
