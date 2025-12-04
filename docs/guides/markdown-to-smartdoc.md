# Markdown to SmartDoc Conversion Guide

Complete guide for converting Markdown to SmartSuite's SmartDoc format (rich text), including both the MCP tool for dynamic conversion and the batch CLI script for bulk operations.

---

## Table of Contents

1. [Overview](#overview)
2. [Supported Markdown Features](#supported-markdown-features)
3. [MCP Tool Usage](#mcp-tool-usage-dynamic-conversion)
4. [Batch CLI Script](#batch-cli-script-bulk-conversion)
5. [Implementation Details](#implementation-details)
6. [Examples](#examples)

---

## Overview

SmartSuite rich text fields use **SmartDoc format** (TipTap/ProseMirror with snake_case type names). This project provides two ways to convert Markdown to SmartDoc:

1. **MCP Tool** (`convert_markdown_to_smartdoc`) - For Claude to dynamically convert markdown when creating/updating records
2. **CLI Script** (`bin/convert_markdown_sessions`) - For bulk conversion of existing records

**Version:** 2.0.1
**Tests:** 26 test cases, 108 assertions, 0 failures
**Coverage:** 93.34% overall project coverage

---

## Supported Markdown Features

### Block-Level Elements

| Feature | Markdown Syntax | SmartDoc Type | Status |
|---------|----------------|---------------|--------|
| **Headings** | `#`, `##`, `###` | `heading` (levels 1-3) | ✅ Full |
| **Paragraphs** | Plain text | `paragraph` | ✅ Full |
| **Bullet Lists** | `- item` or `* item` | `bullet_list` → `list_item` | ✅ Full |
| **Ordered Lists** | `1. item`, `2. item` | `ordered_list` → `list_item` | ✅ Full |
| **Tables** | `\| col1 \| col2 \|` | `table` → `table_row` | ✅ Full |
| **Code Blocks** | ` ```language ` | `code_block` with `hard_break` | ✅ Full |
| **Horizontal Rules** | `---` or `------` | `horizontal_rule` | ✅ Full |

### Inline Formatting

| Feature | Markdown Syntax | SmartDoc Mark | Status |
|---------|----------------|---------------|--------|
| **Bold** | `**text**` or `__text__` | `strong` | ✅ Full |
| **Italic** | `*text*` or `_text_` | `em` | ✅ Full |
| **Bold+Italic** | `***text***` or `___text___` | `strong` + `em` | ✅ Full |
| **Links** | `[text](url)` | `link` with href | ✅ Full |
| **Links with formatting** | `[**bold**](url)` | `link` + `strong` | ✅ Full |

### HTML Cleanup

| Feature | Description | Status |
|---------|-------------|--------|
| **Div wrappers** | Strips `<div class="rendered">` | ✅ Auto |
| **Paragraph tags** | Strips `<p>` tags | ✅ Auto |
| **Line breaks** | Converts `<br>` to newlines | ✅ Auto |

### Not Supported (Future Enhancements)

- ❌ Checklists (`- [ ]`, `- [x]`)
- ❌ Blockquotes (`>`)
- ❌ Images (`![alt](url)`)
- ❌ Nested lists
- ❌ Inline code (`` `code` ``)
- ❌ Strikethrough (`~~text~~`)
- ❌ Mentions (`@user`, `#record`)
- ❌ Callouts

---

## MCP Tool Usage (Dynamic Conversion)

### When to Use

Use the `convert_markdown_to_smartdoc` MCP tool when Claude needs to:
1. Read markdown content from somewhere
2. Convert it to SmartDoc format
3. Use the result in `create_record` or `update_record`

### Usage Pattern

```javascript
// Call the MCP tool
const smartdoc = await convert_markdown_to_smartdoc({
  markdown: "## Summary\n- Point one\n- Point two"
});

// Use in record creation
await create_record(table_id, {
  description: smartdoc
});
```

### Via Ruby API

```ruby
smartdoc = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown_text)

# Use in record update
client.update_record(table_id, record_id, {
  'description' => smartdoc
})
```

### Example

**Input:**
```markdown
## Meeting Summary

- Action item 1
- Action item 2

Next meeting: **January 15**
```

**Output:**
```json
{
  "data": {
    "type": "doc",
    "content": [
      {
        "type": "heading",
        "attrs": {"level": 2},
        "content": [{"type": "text", "text": "Meeting Summary"}]
      },
      {
        "type": "bullet_list",
        "content": [
          {
            "type": "list_item",
            "content": [
              {
                "type": "paragraph",
                "content": [{"type": "text", "text": "Action item 1"}]
              }
            ]
          },
          {
            "type": "list_item",
            "content": [
              {
                "type": "paragraph",
                "content": [{"type": "text", "text": "Action item 2"}]
              }
            ]
          }
        ]
      },
      {
        "type": "paragraph",
        "content": [
          {"type": "text", "text": "Next meeting: "},
          {
            "type": "text",
            "marks": [{"type": "strong"}],
            "text": "January 15"
          }
        ]
      }
    ]
  }
}
```

---

## Batch CLI Script (Bulk Conversion)

### When to Use

Use `bin/convert_markdown_sessions` for:
- Records automatically generated with Markdown content (e.g., from webhooks)
- Bulk conversion of existing records
- Status updates after conversion
- Minimizing AI token usage during conversion

### Installation

```bash
# Make script executable (already done)
chmod +x bin/convert_markdown_sessions

# Ensure environment variables are set
export SMARTSUITE_API_KEY=your_api_key
export SMARTSUITE_ACCOUNT_ID=your_account_id

# Create personal configuration file (recommended)
cp .conversion_config.example .conversion_config
# Edit .conversion_config with your table IDs and field slugs
```

**Important:** The `.conversion_config` file is gitignored to keep your personal SmartSuite configuration private.

### Configuration File

Create `.conversion_config` with your settings:

```bash
# SmartSuite Table Configuration
TABLE_ID=your_table_id_here
STATUS_FIELD=your_status_field_slug_here
CONTENT_FIELD=your_content_field_slug_here

# Status values (from → to)
FROM_STATUS=ready_for_review
TO_STATUS=complete

# Batch processing
BATCH_SIZE=50
```

### Basic Usage

```bash
# Convert records using .conversion_config settings
bin/convert_markdown_sessions

# Use a different config file
bin/convert_markdown_sessions --config my_custom_config.txt

# Dry run (preview changes)
bin/convert_markdown_sessions --dry-run

# Test with limited records
bin/convert_markdown_sessions --dry-run --limit 10

# Convert with limit
bin/convert_markdown_sessions --limit 50
```

### Command-Line Overrides

```bash
# Override status values
bin/convert_markdown_sessions \
  --from-status different_status \
  --to-status another_status

# Override content field
bin/convert_markdown_sessions --content-field different_field

# Override batch size
bin/convert_markdown_sessions --batch-size 25

# Use different table (all required params)
bin/convert_markdown_sessions \
  --table-id YOUR_TABLE_ID \
  --status-field YOUR_STATUS_FIELD \
  --from-status SOURCE_STATUS \
  --to-status TARGET_STATUS
```

### All Options

```
Options:
  --table-id ID          Table ID
  --status-field SLUG    Status field slug
  --content-field SLUG   Content field slug to convert (default: description)
  --from-status VALUE    Source status value
  --to-status VALUE      Target status value
  --dry-run              Preview changes without updating
  --limit N              Process only N records (for testing)
  --batch-size N         Bulk update batch size (default: 50)
  --config PATH          Path to config file (default: .conversion_config)
  -h, --help             Show help message
```

### How It Works

**1. Efficient Record Identification (Minimal Tokens)**
```ruby
# Fetches only IDs and titles - no content
# Uses cache when available (zero API calls if cached)
filter = {
  'operator' => 'and',
  'fields' => [
    {'field' => 's53394fc66', 'comparison' => 'is', 'value' => 'ready_for_review'}
  ]
}
records = client.list_records(table_id, 1000, 0, filter: filter, fields: ['title'])
```

**2. Direct API Access for Content**
```ruby
# Fetches full record content directly (no AI involvement)
full_records = record_ids.map { |id| client.get_record(table_id, id) }
```

**3. Markdown to SmartDoc Conversion**
```ruby
# Converts markdown text to SmartDoc format
markdown_text = record['description']['html'] || record['description']
smartdoc = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown_text)
```

**4. Bulk Update in Batches**
```ruby
# Updates records in batches of 50 (configurable)
updates = records.map do |record|
  {
    'id' => record['id'],
    'description' => smartdoc,
    's53394fc66' => 'complete'
  }
end
client.bulk_update_records(table_id, updates)
```

### Example Output

```
=== SmartSuite Markdown to SmartDoc Batch Converter ===
Table: 66983fdf0b865a9ad2b02a8d
Status: ready_for_review → complete
Content field: description
Mode: LIVE

Fetching record IDs with status 'ready_for_review'... found 87 records

Sample records to convert:
  - 692491d842526694cbfdea02: OPC1 / TD6 | CASCERMAR: Manejo de horas...
  - 69249f0e86275466074237df: Check-In Transformación Digital
  - 6924a287fcac6a48c2e7d3cc: Entorno Fiscal 2026
  ... and 84 more

Fetching full content for 87 records... done

Converting markdown to SmartDoc format...
  [1/87] ✓ 692491d842526694cbfdea02
  [2/87] ✓ 69249f0e86275466074237df
  [3/87] SKIP 6924a287fcac6a48c2e7d3cc: Already SmartDoc format
  ...

Conversion summary:
  Converted: 82
  Skipped: 5
  Total: 87

Updating 82 records in batches of 50...
  Batch 1/2... ✓ updated 50 records
  Batch 2/2... ✓ updated 32 records

✓ Conversion complete!
  Updated 82 records
  Status changed: ready_for_review → complete
```

### Smart Skipping

The script automatically skips records that:
1. Have no content (`nil`)
2. Already have SmartDoc format (content has `data` key)
3. Have empty content (blank strings)

This makes it safe to run multiple times without re-converting already processed records.

### Workflow Integration

**Typical workflow:**
1. **Webhook creates session** → Status: "ready_for_review"
2. **Run converter** → Converts markdown to SmartDoc
3. **Status updated** → "complete"
4. **Manual review** (optional) → Change to other statuses as needed

**Recommended approach for first time:**
```bash
# Test with dry run
bin/convert_markdown_sessions --dry-run --limit 5

# Convert small batch
bin/convert_markdown_sessions --limit 10

# Check results in SmartSuite UI
# If OK, convert all
bin/convert_markdown_sessions
```

**Regular maintenance:**
```bash
# Run periodically to convert new webhook sessions
bin/convert_markdown_sessions
```

### Performance

**Token Efficiency:**
- Record identification: ~100-500 tokens (IDs + titles only, cached when possible)
- Content fetching: Direct API (0 AI tokens)
- Conversion: Local Ruby code (0 AI tokens)
- Update: Direct API (0 AI tokens)

**Time Estimate:**
- 100 records: ~30-60 seconds
- Depends on API latency and record size

---

## Implementation Details

### Snake_Case Type Names

SmartSuite uses **snake_case** for type names, not camelCase:

| Standard TipTap | SmartSuite |
|-----------------|------------|
| `bulletList` | `bullet_list` |
| `orderedList` | `ordered_list` |
| `listItem` | `list_item` |
| `codeBlock` | `code_block` |
| `hardBreak` | `hard_break` |
| `tableRow` | `table_row` |
| `tableCell` | `table_cell` |
| `tableHeader` | `table_header` |
| `horizontalRule` | `horizontal_rule` |

### Code Block Line Breaks

Code blocks use `hard_break` nodes between lines:

```json
{
  "type": "code_block",
  "attrs": {
    "language": "ruby",
    "lineWrapping": true
  },
  "content": [
    {"type": "text", "text": "def hello"},
    {"type": "hard_break"},
    {"type": "text", "text": "  puts 'world'"},
    {"type": "hard_break"},
    {"type": "text", "text": "end"}
  ]
}
```

### Combined Marks

Multiple marks can be applied to a single text node:

```json
{
  "type": "text",
  "marks": [
    {"type": "strong"},
    {"type": "em"},
    {"type": "link", "attrs": {"href": "https://example.com"}}
  ],
  "text": "bold italic link"
}
```

---

## Examples

### Example 1: Ordered Lists

**Input:**
```markdown
1. First step
2. Second step
3. Third step
```

**Output:**
```json
{
  "type": "ordered_list",
  "attrs": {"order": 1},
  "content": [
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "First step"}]
        }
      ]
    },
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Second step"}]
        }
      ]
    },
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Third step"}]
        }
      ]
    }
  ]
}
```

### Example 2: Code Blocks

**Input:**
````markdown
```ruby
def hello
  puts 'world'
end
```
````

**Output:**
```json
{
  "type": "code_block",
  "attrs": {
    "language": "ruby",
    "lineWrapping": true
  },
  "content": [
    {"type": "text", "text": "def hello"},
    {"type": "hard_break"},
    {"type": "text", "text": "  puts 'world'"},
    {"type": "hard_break"},
    {"type": "text", "text": "end"}
  ]
}
```

### Example 3: Links

**Input:**
```markdown
Visit [our website](https://example.com) for more info.
```

**Output:**
```json
{
  "type": "paragraph",
  "content": [
    {"type": "text", "text": "Visit "},
    {
      "type": "text",
      "marks": [{"type": "link", "attrs": {"href": "https://example.com"}}],
      "text": "our website"
    },
    {"type": "text", "text": " for more info."}
  ]
}
```

### Example 4: Combined Formatting

**Input:**
```markdown
This is ***bold and italic*** text.
```

**Output:**
```json
{
  "type": "paragraph",
  "content": [
    {"type": "text", "text": "This is "},
    {
      "type": "text",
      "marks": [{"type": "strong"}, {"type": "em"}],
      "text": "bold and italic"
    },
    {"type": "text", "text": " text."}
  ]
}
```

### Example 5: Links with Formatting

**Input:**
```markdown
Check [**bold link**](https://example.com) here.
```

**Output:**
```json
{
  "type": "paragraph",
  "content": [
    {"type": "text", "text": "Check "},
    {
      "type": "text",
      "marks": [
        {"type": "strong"},
        {"type": "link", "attrs": {"href": "https://example.com"}}
      ],
      "text": "bold link"
    },
    {"type": "text", "text": " here."}
  ]
}
```

### Example 6: Horizontal Rules

**Input:**
```markdown
Before

---

After
```

**Output:**
```json
{
  "type": "doc",
  "content": [
    {"type": "paragraph", "content": [{"type": "text", "text": "Before"}]},
    {"type": "horizontal_rule"},
    {"type": "paragraph", "content": [{"type": "text", "text": "After"}]}
  ]
}
```

### Example 7: Complex Mixed Content

**Input:**
```markdown
# Project Summary

This is a paragraph with **bold** and *italic* text.

## Tasks

1. First task
2. Second task

## Code

```javascript
console.log('Hello');
```

---

Visit [SmartSuite](https://smartsuite.com) for more.
```

**Output Structure:**
- Heading level 1: "Project Summary"
- Paragraph with bold and italic formatting
- Heading level 2: "Tasks"
- Ordered list with 2 items
- Heading level 2: "Code"
- Code block (JavaScript)
- Horizontal rule
- Paragraph with link

---

## See Also

- [SmartDoc Format Reference](../smartdoc_examples.md) - Complete SmartDoc structure
- [API Documentation](../../lib/smartsuite/formatters/markdown_to_smartdoc.rb) - Implementation details
- [Bulk Operations Guide](../api/records.md#bulk-operations) - General bulk operations guide
