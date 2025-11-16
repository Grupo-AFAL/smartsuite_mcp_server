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

### 2. Environment Variables

Set your test credentials:

```bash
export SMARTSUITE_API_KEY="your_api_key_here"
export SMARTSUITE_ACCOUNT_ID="your_account_id_here"
```

**Security Note:** These are YOUR credentials. Never commit them to git!

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

## Running Tests

### Run All Integration Tests

```bash
ruby test/integration/test_integration.rb
```

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
