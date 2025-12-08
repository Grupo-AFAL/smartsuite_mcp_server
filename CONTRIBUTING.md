# Contributing to SmartSuite MCP Server

Thank you for your interest in contributing to the SmartSuite MCP Server! This document provides guidelines and instructions for contributing.

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inspiring community for all. Please be respectful and constructive in all interactions.

### Expected Behavior

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on what is best for the community
- Show empathy towards other community members

### Unacceptable Behavior

- Harassment, discrimination, or offensive comments
- Trolling or insulting/derogatory comments
- Public or private harassment
- Publishing others' private information without permission

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

**Good bug reports include:**

- Clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs actual behavior
- Ruby version, OS, and SmartSuite MCP Server version
- Relevant logs or error messages

**Example:**

```markdown
**Description:** list_tables fails with large workspaces

**Steps to Reproduce:**

1. Configure MCP server with workspace containing 100+ tables
2. Call list_tables tool
3. Observe timeout error

**Expected:** Should return filtered list of tables
**Actual:** Request times out after 30 seconds

**Environment:**

- Ruby: 3.4.7
- OS: macOS 14.5
- MCP Server: v1.0.1
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- Clear, descriptive title
- Detailed description of the proposed feature
- Use case: why would this be useful?
- Possible implementation approach (if you have one)

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following our coding standards
3. **Add tests** for any new functionality
4. **Update documentation** if needed
5. **Ensure all tests pass** (`bundle exec rake test`)
6. **Submit a pull request**

#### Pull Request Process

1. Update the README.md with details of changes if needed
2. Update the ARCHITECTURE.md if you're changing the structure
3. Add tests that prove your fix/feature works
4. Ensure the test suite passes
5. Follow the Ruby style guide (see below)
6. Write a clear commit message

**PR Title Format:**

- `feat: Add support for deleting records`
- `fix: Handle timeout errors in list_records`
- `docs: Update installation instructions`
- `test: Add tests for ApiStatsTracker`
- `refactor: Extract response formatter`

## Development Setup

### Prerequisites

- Ruby 3.0 or higher
- Bundler
- Git
- SmartSuite account with API access (for integration testing)

### Initial Setup

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/smartsuite_mcp.git
cd smartsuite_mcp

# Install dependencies
bundle install

# Set up environment variables for testing
cp .env.example .env
# Edit .env with your test credentials
```

### Running Tests

```bash
# Run all tests
bundle exec rake test

# Run tests with verbose output
bundle exec rake test TESTOPTS="-v"

# Run a specific test file
ruby test/test_smartsuite_server.rb

# Run a specific test
ruby test/test_smartsuite_server.rb -n test_handle_initialize
```

### Project Structure

```
smartsuite_mcp/
├── lib/                          # Library modules
│   ├── smartsuite_client.rb     # SmartSuite API client
│   └── api_stats_tracker.rb     # API statistics tracking
├── test/                         # Test suite
│   └── test_smartsuite_server.rb
├── smartsuite_server.rb          # Main MCP server
├── ARCHITECTURE.md               # Architecture documentation
└── README.md                     # User documentation
```

## Coding Standards

### Ruby Style Guide

We follow standard Ruby conventions:

**Good:**

```ruby
def list_solutions
  response = api_request(:get, '/solutions/')

  if response.is_a?(Hash) && response['items'].is_a?(Array)
    format_solutions(response['items'])
  else
    response
  end
end
```

**Avoid:**

```ruby
def list_solutions
  response=api_request(:get,'/solutions/')
  if response.is_a?(Hash)&&response['items'].is_a?(Array)
    format_solutions(response['items'])
  else
    response
  end
end
```

### Key Principles

1. **Use 2 spaces for indentation** (not tabs)
2. **Keep lines under 100 characters** when possible
3. **Use descriptive variable names** (`user_hash` not `uh`)
4. **Write meaningful comments** for complex logic
5. **Prefer explicit over implicit** (`return nil` over just `nil`)
6. **Use guard clauses** to reduce nesting

### Testing Standards

1. **Write tests for new features**
2. **Maintain or improve test coverage**
3. **Use descriptive test names** (`test_handle_tool_call_get_api_stats` not `test1`)
4. **Test edge cases** (nil values, empty arrays, etc.)
5. **Mock external dependencies** (API calls in tests)

**Good test:**

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

### Documentation Standards

1. **Update README.md** for user-facing changes
2. **Update ARCHITECTURE.md** for structural changes
3. **Add code comments** for non-obvious logic
4. **Include examples** in documentation
5. **Keep docs up to date** with code changes

## Commit Message Guidelines

### Format

```
<type>: <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

**Simple commit:**

```
feat: Add delete_record tool

Adds new tool to delete records from SmartSuite tables.
Includes error handling and tests.
```

**With breaking changes:**

```
feat: Change list_tables response format

BREAKING CHANGE: list_tables now returns a hash with 'tables'
and 'count' keys instead of the raw API response.

Migration: Update code that expects response['items'] to use
response['tables'] instead.
```

## What to Contribute

### Good First Issues

Look for issues labeled `good first issue` - these are great for newcomers:

- Documentation improvements
- Adding tests
- Small bug fixes
- Code cleanup

### High Priority

- Bug fixes
- Performance improvements
- Test coverage
- Documentation gaps

### Feature Ideas

- Support for more SmartSuite API endpoints
- Caching layer for frequently accessed data
- Webhook support
- Rate limiting improvements
- Better error messages

## Questions?

- Create an issue with the `question` label
- Check existing issues and documentation
- Review the ARCHITECTURE.md for design decisions

## Recognition

Contributors will be recognized in the project README. Thank you for making this project better!

---

By contributing to this project, you agree that your contributions will be licensed under the MIT License.
