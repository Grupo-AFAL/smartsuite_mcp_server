# Batch Markdown to SmartDoc Conversion

This guide explains how to use the `convert_markdown_sessions` script to efficiently convert multiple SmartSuite records from Markdown to SmartDoc format.

## Overview

The script is designed for scenarios where:
- Records are automatically generated with Markdown content (e.g., from webhooks)
- You need to convert them to SmartDoc format for proper rich text display
- You want to update their status after conversion
- You want to minimize AI token usage during the conversion process

## Use Case: Read.ai Webhook Sessions

The primary use case is converting session records from Read.ai webhooks:

1. **Initial state**: Records created via webhook with status "Generada automáticamente" (`ready_for_review`)
2. **Content format**: Markdown text in the `description` field
3. **Target state**: After conversion, status changes to "Contenido validado" (`complete`)
4. **Efficiency**: Script fetches record IDs via MCP/cache, then directly accesses API for content conversion

## Installation

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

**Important:** The `.conversion_config` file is gitignored and will not be committed to the repository. This keeps your personal SmartSuite table IDs and configuration private.

## Usage

### Basic Usage (With Configuration File)

```bash
# Convert records using .conversion_config settings
bin/convert_markdown_sessions

# Use a different config file
bin/convert_markdown_sessions --config my_custom_config.txt
```

The script automatically loads `.conversion_config` if it exists in the current directory.

### Dry Run (Preview Changes)

```bash
# See what would be converted without making changes
bin/convert_markdown_sessions --dry-run
```

### Test with Limited Records

```bash
# Convert only first 5 records
bin/convert_markdown_sessions --limit 5

# Dry run with 10 records
bin/convert_markdown_sessions --dry-run --limit 10
```

### Command-Line Overrides

You can override configuration file values with command-line options:

```bash
# Override status values
bin/convert_markdown_sessions \
  --from-status different_status \
  --to-status another_status

# Override content field
bin/convert_markdown_sessions --content-field different_field

# Override batch size
bin/convert_markdown_sessions --batch-size 50

# Use different table (all required params)
bin/convert_markdown_sessions \
  --table-id YOUR_TABLE_ID \
  --status-field YOUR_STATUS_FIELD \
  --from-status SOURCE_STATUS \
  --to-status TARGET_STATUS
```

### All Options

```bash
bin/convert_markdown_sessions --help
```

Options:
- `--table-id ID` - Table ID (default: Sesiones table)
- `--status-field SLUG` - Status field slug (default: s53394fc66)
- `--content-field SLUG` - Content field slug to convert (default: description)
- `--from-status VALUE` - Source status value (default: ready_for_review)
- `--to-status VALUE` - Target status value (default: complete)
- `--dry-run` - Preview changes without updating
- `--limit N` - Process only N records (for testing)
- `--batch-size N` - Bulk update batch size (default: 50)

## How It Works

### 1. Efficient Record Identification (Minimal Tokens)

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

### 2. Direct API Access for Content

```ruby
# Fetches full record content directly (no AI involvement)
full_records = record_ids.map { |id| client.get_record(table_id, id) }
```

### 3. Markdown to SmartDoc Conversion

```ruby
# Converts markdown text to SmartDoc format
markdown_text = record['description']['html'] || record['description']
smartdoc = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown_text)
```

### 4. Bulk Update in Batches

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

## Example Output

```
=== SmartSuite Markdown to SmartDoc Batch Converter ===
Table: 66983fdf0b865a9ad2b02a8d
Status: ready_for_review → complete
Content field: description
Mode: LIVE

Fetching record IDs with status 'ready_for_review'... found 87 records

Sample records to convert:
  - 692491d842526694cbfdea02: OPC1 / TD6 | CASCERMAR: Manejo de horas y registro...
  - 69249f0e86275466074237df: Check-In Transformación Digital
  - 6924a287fcac6a48c2e7d3cc: Entorno Fiscal 2026
  - 6924b0dfd4407779e3093857: Project STAR: Core Alignment
  - 6924bd0c3357498f13b871ae: Kick Off Seguridad y Gobernanza de Datos.
  ... and 82 more

Fetching full content for 87 records... done

Converting markdown to SmartDoc format...
  [1/87] ✓ 692491d842526694cbfdea02: OPC1 / TD6 | CASCERMAR: Manejo...
  [2/87] ✓ 69249f0e86275466074237df: Check-In Transformación Digital
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

## Smart Skipping

The script automatically skips records that:
1. Have no content (`nil`)
2. Already have SmartDoc format (content has `data` key)
3. Have empty content (blank strings)

This makes it safe to run multiple times without re-converting already processed records.

## Workflow Integration

### Typical Workflow

1. **Webhook creates session** → Status: "Generada automáticamente" (`ready_for_review`)
2. **Run converter** → Converts markdown to SmartDoc
3. **Status updated** → "Contenido validado" (`complete`)
4. **Manual review** (optional) → Change to other statuses as needed

### Recommended Approach

**First time:**
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

## Troubleshooting

### No records found

If no records are found with the specified status:
```bash
# Check what status values exist
# Use MCP or check SmartSuite UI
```

### Conversion errors

The script shows individual conversion errors:
```
[42/87] ERROR 6924...: unexpected format in content
```

Check the record manually in SmartSuite to debug.

### Batch update failures

If bulk update fails, the script shows which batch failed. You can:
1. Reduce batch size: `--batch-size 10`
2. Check API rate limits
3. Verify record IDs are valid

## Performance

**Token Efficiency:**
- Record identification: ~100-500 tokens (IDs + titles only, cached when possible)
- Content fetching: Direct API (0 AI tokens)
- Conversion: Local Ruby code (0 AI tokens)
- Update: Direct API (0 AI tokens)

**Time Estimate:**
- 100 records: ~30-60 seconds
- Depends on API latency and record size

## Advanced Usage

### Convert Multiple Tables

Create a shell script to batch process multiple tables:

```bash
#!/bin/bash
# convert_all_sessions.sh

# Sesiones table
bin/convert_markdown_sessions

# Another table with different config
bin/convert_markdown_sessions \
  --table-id ANOTHER_TABLE_ID \
  --content-field different_field \
  --from-status pending \
  --to-status processed
```

### Scheduled Conversion

Use cron to run periodically:

```cron
# Run every hour to convert new webhook sessions
0 * * * * cd /path/to/smartsuite_mcp && bin/convert_markdown_sessions >> logs/conversion.log 2>&1
```

## Status Field Values Reference

For the "Sesiones" table (`s53394fc66` - Estado autogeneración):

| Label | Value | Description |
|-------|-------|-------------|
| Generada manualmente | `in_progress` | Manually created session |
| Generada automáticamente | `ready_for_review` | Auto-generated (webhook) |
| Dudas en contenido | `BGYfu` | Questions about content |
| Contenido validado | `complete` | Content validated |

## See Also

- [Markdown to SmartDoc Converter](../../lib/smartsuite/formatters/markdown_to_smartdoc.rb) - Core conversion logic
- [SmartDoc Format Reference](../smartdoc_examples.md) - SmartDoc structure documentation
- [Bulk Operations Guide](bulk-operations.md) - General bulk operations guide
