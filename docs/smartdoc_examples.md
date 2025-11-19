# SmartDoc Field Format Reference

This document provides comprehensive examples of SmartDoc field structures for the SmartSuite API, validated against actual SmartSuite records.

## Overview

SmartDoc fields use TipTap/ProseMirror format with a `data` key containing the document structure. When creating or updating records with SmartDoc fields (like `richtextareafield`), you must provide the `data` structure, not HTML.

**Structure:**
- `data`: (Required) TipTap/ProseMirror document structure
- `html`: (Optional) Generated automatically by SmartSuite
- `preview`: (Optional) Generated automatically by SmartSuite

## Basic Structure

```json
{
  "data": {
    "type": "doc",
    "content": [
      // Array of content objects
    ]
  }
}
```

## Content Types

### 1. Paragraph (Plain Text)

```json
{
  "type": "paragraph",
  "attrs": {
    "textAlign": "left",
    "size": "medium"
  },
  "content": [
    {
      "type": "text",
      "text": "This is a plain paragraph."
    }
  ]
}
```

### 2. Headings

Levels 1-6 supported. UI-created headings include additional attributes:

```json
{
  "type": "heading",
  "attrs": {
    "level": 1,
    "id": "auto-generated-id",
    "collapse": false,
    "textAlign": null,
    "indentation": 0
  },
  "content": [
    { "type": "text", "text": "Heading 1" }
  ]
}
```

**Minimal version (for API creation):**
```json
{
  "type": "heading",
  "attrs": { "level": 1 },
  "content": [
    { "type": "text", "text": "Heading 1" }
  ]
}
```

### 3. Text Formatting Marks

Marks are inline formatting applied to text nodes. Multiple marks can be combined.

#### Bold Text

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [{ "type": "strong" }],
      "text": "Bold text"
    }
  ]
}
```

#### Italic Text

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [{ "type": "em" }],
      "text": "Italic text"
    }
  ]
}
```

#### Underline Text

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [{ "type": "underline" }],
      "text": "Underlined text"
    }
  ]
}
```

#### Strikethrough Text

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [{ "type": "strikethrough" }],
      "text": "Strikethrough text"
    }
  ]
}
```

#### Colored Text

Available colors: yellow, red, blue, brown, green, purple, pink, orange, gray, default

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [
        {
          "type": "color",
          "attrs": { "color": "red" }
        }
      ],
      "text": "Red text"
    }
  ]
}
```

#### Highlighted Text

Available highlight colors: yellow, red, blue, brown, green, purple, pink, orange, gray

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [
        {
          "type": "highlight",
          "attrs": { "color": "yellow" }
        }
      ],
      "text": "Highlighted text"
    }
  ]
}
```

#### Combining Multiple Marks

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "text": "This paragraph has "
    },
    {
      "type": "text",
      "marks": [
        { "type": "strong" },
        { "type": "underline" }
      ],
      "text": "bold and underlined"
    },
    {
      "type": "text",
      "text": " text."
    }
  ]
}
```

#### Links

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "text",
      "marks": [
        {
          "type": "link",
          "attrs": { "href": "https://example.com" }
        }
      ],
      "text": "Link text"
    }
  ]
}
```

### 4. Lists

#### Bullet List

```json
{
  "type": "bullet_list",
  "content": [
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "First item" }
          ]
        }
      ]
    },
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "Second item" }
          ]
        }
      ]
    }
  ]
}
```

#### Ordered List

```json
{
  "type": "ordered_list",
  "attrs": { "order": 1 },
  "content": [
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "Step 1" }
          ]
        }
      ]
    },
    {
      "type": "list_item",
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "Step 2" }
          ]
        }
      ]
    }
  ]
}
```

### 5. Checklist

```json
{
  "type": "check_list",
  "content": [
    {
      "type": "check_list_item",
      "attrs": { "checked": true },
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "Completed task" }
          ]
        }
      ]
    },
    {
      "type": "check_list_item",
      "attrs": { "checked": false },
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "Unchecked task" }
          ]
        }
      ]
    }
  ]
}
```

### 6. Code Block

Code blocks use `hard_break` nodes for line breaks:

```json
{
  "type": "code_block",
  "attrs": {
    "language": "javascript",
    "lineWrapping": true
  },
  "content": [
    { "type": "text", "text": "function example() {" },
    { "type": "hard_break" },
    { "type": "text", "text": "  return \"test\";" },
    { "type": "hard_break" },
    { "type": "text", "text": "}" }
  ]
}
```

Available languages: javascript, python, ruby, java, go, rust, php, typescript, sql, bash, etc.

### 7. Table

Tables have detailed cell attributes:

```json
{
  "type": "table",
  "content": [
    {
      "type": "table_row",
      "content": [
        {
          "type": "table_header",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "colwidth": null,
            "background": null
          },
          "content": [
            {
              "type": "paragraph",
              "attrs": { "textAlign": "left", "size": "medium" },
              "content": [
                { "type": "text", "text": "Column 1" }
              ]
            }
          ]
        },
        {
          "type": "table_header",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "colwidth": null,
            "background": null
          },
          "content": [
            {
              "type": "paragraph",
              "attrs": { "textAlign": "left", "size": "medium" },
              "content": [
                { "type": "text", "text": "Column 2" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "table_row",
      "content": [
        {
          "type": "table_cell",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "colwidth": null,
            "background": null
          },
          "content": [
            {
              "type": "paragraph",
              "attrs": { "textAlign": "left", "size": "medium" },
              "content": [
                { "type": "text", "text": "Cell 1" }
              ]
            }
          ]
        },
        {
          "type": "table_cell",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "colwidth": null,
            "background": null
          },
          "content": [
            {
              "type": "paragraph",
              "attrs": { "textAlign": "left", "size": "medium" },
              "content": [
                { "type": "text", "text": "Cell 2" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

### 8. Images

Images require file handle from SmartSuite's file system:

```json
{
  "type": "image",
  "attrs": {
    "file": {
      "handle": "file-handle-from-smartsuite",
      "metadata": {
        "container": "smart-suite-media",
        "filename": "image.png",
        "key": "storage-key",
        "mimetype": "image/png",
        "size": 8952
      },
      "transform_options": {},
      "author": 41226,
      "security": {
        "policy": "base64-encoded-policy",
        "signature": "security-signature"
      },
      "file_type": "image",
      "icon": "image",
      "video_conversion_status": "none",
      "video_thumbnail_handle": "",
      "converted_video_handle": null
    },
    "alignment": "left",
    "size": {
      "width": 400
    },
    "caption": "Image caption"
  }
}
```

### 9. Attachments

Attachments use similar file structure to images:

```json
{
  "type": "attachment",
  "attrs": {
    "file": {
      "handle": "file-handle-from-smartsuite",
      "metadata": {
        "container": "smart-suite-media",
        "filename": "document.pdf",
        "key": "storage-key",
        "mimetype": "application/pdf",
        "size": 1024
      },
      "transform_options": {},
      "author": 41226,
      "security": {
        "policy": "base64-encoded-policy",
        "signature": "security-signature"
      },
      "file_type": "other",
      "icon": "file",
      "video_conversion_status": "none",
      "video_thumbnail_handle": "",
      "converted_video_handle": null
    }
  }
}
```

### 10. Mentions

#### Record Mention (Link to another record)

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "mention",
      "attrs": {
        "id": "record-id",
        "application": {
          "id": "application-id",
          "name": "Application Name",
          "slug": "app-slug"
        },
        "title": "Record Title",
        "prefix": "#"
      }
    },
    { "type": "text", "text": " " }
  ]
}
```

#### Member Mention (@ mention)

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    {
      "type": "mention",
      "attrs": {
        "id": "member-id",
        "application": {
          "id": "members-app-id",
          "name": "Members",
          "slug": "members"
        },
        "title": "Member Name",
        "prefix": "@"
      }
    },
    { "type": "text", "text": " " }
  ]
}
```

### 11. Horizontal Rule (Divider)

```json
{
  "type": "horizontal_rule"
}
```

### 12. Callouts

Available callout types: info, warning, success, error

```json
{
  "type": "callout",
  "attrs": {
    "type": "info"
  },
  "content": [
    {
      "type": "paragraph",
      "attrs": { "textAlign": "left", "size": "medium" },
      "content": [
        { "type": "text", "text": "This is an info callout" }
      ]
    }
  ]
}
```

### 13. Emojis

Emojis are regular text nodes:

```json
{
  "type": "paragraph",
  "attrs": { "textAlign": "left", "size": "medium" },
  "content": [
    { "type": "text", "text": "😃 👍 ✨" }
  ]
}
```

## Complete Example

Here's a complete SmartDoc with multiple content types:

```json
{
  "data": {
    "type": "doc",
    "content": [
      {
        "type": "heading",
        "attrs": { "level": 1 },
        "content": [{ "type": "text", "text": "Project Summary" }]
      },
      {
        "type": "paragraph",
        "attrs": { "textAlign": "left", "size": "medium" },
        "content": [
          { "type": "text", "text": "This project aims to " },
          {
            "type": "text",
            "marks": [{ "type": "strong" }],
            "text": "improve user experience"
          },
          { "type": "text", "text": " across all platforms." }
        ]
      },
      {
        "type": "heading",
        "attrs": { "level": 2 },
        "content": [{ "type": "text", "text": "Key Features" }]
      },
      {
        "type": "bullet_list",
        "content": [
          {
            "type": "list_item",
            "content": [
              {
                "type": "paragraph",
                "attrs": { "textAlign": "left", "size": "medium" },
                "content": [{ "type": "text", "text": "Enhanced navigation" }]
              }
            ]
          },
          {
            "type": "list_item",
            "content": [
              {
                "type": "paragraph",
                "attrs": { "textAlign": "left", "size": "medium" },
                "content": [{ "type": "text", "text": "Faster load times" }]
              }
            ]
          }
        ]
      },
      {
        "type": "callout",
        "attrs": { "type": "info" },
        "content": [
          {
            "type": "paragraph",
            "attrs": { "textAlign": "left", "size": "medium" },
            "content": [
              { "type": "text", "text": "Important: Review the " },
              {
                "type": "text",
                "marks": [{ "type": "link", "attrs": { "href": "https://docs.example.com" }}],
                "text": "documentation"
              }
            ]
          }
        ]
      },
      {
        "type": "horizontal_rule"
      }
    ]
  }
}
```

## Usage in API Calls

When creating or updating a record with a SmartDoc field:

```json
{
  "title": "My Record",
  "description": {
    "data": {
      "type": "doc",
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": "left", "size": "medium" },
          "content": [
            { "type": "text", "text": "Your content here" }
          ]
        }
      ]
    }
  }
}
```

## Important Notes

- Always wrap content in a `data` object with `type: "doc"`
- `html` and `preview` fields are auto-generated - don't include them when creating/updating
- Paragraphs should include `attrs` with `textAlign` and `size`
- Lists must wrap text in paragraphs within list_item
- **Bold uses `"type": "strong"`, NOT `"type": "bold"`**
- **Italic uses `"type": "em"`, NOT `"type": "italic"`**
- Multiple marks can be combined on a single text node
- Images and attachments require file handles from SmartSuite's file system
- Code blocks use `hard_break` nodes for line breaks
- Mentions can reference records (prefix: "#") or members (prefix: "@")
- Callout types: info, warning, success, error
- Available text colors: yellow, red, blue, brown, green, purple, pink, orange, gray, default
- Available highlight colors: yellow, red, blue, brown, green, purple, pink, orange, gray

## Reference

All examples validated against actual SmartSuite records. See `/Users/fede/code/ruby/smartsuite_mcp/docs/smartdoc_complete_reference.json` for complete structure with all content types.
