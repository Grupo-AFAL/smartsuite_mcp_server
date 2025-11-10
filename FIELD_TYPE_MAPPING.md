# SmartSuite to SQLite Field Type Mapping

## Overview

This document provides a comprehensive mapping of all 45+ SmartSuite field types to SQLite column types and storage strategies for the caching layer.

**Source:** SmartSuite Developer Documentation - Field Types and Properties
**URL:** https://developers.smartsuite.com/docs/solution-data/fields/field-types

---

## Mapping Strategy

### SQLite Type Selection Criteria

1. **Simple types** (text, number, boolean) → Native SQLite types (TEXT, REAL, INTEGER)
2. **Complex objects** → TEXT with JSON encoding
3. **Arrays** → TEXT with JSON encoding
4. **Dates** → INTEGER (Unix timestamp for querying) + original JSON in separate column if needed
5. **System fields** → Native types where possible, read-only marked

### Indexing Strategy

- ✅ **Always index**: Status, dates, assigned_to, primary fields
- 🟡 **Conditionally index**: Single-select, tags, yes/no (if commonly filtered)
- ❌ **Don't index**: Large JSON objects, text areas, rich content

---

## System Field Formats (9 types)

### 1. Auto Number
**SmartSuite Type:** `autonumber`
**Data Format:** `number`
**SQLite Type:** `INTEGER`
**Storage:** Direct value
**Indexed:** ❌ No (auto-incrementing, less useful for filtering)
**Read-Only:** ✅ Yes

```sql
autonumber INTEGER
```

**Example:**
```json
"autonumber": 1
```

---

### 2. Record Id
**SmartSuite Type:** `record_id` (system field)
**Data Format:** `string`
**SQLite Type:** `TEXT`
**Storage:** Direct value (this is the primary key `id`)
**Indexed:** ✅ Yes (PRIMARY KEY)
**Read-Only:** ✅ Yes

```sql
id TEXT PRIMARY KEY  -- Record ID is the table primary key
```

**Example:**
```json
"record_id": "6455294a7715e71aecd9c56a"
```

**Note:** This is typically stored as the `id` column in the cache table.

---

### 3. Application Slug
**SmartSuite Type:** `application_slug`
**Data Format:** `string`
**SQLite Type:** `TEXT`
**Storage:** Direct value (internal use)
**Indexed:** ❌ No
**Read-Only:** ✅ Yes

```sql
application_slug TEXT
```

---

### 4. Application Id
**SmartSuite Type:** `application_id`
**Data Format:** `string`
**SQLite Type:** `TEXT`
**Storage:** Store as `table_id` foreign key
**Indexed:** ✅ Yes (foreign key to tables)
**Read-Only:** ✅ Yes

```sql
table_id TEXT NOT NULL,
FOREIGN KEY (table_id) REFERENCES tables(id)
```

**Example:**
```json
"application_id": "6418cd08b64e448d78141297"
```

---

### 5. First Created
**SmartSuite Type:** `firstcreated` / `first_created`
**Data Format:** Object with `by` (user id) and `on` (datetime)
**SQLite Type:** `INTEGER` (timestamp) + `TEXT` (user id)
**Storage:** Separate columns for timestamp and user
**Indexed:** 🟡 Conditional (timestamp useful for sorting)

```sql
created_on INTEGER,
created_by TEXT
```

**Example:**
```json
"first_created": {
    "by": "63a1f65723aaf6bcb564b1f1",
    "on": "2023-05-05T16:05:37.529000Z"
}
```

**Extraction:**
```ruby
created_on = Time.parse(record['first_created']['on']).to_i
created_by = record['first_created']['by']
```

---

### 6. Followed By
**SmartSuite Type:** `followed_by`
**Data Format:** Array of user IDs
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array
**Indexed:** ❌ No

```sql
followed_by TEXT  -- JSON: ["user_id_1", "user_id_2"]
```

**Example:**
```json
"followed_by": ["63a1f65723aaf6bcb564b1f1", "63d43a8cab58a15ffdca6315"]
```

---

### 7. Last Updated
**SmartSuite Type:** `lastupdated` / `last_updated`
**Data Format:** Object with `by` (user id) and `on` (datetime)
**SQLite Type:** `INTEGER` (timestamp) + `TEXT` (user id)
**Storage:** Separate columns for timestamp and user
**Indexed:** ✅ Yes (timestamp frequently used for sorting recent records)

```sql
updated_on INTEGER,
updated_by TEXT,
CREATE INDEX idx_updated_on ON cache_records_xxx(updated_on);
```

**Example:**
```json
"last_updated": {
    "by": "63a1f65723aaf6bcb564b1f1",
    "on": "2023-05-05T16:05:37.529000Z"
}
```

---

### 8. Deleted Date
**SmartSuite Type:** `deleted_date`
**Data Format:** Object with `date` and `include_time`, plus `deleted_by` field
**SQLite Type:** `INTEGER` (timestamp, nullable) + `TEXT` (user id)
**Storage:** Separate columns, NULL if not deleted
**Indexed:** 🟡 Conditional (useful for filtering deleted records)

```sql
deleted_on INTEGER,  -- NULL if not deleted
deleted_by TEXT
```

**Example:**
```json
"deleted_date": {
    "date": "2023-05-09T19:58:59.089000Z",
    "include_time": true
},
"deleted_by": "63a1f65723aaf6bcb564b1f1"
```

---

### 9. Comments Count
**SmartSuite Type:** `comments_count`
**Data Format:** `int`
**SQLite Type:** `INTEGER`
**Storage:** Direct value
**Indexed:** ❌ No

```sql
comments_count INTEGER DEFAULT 0
```

**Example:**
```json
"comments_count": 0
```

---

## Text Field Formats (12 types)

### 10. Address
**SmartSuite Type:** `addressfield`
**Data Format:** Complex object with location fields
**SQLite Type:** `TEXT` (full JSON) + `TEXT` (concatenated address for search)
**Storage:** JSON for full object, `sys_root` for searchable text
**Indexed:** 🟡 Conditional (on concatenated address if commonly searched)

```sql
address_json TEXT,  -- Full JSON object
address_text TEXT   -- Concatenated searchable address
```

**Example:**
```json
{
    "location_address": "15549 West 166th Street",
    "location_city": "Olathe",
    "location_state": "Kansas",
    "location_zip": "66062",
    "location_country": "United States",
    "location_longitude": "-94.76601199999999",
    "location_latitude": "38.827365",
    "sys_root": "15549 West 166th Street, Olathe, Kansas, 66062, United States"
}
```

**Extraction:**
```ruby
address_json = record['address_field'].to_json
address_text = record['address_field']['sys_root']
```

---

### 11. Checklist
**SmartSuite Type:** `checklistfield`
**Data Format:** Complex object with items array
**SQLite Type:** `TEXT` (JSON) + `INTEGER` (completed count) + `INTEGER` (total count)
**Storage:** JSON for full data, denormalized counts for filtering
**Indexed:** 🟡 Conditional (on completion percentage)

```sql
checklist_json TEXT,  -- Full JSON
checklist_total INTEGER,
checklist_completed INTEGER
```

**Example:**
```json
{
    "items": [
        {
            "id": "483d963c-5454-4da0-a869-4043be0a4c69",
            "content": {...},
            "completed": true,
            "assignee": "63a1f65723aaf6bcb564b1f1",
            "due_date": "2023-05-10"
        }
    ],
    "total_items": 2,
    "completed_items": 1
}
```

---

### 12. Color Picker
**SmartSuite Type:** `colorpickerfield`
**Data Format:** Array of objects with `name` and `value` (hex)
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array
**Indexed:** ❌ No

```sql
colors TEXT  -- JSON: [{"name": "reddish", "value": "#814C4C"}]
```

---

### 13. Email
**SmartSuite Type:** `emailfield`
**Data Format:** Array of strings
**SQLite Type:** `TEXT` (JSON array) OR `TEXT` (first email only for single-value fields)
**Storage:** JSON array for multi-value, direct string for single-value
**Indexed:** 🟡 Conditional (if commonly searched)

```sql
-- For multi-value:
emails TEXT  -- JSON: ["peter@smartsuite.com", "peter.novosel@gmail.com"]

-- For single-value (denormalized):
email TEXT,  -- "peter@smartsuite.com"
emails_json TEXT  -- Full JSON array
```

**Example:**
```json
"email_field": ["peter@smartsuite.com", "peter.novosel@gmail.com"]
```

---

### 14. Full Name
**SmartSuite Type:** `fullnamefield`
**Data Format:** Object with title, first_name, middle_name, last_name, sys_root
**SQLite Type:** `TEXT` (full name) + `TEXT` (JSON for components)
**Storage:** `sys_root` for searchable name, JSON for full object
**Indexed:** 🟡 Conditional (on full name if commonly searched)

```sql
full_name TEXT,  -- "Mr. Peter N Novosel"
full_name_json TEXT  -- Full JSON object
```

**Example:**
```json
{
    "title": "1",
    "first_name": "Peter",
    "middle_name": "N",
    "last_name": "Novosel",
    "sys_root": "Mr. Peter N Novosel"
}
```

---

### 15. IP Address
**SmartSuite Type:** `ipaddressfield`
**Data Format:** Array of objects with `country_code` and `address`
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array
**Indexed:** ❌ No

```sql
ip_addresses TEXT  -- JSON array
```

---

### 16. Link
**SmartSuite Type:** `linkfield`
**Data Format:** Array of strings (URLs)
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array
**Indexed:** ❌ No

```sql
links TEXT  -- JSON: ["www.smartsuite.com", "www.google.com"]
```

---

### 17. Phone
**SmartSuite Type:** `phonefield`
**Data Format:** Array of objects with phone details
**SQLite Type:** `TEXT` (JSON array) OR `TEXT` (formatted first phone for single-value)
**Storage:** JSON array, optionally denormalize first phone
**Indexed:** 🟡 Conditional (on formatted phone if commonly searched)

```sql
phones TEXT,  -- Full JSON array
phone_primary TEXT  -- "+1 913 555 1212" (first phone, denormalized)
```

**Example:**
```json
[
    {
        "phone_country": "US",
        "phone_number": "913 555 1212",
        "phone_extension": "",
        "phone_type": 1,
        "sys_root": "19135551212",
        "sys_title": "+1 913 555 1212"
    }
]
```

---

### 18. Record Title (Primary Field)
**SmartSuite Type:** `title` (special field)
**Data Format:** `string`
**SQLite Type:** `TEXT`
**Storage:** Direct value (this is the main record title)
**Indexed:** ✅ Yes (frequently used for search and display)

```sql
title TEXT,
CREATE INDEX idx_title ON cache_records_xxx(title);
```

**Example:**
```json
"title": "My Record"
```

**Note:** Auto-generated titles are read-only.

---

### 19. SmartDoc
**SmartSuite Type:** `smartdocfield`
**Data Format:** Complex object with `data`, `html`, `preview`
**SQLite Type:** `TEXT` (preview) + `TEXT` (full JSON)
**Storage:** `preview` for searchable text, full JSON for rendering
**Indexed:** ❌ No (large content)

```sql
smartdoc_preview TEXT,  -- "Hello <strong>world</strong>"
smartdoc_json TEXT  -- Full JSON with data, html, preview
```

**Example:**
```json
{
    "data": {...},  // TipTap/ProseMirror format
    "html": "<div class=\"rendered\">\n    <p>Hello <strong>world</strong></p>\n</div>",
    "preview": "Hello <strong>world</strong>"
}
```

---

### 20. Social Network
**SmartSuite Type:** `socialnetworkfield`
**Data Format:** Object with usernames for different platforms
**SQLite Type:** `TEXT` (JSON object)
**Storage:** JSON-encoded object
**Indexed:** ❌ No

```sql
social_networks TEXT  -- JSON object
```

**Example:**
```json
{
    "facebook_username": "myuser",
    "twitter_username": "",
    "instagram_username": "",
    "linkedin_username": ""
}
```

---

### 21. Text Area
**SmartSuite Type:** `textarea`
**Data Format:** `string` (with `\n` for line breaks)
**SQLite Type:** `TEXT`
**Storage:** Direct value
**Indexed:** ❌ No (long content)

```sql
description TEXT
```

**Example:**
```json
"description": "test\n123\ntesting 1,2,3..."
```

**Note:** Use `\n` for line breaks.

---

### 22. Text
**SmartSuite Type:** `textfield`
**Data Format:** `string`
**SQLite Type:** `TEXT`
**Storage:** Direct value
**Indexed:** 🟡 Conditional (if commonly searched, like names, codes)

```sql
project_name TEXT
```

**Example:**
```json
"project_name": "Hello World!"
```

---

## Date Field Formats (6 types)

### 23. Date
**SmartSuite Type:** `datefield`
**Data Format:** Object with `date` (ISO format) and `include_time` (boolean)
**SQLite Type:** `INTEGER` (Unix timestamp)
**Storage:** Convert ISO date to Unix timestamp for efficient querying
**Indexed:** ✅ Yes (dates frequently used for filtering/sorting)

```sql
start_date INTEGER,  -- Unix timestamp
CREATE INDEX idx_start_date ON cache_records_xxx(start_date);
```

**Example:**
```json
{
    "date": "2023-05-09T06:00:00Z",
    "include_time": true
}
```

**Extraction:**
```ruby
start_date = Time.parse(record['date_field']['date']).to_i
```

---

### 24. Date Range
**SmartSuite Type:** `daterangefield`
**Data Format:** Object with `from_date` and `to_date` (date objects)
**SQLite Type:** `INTEGER` (from) + `INTEGER` (to)
**Storage:** Two separate timestamp columns
**Indexed:** ✅ Yes (both from and to dates)

```sql
date_range_from INTEGER,
date_range_to INTEGER,
CREATE INDEX idx_date_range_from ON cache_records_xxx(date_range_from);
CREATE INDEX idx_date_range_to ON cache_records_xxx(date_range_to);
```

**Example:**
```json
{
    "from_date": {
        "date": "2023-05-09T00:00:00Z",
        "include_time": false
    },
    "to_date": {
        "date": "2023-05-12T00:00:00Z",
        "include_time": false
    }
}
```

**Note:** SmartSuite docs mention date range fields can be referenced as `[field_slug].from_date` and `[field_slug].to_date`.

---

### 25. Due Date
**SmartSuite Type:** `duedatefield`
**Data Format:** Object with `from_date`, `to_date`, `is_overdue`, `status_is_completed`, `status_updated_on`
**SQLite Type:** `INTEGER` (from) + `INTEGER` (to) + `INTEGER` (boolean as 0/1) for overdue/completed
**Storage:** Separate columns for dates and status flags
**Indexed:** ✅ Yes (due date and overdue status frequently filtered)

```sql
due_date_from INTEGER,
due_date_to INTEGER,
due_date_is_overdue INTEGER,  -- 0 or 1
due_date_is_completed INTEGER,  -- 0 or 1
CREATE INDEX idx_due_date_to ON cache_records_xxx(due_date_to);
CREATE INDEX idx_due_date_is_overdue ON cache_records_xxx(due_date_is_overdue);
```

**Example:**
```json
{
    "from_date": {
        "date": null,
        "include_time": false
    },
    "to_date": {
        "date": "2023-05-12T00:00:00Z",
        "include_time": false
    },
    "is_overdue": false,
    "status_is_completed": false,
    "status_updated_on": "2023-05-09T19:25:04.981000Z"
}
```

---

### 26. Duration
**SmartSuite Type:** `durationfield`
**Data Format:** Number as string (duration in seconds)
**SQLite Type:** `REAL`
**Storage:** Convert string to numeric value
**Indexed:** 🟡 Conditional (if commonly used for filtering/sorting)

```sql
duration REAL  -- Duration in seconds
```

**Example:**
```json
"duration": "94530.0"
```

**Extraction:**
```ruby
duration = record['duration_field'].to_f
```

---

### 27. Time
**SmartSuite Type:** `timefield`
**Data Format:** String in 24-hour format (HH:MM:SS)
**SQLite Type:** `TEXT` OR `INTEGER` (seconds since midnight for easier comparison)
**Storage:** Store as text for display, or convert to seconds for querying
**Indexed:** 🟡 Conditional

```sql
-- Option 1: Store as text
meeting_time TEXT  -- "21:15:00"

-- Option 2: Store as seconds (better for range queries)
meeting_time_seconds INTEGER  -- 76500 (21:15:00 = 21*3600 + 15*60)
```

**Example:**
```json
"meeting_time": "21:15:00"
```

---

### 28. Time Tracking Log
**SmartSuite Type:** `timetrackingfield`
**Data Format:** Complex object with `time_track_logs` array and `total_duration`
**SQLite Type:** `TEXT` (JSON) + `REAL` (total duration)
**Storage:** JSON for full logs, denormalized total for querying
**Indexed:** 🟡 Conditional (on total_duration if tracking billable hours)

```sql
time_tracking_json TEXT,  -- Full JSON
time_tracking_total REAL  -- Total duration in seconds
```

**Example:**
```json
{
    "time_track_logs": [
        {
            "user_id": "63a1f65723aaf6bcb564b1f1",
            "date_time": "2023-05-09T19:46:16.751000Z",
            "duration": 45000,
            "note": "test note"
        }
    ],
    "total_duration": 69021
}
```

**Note:** Read-only field (not supported in bulk operations).

---

## Number Field Formats (7 types)

### 29. Currency
**SmartSuite Type:** `currencyfield`
**Data Format:** Number as string
**SQLite Type:** `REAL`
**Storage:** Convert string to float
**Indexed:** ✅ Yes (commonly filtered/sorted by amount)

```sql
revenue REAL,
CREATE INDEX idx_revenue ON cache_records_xxx(revenue);
```

**Example:**
```json
"revenue": "19.95"
```

**Extraction:**
```ruby
revenue = record['revenue'].to_f
```

---

### 30. Number
**SmartSuite Type:** `numberfield`
**Data Format:** Number as string
**SQLite Type:** `REAL`
**Storage:** Convert string to float
**Indexed:** 🟡 Conditional (depends on use case)

```sql
quantity REAL
```

**Example:**
```json
"quantity": "120"
```

---

### 31. Number Slider
**SmartSuite Type:** `numbersliderfield`
**Data Format:** `number`
**SQLite Type:** `REAL`
**Storage:** Direct numeric value
**Indexed:** 🟡 Conditional

```sql
priority_score REAL
```

**Example:**
```json
"priority_score": 59
```

**Note:** Value is clamped to min/max and rounded to increment.

---

### 32. Percent Complete
**SmartSuite Type:** `percentcompletefield`
**Data Format:** `number` (0-100)
**SQLite Type:** `REAL`
**Storage:** Direct numeric value
**Indexed:** 🟡 Conditional (useful for filtering incomplete tasks)

```sql
percent_complete REAL
```

**Example:**
```json
"percent_complete": 72
```

---

### 33. Percent
**SmartSuite Type:** `percentfield`
**Data Format:** Number as string
**SQLite Type:** `REAL`
**Storage:** Convert string to float
**Indexed:** 🟡 Conditional

```sql
completion_rate REAL
```

**Example:**
```json
"completion_rate": "42"
```

---

### 34. Rating
**SmartSuite Type:** `ratingfield`
**Data Format:** `number`
**SQLite Type:** `REAL`
**Storage:** Direct numeric value
**Indexed:** 🟡 Conditional (useful for filtering high/low ratings)

```sql
customer_rating REAL
```

**Example:**
```json
"customer_rating": 4
```

**Note:** Value is clamped to min/max.

---

### 35. Vote
**SmartSuite Type:** `votefield`
**Data Format:** Object with `total_votes` and `votes` array
**SQLite Type:** `INTEGER` (total votes) + `TEXT` (JSON for vote details)
**Storage:** Denormalized total for sorting, JSON for details
**Indexed:** 🟡 Conditional (on total_votes for popularity sorting)

```sql
vote_count INTEGER,
vote_details TEXT  -- JSON
```

**Example:**
```json
{
    "total_votes": 1,
    "votes": [
        {
            "user_id": "63a1f65723aaf6bcb564b1f1",
            "date": "2023-05-09"
        }
    ]
}
```

---

## List Field Formats (5 types)

### 36. Multiple Select
**SmartSuite Type:** `multipleselectfield`
**Data Format:** Array of strings (choice IDs)
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array of IDs
**Indexed:** ❌ No (JSON arrays not efficiently indexed in basic SQLite)

```sql
categories TEXT  -- JSON: ["120ed618-06bb-4acd-8880-05a0cea3e415", "1da865e2-48a6-4e1a-9158-de51cdf9f6b7"]
```

**Example:**
```json
"categories": [
    "120ed618-06bb-4acd-8880-05a0cea3e415",
    "1da865e2-48a6-4e1a-9158-de51cdf9f6b7"
]
```

**Querying:**
```sql
-- Check if array contains specific value
WHERE json_extract(categories, '$') LIKE '%"120ed618-06bb-4acd-8880-05a0cea3e415"%'
```

---

### 37. Single Select
**SmartSuite Type:** `singleselectfield`
**Data Format:** String (choice ID)
**SQLite Type:** `TEXT`
**Storage:** Direct string value (the choice ID)
**Indexed:** ✅ Yes (very commonly filtered)

```sql
priority TEXT,
CREATE INDEX idx_priority ON cache_records_xxx(priority);
```

**Example:**
```json
"priority": "ace70ec5-b046-4ba6-80b8-cf39b6390fd6"
```

**Note:** The value is the choice ID, not the label. Need table structure to map IDs to labels.

---

### 38. Status
**SmartSuite Type:** `statusfield`
**Data Format:** Object with `value` (status ID) and `updated_on` (datetime)
**SQLite Type:** `TEXT` (status value) + `INTEGER` (updated timestamp)
**Storage:** Separate columns for value and timestamp
**Indexed:** ✅ Yes (most commonly filtered field)

```sql
status TEXT,
status_updated_on INTEGER,
CREATE INDEX idx_status ON cache_records_xxx(status);
```

**Example:**
```json
{
    "value": "backlog",
    "updated_on": "2023-05-09T22:58:48.291000Z"
}
```

**Extraction:**
```ruby
status = record['status_field']['value']
status_updated_on = Time.parse(record['status_field']['updated_on']).to_i
```

---

### 39. Tag
**SmartSuite Type:** `tagfield`
**Data Format:** Array of strings (tag IDs)
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array of tag IDs
**Indexed:** 🟡 Conditional (if commonly filtered)

```sql
tags TEXT  -- JSON: ["645acfd07bb0b8858a01bf30", "645acfd07bb0b8858a01bf31"]
```

**Example:**
```json
"tags": [
    "645acfd07bb0b8858a01bf30",
    "645acfd07bb0b8858a01bf31"
]
```

**Note:** Tags can be private (solution-scoped) or public (account-scoped).

---

### 40. Yes / No
**SmartSuite Type:** `yesnofield`
**Data Format:** `boolean`
**SQLite Type:** `INTEGER` (0 or 1)
**Storage:** Direct boolean value as integer
**Indexed:** 🟡 Conditional (useful for filtering active/inactive)

```sql
is_active INTEGER  -- 0 = false, 1 = true
```

**Example:**
```json
"is_active": true
```

**Extraction:**
```ruby
is_active = record['is_active'] ? 1 : 0
```

---

## Reference Field Formats (3 types)

### 41. Assigned To
**SmartSuite Type:** `assignedtofield`
**Data Format:** Array of strings (user IDs) - always returns array even if single-value
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array
**Indexed:** 🟡 Conditional (commonly filtered to see "my tasks")

```sql
assigned_to TEXT  -- JSON: ["63a1f65723aaf6bcb564b1f1"]
```

**Example:**
```json
"assigned_to": ["63a1f65723aaf6bcb564b1f1"]
```

**Note:** Always returns an array, even for single-value configuration.

**Querying:**
```sql
-- Find records assigned to specific user
WHERE json_extract(assigned_to, '$') LIKE '%"63a1f65723aaf6bcb564b1f1"%'
```

---

### 42. Button
**SmartSuite Type:** `buttonfield`
**Data Format:** String (URL) or null
**SQLite Type:** `TEXT`
**Storage:** Direct string value (nullable)
**Indexed:** ❌ No

```sql
button_url TEXT  -- URL or NULL
```

**Example:**
```json
"button_url": "https://www.fakesite.com?id=test"
```

**Note:** Static URL buttons return null, dynamic buttons return generated URL.

---

### 43. Linked Record
**SmartSuite Type:** `linkedrecordfield`
**Data Format:** Array of strings (record IDs) - always returns array even if single-value
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array of record IDs
**Indexed:** ❌ No (foreign key relationships could be modeled but complex)

```sql
related_projects TEXT  -- JSON: ["6455294a7715e71aecd9c56a", "645c1dee9f83b887865d99ec"]
```

**Example:**
```json
"related_projects": [
    "6455294a7715e71aecd9c56a",
    "645c1dee9f83b887865d99ec"
]
```

**Note:** Always returns an array, even for single-value configuration.

---

## File Field Formats (2 types)

### 44. Files and Images
**SmartSuite Type:** `filesfield` / `imagesfield`
**Data Format:** Array of file objects with handle, metadata, etc.
**SQLite Type:** `TEXT` (JSON array)
**Storage:** JSON-encoded array
**Indexed:** ❌ No

```sql
attachments TEXT  -- JSON array of file objects
```

**Example:**
```json
[
    {
        "handle": "a4d988eCTCKZ62XMqUIj",
        "metadata": {
            "filename": "image (48).png",
            "mimetype": "image/png",
            "size": 51443
        },
        "file_type": "image",
        "created_on": "2023-05-11T15:15:37.263000Z"
    }
]
```

**Note:** Cannot attach files via API, use separate endpoint. This field is read-only in record operations.

---

### 45. Signature
**SmartSuite Type:** `signaturefield`
**Data Format:** Object with `text` (string or null) and `image_base64` (base64 string or null)
**SQLite Type:** `TEXT` (JSON object)
**Storage:** JSON-encoded (large if image)
**Indexed:** ❌ No

```sql
signature TEXT  -- JSON object
```

**Example:**
```json
{
    "text": null,
    "image_base64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAVgAAA..."
}
```

**Note:** Either `text` or `image_base64` is populated, not both.

---

## Summary Tables

### Field Type to SQLite Type Quick Reference

| SmartSuite Type | SQLite Type | Indexed? | Notes |
|-----------------|-------------|----------|-------|
| **System Fields** ||||
| autonumber | INTEGER | ❌ | Read-only |
| record_id | TEXT | ✅ PK | Primary key |
| application_id | TEXT | ✅ FK | Foreign key to tables |
| first_created | INTEGER + TEXT | 🟡 | Timestamp + user ID |
| followed_by | TEXT (JSON) | ❌ | Array of user IDs |
| last_updated | INTEGER + TEXT | ✅ | Timestamp + user ID |
| deleted_date | INTEGER + TEXT | 🟡 | Nullable, timestamp + user |
| comments_count | INTEGER | ❌ | Count |
| **Text Fields** ||||
| textfield | TEXT | 🟡 | Direct string |
| textarea | TEXT | ❌ | Long text |
| emailfield | TEXT (JSON) | 🟡 | Array of emails |
| phonefield | TEXT (JSON) | 🟡 | Array of phone objects |
| linkfield | TEXT (JSON) | ❌ | Array of URLs |
| addressfield | TEXT + TEXT | 🟡 | JSON + searchable text |
| fullnamefield | TEXT + TEXT | 🟡 | Full name + JSON |
| smartdocfield | TEXT + TEXT | ❌ | Preview + JSON |
| checklistfield | TEXT + INT + INT | 🟡 | JSON + counts |
| colorpickerfield | TEXT (JSON) | ❌ | Array of colors |
| ipaddressfield | TEXT (JSON) | ❌ | Array of IPs |
| socialnetworkfield | TEXT (JSON) | ❌ | Social usernames |
| **Date Fields** ||||
| datefield | INTEGER | ✅ | Unix timestamp |
| daterangefield | INTEGER + INTEGER | ✅ | From + to timestamps |
| duedatefield | INT + INT + INT + INT | ✅ | Dates + flags |
| durationfield | REAL | 🟡 | Seconds |
| timefield | TEXT or INTEGER | 🟡 | HH:MM:SS or seconds |
| timetrackingfield | TEXT + REAL | 🟡 | JSON + total |
| **Number Fields** ||||
| numberfield | REAL | 🟡 | Numeric |
| currencyfield | REAL | ✅ | Numeric |
| percentfield | REAL | 🟡 | Numeric |
| percentcompletefield | REAL | 🟡 | 0-100 |
| ratingfield | REAL | 🟡 | Numeric |
| numbersliderfield | REAL | 🟡 | Numeric |
| votefield | INTEGER + TEXT | 🟡 | Count + JSON |
| **List Fields** ||||
| singleselectfield | TEXT | ✅ | Choice ID |
| multipleselectfield | TEXT (JSON) | ❌ | Array of choice IDs |
| statusfield | TEXT + INTEGER | ✅ | Status + timestamp |
| tagfield | TEXT (JSON) | 🟡 | Array of tag IDs |
| yesnofield | INTEGER | 🟡 | 0 or 1 |
| **Reference Fields** ||||
| assignedtofield | TEXT (JSON) | 🟡 | Array of user IDs |
| linkedrecordfield | TEXT (JSON) | ❌ | Array of record IDs |
| buttonfield | TEXT | ❌ | URL or null |
| **File Fields** ||||
| filesfield/imagesfield | TEXT (JSON) | ❌ | Array of file objects |
| signaturefield | TEXT (JSON) | ❌ | Text or base64 image |

---

## Implementation Code

### Field Type Mapping Function

```ruby
# Map SmartSuite field types to SQLite column definitions
FIELD_TYPE_MAP = {
  # System fields
  'autonumber' => 'INTEGER',
  'record_id' => 'TEXT',  # Usually stored as 'id' PRIMARY KEY
  'application_slug' => 'TEXT',
  'application_id' => 'TEXT',
  'firstcreated' => 'INTEGER',  # created_on + created_by TEXT
  'followed_by' => 'TEXT',  # JSON
  'lastupdated' => 'INTEGER',  # updated_on + updated_by TEXT
  'deleted_date' => 'INTEGER',  # deleted_on + deleted_by TEXT
  'comments_count' => 'INTEGER',

  # Text fields
  'textfield' => 'TEXT',
  'textarea' => 'TEXT',
  'emailfield' => 'TEXT',  # JSON or first email
  'phonefield' => 'TEXT',  # JSON
  'linkfield' => 'TEXT',  # JSON
  'addressfield' => 'TEXT',  # JSON or sys_root
  'fullnamefield' => 'TEXT',  # sys_root
  'smartdocfield' => 'TEXT',  # preview
  'checklistfield' => 'TEXT',  # JSON
  'colorpickerfield' => 'TEXT',  # JSON
  'ipaddressfield' => 'TEXT',  # JSON
  'socialnetworkfield' => 'TEXT',  # JSON

  # Date fields
  'datefield' => 'INTEGER',
  'daterangefield' => 'INTEGER',  # Two columns: _from and _to
  'duedatefield' => 'INTEGER',  # Multiple columns
  'durationfield' => 'REAL',
  'timefield' => 'TEXT',
  'timetrackingfield' => 'TEXT',  # JSON

  # Number fields
  'numberfield' => 'REAL',
  'currencyfield' => 'REAL',
  'percentfield' => 'REAL',
  'percentcompletefield' => 'REAL',
  'ratingfield' => 'REAL',
  'numbersliderfield' => 'REAL',
  'votefield' => 'INTEGER',  # total_votes + vote_details TEXT

  # List fields
  'singleselectfield' => 'TEXT',
  'multipleselectfield' => 'TEXT',  # JSON
  'statusfield' => 'TEXT',  # value + updated_on INTEGER
  'tagfield' => 'TEXT',  # JSON
  'yesnofield' => 'INTEGER',

  # Reference fields
  'assignedtofield' => 'TEXT',  # JSON
  'linkedrecordfield' => 'TEXT',  # JSON
  'buttonfield' => 'TEXT',

  # File fields
  'filesfield' => 'TEXT',  # JSON
  'imagesfield' => 'TEXT',  # JSON
  'signaturefield' => 'TEXT',  # JSON
}

def get_sqlite_type(field_type)
  normalized_type = field_type.downcase.gsub(/field$/, '') + 'field'
  FIELD_TYPE_MAP[normalized_type] || 'TEXT'  # Default to TEXT for unknown types
end
```

### Column Name Sanitization

```ruby
def sanitize_column_name(field_slug)
  # SQLite column names: letters, digits, underscores only
  # Must start with letter or underscore
  # Reserved words should be avoided

  sanitized = field_slug.gsub(/[^a-zA-Z0-9_]/, '_').downcase

  # Ensure doesn't start with digit
  sanitized = "f_#{sanitized}" if sanitized =~ /^[0-9]/

  # Avoid SQLite reserved words
  reserved = %w[table column index select insert update delete where from join]
  sanitized = "field_#{sanitized}" if reserved.include?(sanitized)

  sanitized
end
```

### Index Creation Strategy

```ruby
def should_index_field?(field_info)
  field_type = field_info['field_type'].downcase

  # Always index these types
  always_index = %w[
    statusfield
    singleselectfield
    datefield
    duedatefield
    daterangefield
    currencyfield
    lastupdated
  ]

  return true if always_index.include?(field_type)

  # Conditionally index
  return true if field_info['params'] && field_info['params']['primary']
  return true if field_type == 'assignedtofield'
  return true if field_type == 'yesnofield'

  false
end
```

### Value Extraction for Complex Types

```ruby
def extract_field_value(field_slug, field_type, record_data)
  value = record_data[field_slug]
  return nil if value.nil?

  case field_type.downcase
  when 'datefield'
    Time.parse(value['date']).to_i
  when 'daterangefield'
    {
      from: value['from_date'] ? Time.parse(value['from_date']['date']).to_i : nil,
      to: value['to_date'] ? Time.parse(value['to_date']['date']).to_i : nil
    }
  when 'statusfield'
    {
      value: value['value'],
      updated_on: Time.parse(value['updated_on']).to_i
    }
  when 'firstcreated', 'lastupdated'
    {
      on: Time.parse(value['on']).to_i,
      by: value['by']
    }
  when 'numberfield', 'currencyfield', 'percentfield'
    value.to_f
  when 'yesnofield'
    value ? 1 : 0
  when 'addressfield'
    value['sys_root']  # Searchable concatenated address
  when 'fullnamefield'
    value['sys_root']  # Full formatted name
  when 'smartdocfield'
    value['preview']  # Text preview
  when 'checklistfield'
    {
      json: value.to_json,
      total: value['total_items'],
      completed: value['completed_items']
    }
  when 'votefield'
    {
      count: value['total_votes'],
      details: value.to_json
    }
  else
    # Default: JSON for complex types, direct value for simple types
    value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value
  end
end
```

---

## TTL Recommendations by Field Type

Based on mutation frequency:

### Long TTL (4-24 hours)
- **System fields** (read-only): first_created, record_id, autonumber
- **Static text**: addresses, full names, social networks
- **Rarely changing**: linked records, email, phone

### Medium TTL (1-4 hours)
- **Assignments**: assigned_to (changes periodically)
- **Status**: statusfield (updated regularly but not constantly)
- **Numbers**: currency, ratings (business data)

### Short TTL (5-30 minutes)
- **Activity tracking**: last_updated, followed_by
- **Progress**: percent_complete, checklist
- **Comments**: comments_count

### Very Short / No Cache (1-5 minutes)
- **Real-time**: time_tracking_log (active timers)
- **Volatile**: vote counts (if public voting)
- **Dynamic**: button fields (if URL changes frequently)

---

## Special Considerations

### 1. Read-Only Fields
These fields should not be included in INSERT/UPDATE operations:
- `autonumber`
- `record_id`
- `application_id`
- `first_created`
- `last_updated`
- `deleted_date`
- `comments_count`
- `timetrackingfield` (not supported in bulk operations)

### 2. Multi-Column Fields
These field types should be split into multiple SQL columns:
- `firstcreated` → `created_on INTEGER` + `created_by TEXT`
- `lastupdated` → `updated_on INTEGER` + `updated_by TEXT`
- `deleted_date` → `deleted_on INTEGER` + `deleted_by TEXT`
- `daterangefield` → `{field}_from INTEGER` + `{field}_to INTEGER`
- `statusfield` → `{field} TEXT` + `{field}_updated_on INTEGER`
- `duedatefield` → `{field}_from INTEGER` + `{field}_to INTEGER` + `{field}_is_overdue INTEGER`
- `addressfield` → `{field}_text TEXT` + `{field}_json TEXT` (optional)
- `checklistfield` → `{field}_json TEXT` + `{field}_total INTEGER` + `{field}_completed INTEGER` (optional)

### 3. JSON Array Querying
For fields stored as JSON arrays (assigned_to, linked_record, multiple_select, tags):

```sql
-- Check if array contains value
WHERE json_extract(assigned_to, '$') LIKE '%"user_123"%'

-- Check if array is empty or null
WHERE (assigned_to IS NULL OR json_array_length(assigned_to) = 0)

-- More robust JSON_EACH approach (SQLite 3.38+)
WHERE EXISTS (
  SELECT 1 FROM json_each(assigned_to)
  WHERE value = 'user_123'
)
```

### 4. Choice ID to Label Mapping
Fields like `singleselectfield`, `multipleselectfield`, and `statusfield` store choice IDs, not labels. The labels are stored in the table structure's `params.choices` array. Consider:
- Storing a `choice_labels` lookup table
- Or joining with the `fields` table metadata
- Or denormalizing commonly-used labels

### 5. Bulk Operation Limitations
Per SmartSuite docs, certain field types are not supported in bulk operations:
- Formula
- Count
- TimeTracking

These should be treated as read-only when present.

---

## Configurable TTL Implementation

Based on your feedback that TTL should be longer and configurable per table:

```ruby
# Default TTLs by field category (in seconds)
DEFAULT_TTLS = {
  system_readonly: 24 * 3600,  # 24 hours (read-only system fields)
  static_text: 12 * 3600,      # 12 hours (addresses, names, etc.)
  metadata: 6 * 3600,          # 6 hours (status, assignments)
  numbers: 4 * 3600,           # 4 hours (currency, ratings)
  activity: 1 * 3600,          # 1 hour (comments_count, followers)
  volatile: 15 * 60            # 15 minutes (time tracking, votes)
}

# Table-specific TTL configuration
TABLE_TTL_CONFIG = {
  'table_abc123' => 8 * 3600,   # 8 hours for this specific table
  'table_def456' => 2 * 3600    # 2 hours for frequently changing table
}

def get_record_ttl(table_id)
  # Check for table-specific override
  TABLE_TTL_CONFIG[table_id] || DEFAULT_TTLS[:metadata]
end
```

Store TTL configuration in the database:

```sql
CREATE TABLE cache_ttl_config (
  table_id TEXT PRIMARY KEY,
  ttl_seconds INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (table_id) REFERENCES tables(id)
);

-- Set custom TTL for a table
INSERT OR REPLACE INTO cache_ttl_config (table_id, ttl_seconds, updated_at)
VALUES ('table_abc123', 28800, strftime('%s', 'now'));  -- 8 hours
```

---

*Comprehensive Field Type Mapping v1.0*
*Based on SmartSuite Developer Documentation (2024)*
