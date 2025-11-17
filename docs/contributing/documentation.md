# Documentation Standards

Guidelines for writing and maintaining documentation for SmartSuite MCP Server.

## Overview

Good documentation is essential for user adoption and contributor onboarding. This guide covers documentation standards, structure, and best practices.

---

## Documentation Structure

### Documentation Hierarchy

```
docs/
├── README.md                    # Documentation index
├── getting-started/             # New user guides
│   ├── installation.md
│   ├── quick-start.md
│   ├── configuration.md
│   └── troubleshooting.md
├── guides/                      # In-depth guides
│   ├── user-guide.md
│   ├── caching-guide.md
│   ├── filtering-guide.md
│   └── performance-guide.md
├── api/                         # API reference
│   ├── README.md
│   ├── workspace.md
│   ├── tables.md
│   ├── records.md
│   ├── fields.md
│   ├── members.md
│   ├── comments.md
│   ├── views.md
│   └── stats.md
├── architecture/                # Technical details
│   ├── overview.md
│   ├── caching-system.md
│   ├── mcp-protocol.md
│   ├── data-flow.md
│   └── design-decisions.md
├── reference/                   # Quick references
│   ├── field-types.md
│   └── filter-operators.md
├── examples/                    # Tutorials
│   ├── README.md
│   ├── basic-workflow.md
│   └── advanced-filtering.md
└── contributing/                # Contributor docs
    ├── code-style.md
    ├── testing.md
    └── documentation.md
```

---

## Documentation Types

### 1. Getting Started (For New Users)

**Purpose:** Help users install and configure the server

**Characteristics:**
- Step-by-step instructions
- Assumes no prior knowledge
- Includes screenshots/examples
- Links to troubleshooting

**Example Structure:**
```markdown
# Installation Guide

## Prerequisites
- System requirements
- What you'll need

## Step 1: Install Ruby
- macOS instructions
- Windows instructions
- Linux instructions

## Step 2: Clone Repository
...

## Verification
- How to test it works

## Troubleshooting
- Common issues
```

### 2. Guides (For Learning)

**Purpose:** Teach concepts and best practices

**Characteristics:**
- Explains the "why" not just "how"
- Real-world examples
- Progressive difficulty
- Links to related guides

**Example Structure:**
```markdown
# Caching Guide

## Overview
- What is caching
- Why it matters
- When to use it

## How It Works
- Cache-first strategy
- TTL behavior
- Invalidation

## Usage Patterns
- Common scenarios
- Best practices
- Performance tips

## Advanced Topics
...
```

### 3. API Reference (For Lookup)

**Purpose:** Complete technical reference for all tools

**Characteristics:**
- Exhaustive parameter documentation
- Return value specifications
- Code examples
- Error documentation

**Example Structure:**
```markdown
# list_records

Lists records from a SmartSuite table.

## Parameters

### Required
- `table_id` (String): Table identifier
- `fields` (Array<String>): Field slugs to return

### Optional
- `limit` (Integer): Max records (default: 10)
...

## Returns

Hash containing:
- `records` (Array): Record objects
- `count` (Integer): Records returned
...

## Examples

```ruby
# Basic usage
list_records('tbl_123', fields: ['status'])
```

## Errors
...
```

### 4. Architecture Docs (For Understanding)

**Purpose:** Explain system design and implementation

**Characteristics:**
- High-level overview
- Design decisions explained
- Diagrams and flowcharts
- Links to code

**Example Structure:**
```markdown
# Caching System Architecture

## Overview
- Why we built it
- Goals and constraints

## Design
- SQLite backend
- Table-based TTL
- Dynamic schema

## Implementation
- Key components
- Data flow
- Performance characteristics

## Trade-offs
- What we optimized for
- What we sacrificed
```

---

## Writing Style

### General Guidelines

1. **Be Clear and Concise**
   - Use simple language
   - Short sentences (< 25 words)
   - Active voice

2. **Be Specific**
   - Concrete examples over abstract concepts
   - Actual code over pseudocode
   - Real scenarios over hypotheticals

3. **Be Helpful**
   - Anticipate questions
   - Link to related docs
   - Provide troubleshooting tips

### Voice and Tone

**Use active voice:**
```markdown
✅ The cache stores records for 4 hours.
❌ Records are stored by the cache for 4 hours.
```

**Be direct:**
```markdown
✅ Set the SMARTSUITE_API_KEY environment variable.
❌ You might want to consider setting the SMARTSUITE_API_KEY variable.
```

**Be friendly but professional:**
```markdown
✅ This guide will help you get started quickly.
❌ OMG this is so cool! Let's dive in!!!
```

---

## Formatting Standards

### Headings

Use ATX-style headings:

```markdown
# H1 - Document Title (only one per file)
## H2 - Major Sections
### H3 - Subsections
#### H4 - Details (use sparingly)
```

**Hierarchy:**
- H1: Document title
- H2: Major sections
- H3: Subsections
- H4+: Avoid if possible

### Code Blocks

Always specify language for syntax highlighting:

````markdown
```ruby
def list_solutions
  # Code here
end
```

```bash
bundle exec rake test
```

```json
{
  "key": "value"
}
```
````

### Lists

**Unordered lists:**
```markdown
- First item
- Second item
  - Nested item
  - Another nested item
- Third item
```

**Ordered lists:**
```markdown
1. First step
2. Second step
3. Third step
```

### Links

**Internal links (relative paths):**
```markdown
See [Installation Guide](../getting-started/installation.md)
```

**External links:**
```markdown
Visit [SmartSuite](https://app.smartsuite.com)
```

**Reference-style links (for readability):**
```markdown
Check the [API docs][api-ref] and [user guide][guide].

[api-ref]: ../api/records.md
[guide]: ../guides/user-guide.md
```

### Emphasis

```markdown
**Bold** for important terms
*Italic* for emphasis
`code` for inline code/filenames
```

### Tables

```markdown
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| table_id | String | Yes | Table identifier |
| limit | Integer | No | Max records (default: 10) |
```

Keep tables simple and readable.

---

## Code Examples

### Make Examples Complete

**Good:**
```markdown
## Example

```ruby
# List active tasks
list_records('tbl_tasks', 10, 0,
  fields: ['title', 'status'],
  filter: {
    operator: 'and',
    fields: [{field: 'status', comparison: 'is', value: 'Active'}]
  }
)
```

This returns the first 10 active tasks with only title and status fields.
```

**Avoid:**
```markdown
## Example

```ruby
list_records(table_id, limit, offset, fields: [...])
```
```

### Show Both Success and Error Cases

```markdown
## Examples

### Success Case

```ruby
result = create_record('tbl_123', {status: 'Active'})
# => {id: 'rec_456', status: 'Active'}
```

### Error Case

```ruby
result = create_record(nil, {})
# => {error: 'Table ID is required'}
```
```

---

## YARD Documentation

### Format

```ruby
# Short description (one line)
#
# Longer description if needed. Can span multiple lines
# and explain complex behavior.
#
# @param table_id [String] Table identifier
# @param limit [Integer] Maximum records to return (default: 10)
# @param options [Hash] Additional options
# @option options [Array<String>] :fields Required field slugs
# @option options [Boolean] :bypass_cache Force API call
# @return [Hash] Response containing records array and metadata
# @raise [ArgumentError] If table_id is nil
# @example Basic usage
#   list_records('tbl_123', fields: ['status'])
#   # => {records: [...], count: 10}
# @example With filter
#   list_records('tbl_123',
#     fields: ['status'],
#     filter: {operator: 'and', fields: [...]}
#   )
# @see #get_table For table schema information
def list_records(table_id, limit = 10, **options)
  # Implementation
end
```

### Generate YARD Docs

```bash
# Generate documentation
bundle exec yard doc

# View statistics
bundle exec yard stats

# List undocumented methods
bundle exec yard stats --list-undoc
```

---

## Documentation Checklist

When adding/updating documentation:

### Content
- [ ] Accurate and up-to-date
- [ ] Complete (covers all parameters/options)
- [ ] Examples provided
- [ ] Error cases documented
- [ ] Links to related docs

### Format
- [ ] Proper markdown syntax
- [ ] Code blocks have language specified
- [ ] Headings use proper hierarchy
- [ ] Links work (no broken links)
- [ ] Tables render correctly

### Style
- [ ] Clear and concise language
- [ ] Active voice used
- [ ] Consistent terminology
- [ ] No spelling/grammar errors

### Organization
- [ ] Logical flow/structure
- [ ] Progressive disclosure (simple → complex)
- [ ] Proper categorization
- [ ] Easy to scan/navigate

---

## Updating Documentation

### When Code Changes

**Always update docs when:**
1. Adding new features
2. Changing existing behavior
3. Deprecating functionality
4. Fixing bugs that affect usage

**What to update:**
- README.md (if user-facing)
- CHANGELOG.md (always!)
- Relevant guide(s)
- API reference
- CLAUDE.md (if architecture changes)
- Examples (if needed)

### Documentation Pull Requests

Include in your PR:
```markdown
## Documentation Changes

- [ ] Updated README.md with new feature
- [ ] Added examples to user-guide.md
- [ ] Updated API reference
- [ ] Added entry to CHANGELOG.md
- [ ] Updated YARD documentation
```

---

## Common Documentation Patterns

### Prerequisites Section

```markdown
## Prerequisites

Before starting, ensure you have:

- Ruby 3.0 or higher
- Bundler installed
- SmartSuite account with API access
- Claude Desktop (latest version)
```

### Step-by-Step Instructions

```markdown
## Installation Steps

### 1. Install Ruby

**macOS:**
```bash
brew install ruby
```

**Linux:**
```bash
sudo apt-get install ruby-full
```

### 2. Clone Repository

```bash
git clone https://github.com/...
```

...
```

### Troubleshooting Section

```markdown
## Troubleshooting

### Server not appearing?

**Check logs:**
```bash
tail -f ~/Library/Logs/Claude/mcp*.log
```

**Common issues:**
- ❌ Relative path used → Use absolute path
- ❌ Wrong Ruby version → Must be 3.0+
- ❌ Missing bundle install → Run it first
```

### See Also Section

```markdown
## See Also

- **[Installation Guide](../getting-started/installation.md)** - Setup instructions
- **[User Guide](../guides/user-guide.md)** - How to use the server
- **[API Reference](../api/records.md)** - Complete API docs
```

---

## Documentation Maintenance

### Regular Reviews

- Monthly: Check for broken links
- Quarterly: Update screenshots
- Per release: Verify all docs accurate
- Annually: Reorganize if needed

### Version Compatibility

Note version requirements:

```markdown
## New in v1.7

The cache system was introduced in version 1.7.

**Requires:** SmartSuite MCP Server v1.7+
```

---

## Tools

### Markdown Linting

```bash
# Install markdownlint
npm install -g markdownlint-cli

# Check all markdown files
markdownlint docs/**/*.md

# Auto-fix issues
markdownlint --fix docs/**/*.md
```

### Link Checking

```bash
# Check for broken links
find docs -name "*.md" -exec grep -l "\[.*\](.*\.md)" {} \;
```

---

## See Also

- **[Code Style Guide](code-style.md)** - Coding standards
- **[Testing Guidelines](testing.md)** - How to write tests
- **[CONTRIBUTING.md](../../CONTRIBUTING.md)** - General contribution guide

---

## Need Help?

- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
