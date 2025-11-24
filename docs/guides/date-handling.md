# Date Handling Guide

This guide explains how dates work in the SmartSuite MCP server, including how to read and write date values.

## Overview

SmartSuite stores all dates in UTC. The MCP server provides:

1. **Transparent date input** - Simple date strings are automatically converted to SmartSuite's format
2. **Local timezone output** - Dates are converted to your local timezone when reading

## Writing Dates

When creating or updating records, you can use simple date strings. The server automatically:
- Detects if the date includes a time component
- Converts any timezone to UTC
- Sets the appropriate `include_time` flag

### Supported Input Formats

| Format | Example | Result |
|--------|---------|--------|
| Date only | `"2025-06-20"` | Date without time |
| Date with slashes | `"2025/06/20"` | Date without time |
| UTC datetime | `"2025-06-20T14:30:00Z"` | Date with time |
| Datetime no TZ | `"2025-06-20T14:30:00"` | Date with time (assumes UTC) |
| Space format | `"2025-06-20 14:30"` | Date with time (assumes UTC) |
| With timezone | `"2025-06-20T14:30:00-07:00"` | Date with time (converted to UTC) |

### Examples

#### Simple date field (datefield)

```json
{
  "fecha": "2025-06-20"
}
```

#### Date with time

```json
{
  "fecha": "2025-06-20T14:30:00Z"
}
```

#### Due date field (duedatefield)

```json
{
  "due_date": {
    "from_date": "2025-06-20",
    "to_date": "2025-06-25T17:00:00Z"
  }
}
```

#### Date range field (daterangefield)

```json
{
  "date_range": {
    "from_date": "2025-06-01",
    "to_date": "2025-06-30"
  }
}
```

#### With timezone offset

```json
{
  "meeting_time": "2025-06-20T17:00:00-07:00"
}
```

This will be converted to `2025-06-21T00:00:00Z` (midnight UTC next day).

## Reading Dates

When listing records, dates are returned in your local timezone:

- **Date-only fields** return just the date: `"2025-06-20"`
- **Datetime fields** return date and time with timezone: `"2025-06-20 07:30:00 -0700"`

### Example Response

```yaml
records:
  - title: Sample Record
    due_date:
      from_date: "2025-08-15 02:00:00 -0700"
      to_date: 2025-08-20
      is_overdue: false
      is_completed: false
    fecha: 2025-09-10
    date_range:
      from_date: "2025-10-01 01:30:00 -0700"
      to_date: 2025-10-15
```

## Timezone Configuration

The server uses your system's local timezone by default. You can configure this:

### Environment Variable

```bash
export SMARTSUITE_TIMEZONE=America/Mexico_City
```

### Supported Values

- Named timezones: `America/New_York`, `Europe/London`, `Asia/Tokyo`
- UTC offset: `+0500`, `-0300`, `+05:30`
- Special values: `utc`, `local`, `system`

## Best Practices

1. **Use date-only for calendar dates** - If you don't need a specific time, use `"2025-06-20"` format
2. **Use UTC for specific times** - When a specific moment matters, use `"2025-06-20T14:30:00Z"`
3. **Include timezone when relevant** - If the AI knows the user's timezone, include it: `"2025-06-20T14:30:00-07:00"`
4. **Let the server handle conversion** - Don't worry about `include_time` flags; the server infers them automatically

## Technical Details

### How Dates Are Stored

SmartSuite stores dates as:
```json
{
  "date": "2025-06-20T14:30:00Z",
  "include_time": true
}
```

The `include_time` flag determines whether the time component is displayed in the UI.

### Automatic Inference

The server infers `include_time` based on your input:

| Input | Inferred `include_time` |
|-------|------------------------|
| `"2025-06-20"` | `false` |
| `"2025-06-20T00:00:00Z"` | `false` (midnight = no time) |
| `"2025-06-20T14:30:00Z"` | `true` |
| `"2025-06-20 14:30"` | `true` |

### Timezone Conversion

All timezone offsets are converted to UTC before sending to SmartSuite:

```
Input:  2025-06-20T17:00:00-07:00  (5 PM Pacific)
Stored: 2025-06-21T00:00:00Z       (Midnight UTC next day)
```

When reading back, the server converts from UTC to your local timezone.
