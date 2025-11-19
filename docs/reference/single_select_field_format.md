# Single Select Field Format Reference

## Overview

Single select fields (`singleselectfield`) in SmartSuite require a specific format for their choices. This document provides the correct format to avoid display issues.

## Bug History

**Issue Found:** November 19, 2025
**Symptom:** Single select field dropdowns showed empty/invisible options
**Root Cause:** Choices were created with simple string values instead of UUIDs and missing color attributes

## Required Format

Each choice in a single select field MUST include:

1. **label** (string) - Display text shown to users
2. **value** (UUID string) - Unique identifier (must be a valid UUID)
3. **value_color** (hex string) - Color code in format `#RRGGBB`
4. **icon_type** (string) - Should be `"icon"` for standard display
5. **weight** (integer) - Priority/importance (typically `1`)

### Correct Example

```ruby
{
  "field_type" => "singleselectfield",
  "label" => "Priority",
  "params" => {
    "choices" => [
      {
        "label" => "Urgent",
        "value" => "28ed62aa-4338-434a-8cd4-3a58d0cfae89",  # UUID
        "value_color" => "#FF5757",                          # Hex color
        "icon_type" => "icon",
        "weight" => 1
      },
      {
        "label" => "High",
        "value" => "36ed4a25-b85a-4dd4-8d30-bbee39277333",
        "value_color" => "#FF9F43",
        "icon_type" => "icon",
        "weight" => 1
      },
      {
        "label" => "Normal",
        "value" => "23d71694-1ce9-4282-9958-bcf8e2140c34",
        "value_color" => "#FFC107",
        "icon_type" => "icon",
        "weight" => 1
      },
      {
        "label" => "Low",
        "value" => "0a62aa92-ab22-4035-9c71-9d3e4bc9f5a3",
        "value_color" => "#54D62C",
        "icon_type" => "icon",
        "weight" => 1
      }
    ]
  }
}
```

### Incorrect Example (Will Cause Bugs)

```ruby
{
  "field_type" => "singleselectfield",
  "label" => "Priority",
  "params" => {
    "choices" => [
      {
        "label" => "Urgent",
        "value" => "urgent"  # ❌ WRONG: Simple string instead of UUID
      },
      {
        "label" => "High",
        "value" => "high",
        "color" => "red"     # ❌ WRONG: "color" instead of "value_color", name instead of hex
      }
    ]
  }
}
```

## Common Color Codes

```ruby
SMARTSUITE_COLORS = {
  # Reds
  red:    '#FF5757',

  # Oranges/Yellows
  orange: '#FF9F43',
  yellow: '#FFC107',

  # Greens
  green:  '#54D62C',

  # Blues
  blue:   '#2196F3',

  # Purples
  purple: '#9C27B0',

  # Grays/Browns
  gray:   '#9E9E9E',
  brown:  '#795548'
}
```

## Symptoms of Incorrect Format

If choices are created without proper UUIDs and colors:

1. **Dropdown shows empty space** - Options exist but appear blank/invisible
2. **Edit view shows options** - When editing the field settings, options display correctly
3. **API returns choices** - The choices exist in the API response but don't render in UI

## Solution

When creating or updating single select fields via the MCP server:

1. **Always generate UUIDs** for each choice value using `SecureRandom.uuid`
2. **Always include value_color** with hex color code
3. **Always include icon_type** set to `"icon"`
4. **Always include weight** set to `1`

## Example Code

```ruby
require 'securerandom'

choices = [
  {
    "label" => "Critical",
    "value" => SecureRandom.uuid,
    "value_color" => "#FF5757",
    "icon_type" => "icon",
    "weight" => 1
  },
  {
    "label" => "Medium",
    "value" => SecureRandom.uuid,
    "value_color" => "#FF9F43",
    "icon_type" => "icon",
    "weight" => 1
  },
  {
    "label" => "Low",
    "value" => SecureRandom.uuid,
    "value_color" => "#54D62C",
    "icon_type" => "icon",
    "weight" => 1
  }
]
```

## References

- SmartSuite Field Types: `singleselectfield`, `statusfield`, `multipleselectfield`
- Related Issue: Table "Incidentes de Tecnología" (ID: 691d16fe6f3bee01a1c9fca9)
- Date Fixed: November 19, 2025
