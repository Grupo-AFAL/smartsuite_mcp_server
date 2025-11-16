# Integration Tests

This directory contains manual integration tests that validate the SmartSuite MCP Server against the real SmartSuite API.

## Purpose

These tests:
- Validate API contract assumptions
- Test real API behavior vs. documented behavior
- Verify cache layer works with real data
- Catch breaking changes in SmartSuite API
- Document actual API responses and edge cases

## Prerequisites

### 1. SmartSuite Test Account

You need a SmartSuite account with:
- At least one solution (workspace)
- At least one table with some records
- API access enabled

⚠️ **IMPORTANT:** Use a TEST/DEVELOPMENT workspace only! Never use production credentials!

### 2. Test Credentials Configuration

Integration tests load credentials ONLY from the local `.env` file to prevent accidentally using production credentials.

**Setup Steps:**

1. Copy the example file:
   ```bash
   cp test/integration/.env.example test/integration/.env
   ```

2. Edit `test/integration/.env` with your TEST credentials:
   ```bash
   SMARTSUITE_API_KEY=your_test_api_key_here
   SMARTSUITE_ACCOUNT_ID=your_test_account_id_here
   ```

3. The `.env` file is git-ignored for security

**Security Features:**
- Tests NEVER use `ENV['SMARTSUITE_API_KEY']` from your shell environment
- Credentials are loaded exclusively from the local `.env` file
- Built-in safeguards prevent running with placeholder values
- `.env` file is in `.gitignore` to prevent accidental commits
- Isolated test database (never touches production cache at `~/.smartsuite_mcp_cache.db`)
- Workspace confirmation prompt before any tests run

**Security Note:** Always use TEST credentials, never production!

### 3. Test Data Setup (Optional)

For comprehensive testing, create a test solution with:
- **Test Table 1**: "Customers" with fields:
  - Name (text)
  - Email (email)
  - Status (single select: Active, Inactive)
  - Priority (number: 1-5)
  - Created Date (date)
  - Tags (multiple select)

- **Test Table 2**: "Orders" with fields:
  - Order Number (autonumber)
  - Customer (linked record → Customers)
  - Amount (currency)
  - Status (single select: Pending, Completed, Cancelled)

Add a few test records to each table.

## Safety Features

Integration tests include multiple layers of protection to prevent accidental damage to production data:

### 1. Workspace Confirmation

Before any tests run, you'll be prompted to confirm the workspace:

```
======================================================================
⚠️  WORKSPACE CONFIRMATION REQUIRED
======================================================================

You are about to run integration tests against:
  Account ID: your_account_id
  Solutions found: 5

First few solutions:
  - Test Workspace (sol_123abc)
  - Development Environment (sol_456def)
  - QA Testing (sol_789ghi)

⚠️  WARNING: These tests will:
  - Read data from your workspace
  - Create test records (if write tests are enabled)
  - Modify test records (if write tests are enabled)
  - Use API calls (counts toward your rate limit)

======================================================================
Is this the correct TEST workspace? (yes/no):
```

**Important:**
- Type `yes` (exactly) to proceed with tests
- Any other response aborts all tests
- Review the solution names carefully to ensure it's your test workspace
- Tests will skip immediately if you don't confirm

### 2. Isolated Test Database

Tests use a completely separate database to prevent any interaction with your production cache:

- **Production cache:** `~/.smartsuite_mcp_cache.db` (never touched by tests)
- **Test cache:** `/tmp/smartsuite_mcp_test_cache.db` (auto-cleaned)
- **Confirmation cache:** `/tmp/temp_confirmation.db` (auto-deleted after check)

This ensures integration tests cannot corrupt or interfere with your production cache data.

### 3. Credential Isolation

As described in Prerequisites, credentials are:
- Loaded only from `test/integration/.env`
- Never from shell environment variables
- Validated before use
- Protected by `.gitignore`

## Running Tests

### Run All Integration Tests

```bash
ruby test/integration/test_integration.rb
```

**First-time flow:**
1. Tests load credentials from `.env`
2. Workspace confirmation prompt appears
3. Review workspace details carefully
4. Type `yes` to confirm and proceed
5. Tests run against confirmed workspace

### Run Specific Test Categories

```bash
# Workspace operations only
ruby test/integration/test_integration.rb -n /workspace/

# Table operations only
ruby test/integration/test_integration.rb -n /table/

# Record operations only
ruby test/integration/test_integration.rb -n /record/

# Cache operations only
ruby test/integration/test_integration.rb -n /cache/
```

### Run with Verbose Output

```bash
ruby test/integration/test_integration.rb -v
```

## Test Structure

Integration tests are organized by API category:

- **Workspace Tests**: Solutions, usage analysis, ownership
- **Table Tests**: List tables, get structure, create tables
- **Record Tests**: CRUD operations, filtering, sorting
- **Field Tests**: Add/update/delete fields, schema changes
- **Member Tests**: List users, teams, search
- **Comment Tests**: Add/list comments
- **View Tests**: Get view records, create views
- **Cache Tests**: Caching, invalidation, warming

## Expected Behavior

### Success Output

```
Run options: --seed 12345

# Running:

..................

Finished in 15.234s, 1.18 runs/s, 4.52 assertions/s.

18 runs, 69 assertions, 0 failures, 0 errors, 0 skips
```

### Common Failures

**Authentication Error:**
```
Error: Authentication failed. Check API_KEY and ACCOUNT_ID.
```
**Solution:** Verify your credentials are correct.

**No Solutions Found:**
```
Error: Expected at least 1 solution, got 0
```
**Solution:** Create a test solution in your SmartSuite account.

**Rate Limit:**
```
Error: Rate limit exceeded (429)
```
**Solution:** Wait 60 seconds and try again, or reduce test scope.

## Writing New Integration Tests

```ruby
def test_new_api_feature
  skip "Integration test - requires real API credentials" unless integration_tests_enabled?

  # Arrange
  table_id = get_test_table_id

  # Act
  result = @client.some_new_operation(table_id)

  # Assert
  assert result.is_a?(Hash), "Expected Hash response"
  assert result.key?('expected_field'), "Missing expected field"

  # Document actual behavior
  puts "\nActual API Response:"
  puts JSON.pretty_generate(result)
end
```

## Cleanup

Integration tests create minimal test data but you may want to:

```bash
# Clear cache after tests
rm ~/.smartsuite_mcp_cache.db

# View test metrics
cat ~/.smartsuite_mcp_metrics.log | tail -100
```

## CI/CD Integration (Future)

To run in GitHub Actions:

```yaml
- name: Run Integration Tests
  env:
    SMARTSUITE_API_KEY: ${{ secrets.SMARTSUITE_API_KEY }}
    SMARTSUITE_ACCOUNT_ID: ${{ secrets.SMARTSUITE_ACCOUNT_ID }}
  run: bundle exec ruby test/integration/test_integration.rb
  if: github.event_name == 'schedule' # Run nightly, not on every PR
```

## Troubleshooting

### Tests Won't Run

1. Check environment variables are set:
   ```bash
   echo $SMARTSUITE_API_KEY
   echo $SMARTSUITE_ACCOUNT_ID
   ```

2. Verify API credentials work:
   ```bash
   curl -H "Authorization: Token $SMARTSUITE_API_KEY" \
        -H "Account-Id: $SMARTSUITE_ACCOUNT_ID" \
        https://app.smartsuite.com/api/v1/solutions/
   ```

3. Check account has solutions:
   - Log into https://app.smartsuite.com
   - Verify you have at least one solution

### Tests Failing

1. **Compare expected vs actual**
   - Tests print actual API responses
   - Update expectations if API behavior changed legitimately

2. **Check SmartSuite API status**
   - Visit SmartSuite status page
   - API might be experiencing issues

3. **Verify test data**
   - Ensure test solution/tables exist
   - Check records haven't been deleted

## Best Practices

1. **Idempotent Tests**: Tests should not depend on previous test state
2. **Cleanup**: Delete created test data when possible
3. **Minimal Impact**: Use minimal API calls to respect rate limits
4. **Document Changes**: If API behavior changes, document in test comments
5. **Skip on Failure**: Use `skip` for tests requiring specific setup

## Security

**NEVER commit:**
- API keys
- Account IDs
- Test credentials
- Real customer data

**ALWAYS:**
- Use environment variables
- Use test accounts, not production
- Clear logs containing sensitive data
- Review test output before sharing
