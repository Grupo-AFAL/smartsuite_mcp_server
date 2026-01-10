# Field Types and Properties

This documents all of the currently supported SmartSuite field types and their corresponding value formats, as well as their option formats.

> **Notice:** We may add more field types in the future and this will not be considered a breaking change. API consumers are expected to handle unknown field types gracefully. Further, object definitions are not meant to exhaustively describe the shape, new properties can be added and will not be considered a breaking change.

## System Field Formats

### Auto Number

The automatically generated number associated with the record. These numbers are unique within the Table. Note that this is a system field and is read only.

**Type:** number

```json
"autonumber": 1
```

### Record Id

A field that displays the record id. Note that this is a system field and is read only.

**Type:** string

```json
"record_id": "6455294a7715e71aecd9c56a"
```

### Application Slug

The application slug is used internally by SmartSuite.

**Type:** string

```json
"application_slug": "s4o4zlr7"
```

### Application Id

A field that displays the record's Table (App) id. Note that this is a system field and is read only.

**Type:** string

```json
"application_id": "6418cd08b64e448d78141297"
```

### First Created

The record creator and created date and time. Note that this is a system field and is read only.

| Key | Type                   | Value                             |
| --- | ---------------------- | --------------------------------- |
| by  | string                 | Id of user who created the record |
| on  | Datetime in ISO format | Date record was created           |

```json
"first_created": {
  "by": "63a1f65723aaf6bcb564b1f1",
  "on": "2023-05-05T16:05:37.529000Z"
}
```

### Followed By

List of Members by Id who are following the record.

**Type:** array of strings

```json
"followed_by": []
```

### Last Updated

The user who last updated the record, and the date and time of the update. Note that this is a system field and is read only.

| Key | Type     | Value                                   |
| --- | -------- | --------------------------------------- |
| by  | string   | Id of user who updated the record       |
| on  | datetime | Datetime (in ISO format) of last update |

```json
"last_updated": {
  "by": "63a1f65723aaf6bcb564b1f1",
  "on": "2023-05-05T16:05:37.529000Z"
}
```

### Deleted Date

Date the record was deleted. Note that this is a system field and is read only. The "deleted_by" field is also set to the user id of the deleting user. Date property and deleted_by fields are null if not deleted.

| Key          | Type     | Value                                                         |
| ------------ | -------- | ------------------------------------------------------------- |
| date         | datetime | Date (ISO format) the record was deleted, null if not deleted |
| include_time | boolean  | This value is always true                                     |

```json
"deleted_date": {
  "date": "2023-05-09T19:58:59.089000Z",
  "include_time": true
},
"deleted_by": "63a1f65723aaf6bcb564b1f1"
```

### Comments Count

Count of the open comments for the record.

**Type:** int

```json
"comments_count": 0
```

## Text Field Formats

### Address

An address that can be displayed on a map.

| Key                | Type   | Value                       |
| ------------------ | ------ | --------------------------- |
| location_address   | string | Address line 1              |
| location_address2  | string | Address line 2              |
| location_city      | string | Name of City                |
| location_state     | string | Name of State               |
| location_zip       | string | Zip/postal code             |
| location_country   | string | Country                     |
| location_longitude | number | Address longitude           |
| location_latitude  | number | Address latitude            |
| sys_root           | string | Concatenated Address string |

```json
"sd27e602f7": {
  "location_address": "15549 West 166th Street",
  "location_address2": "",
  "location_city": "Olathe",
  "location_state": "Kansas",
  "location_zip": "66062",
  "location_country": "United States",
  "location_longitude": "-94.76601199999999",
  "location_latitude": "38.827365",
  "sys_root": "15549 West 166th Street, Olathe, Kansas, 66062, United States"
}
```

### Checklist

Manage a list of things that need to get done.

| Type            | Value  |
| --------------- | ------ |
| items           | array  |
| total_items     | number |
| completed_items | number |

Each item contains: id, content (with data, html, preview), completed, assignee, due_date, completed_at

```json
"s1e50979f6": {
  "items": [
    {
      "id": "483d963c-5454-4da0-a869-4043be0a4c69",
      "content": {
        "data": {...},
        "html": "<div class=\\"rendered\\">\\n <p>test</p>\\n</div>",
        "preview": "test"
      },
      "completed": true,
      "assignee": "63a1f65723aaf6bcb564b1f1",
      "due_date": "2023-05-10",
      "completed_at": "2023-05-09T16:21:03.892000Z"
    }
  ],
  "total_items": 2,
  "completed_items": 1
}
```

### Color Picker

Allow the selection of a color palette in HEX, RGB or CMYK formats.

**Type:** Array of objects

| Key   | Type   | Value                 |
| ----- | ------ | --------------------- |
| name  | string | Color name (optional) |
| value | string | Color hex value       |

```json
"s85fff4632": [
  {
    "name": "reddish",
    "value": "#814C4C"
  }
]
```

### Email

Allows a user to store email values. Allows to store multiple emails per field.

**Type:** Array of strings

```json
"sdd0608960": [
  "peter@smartsuite.com"
]
```

### Full Name

Capture a person's full name and title.

| Key         | Type   | Value                                |
| ----------- | ------ | ------------------------------------ |
| title       | number | 1 - Mr., 2 - Mrs., n - custom titles |
| first_name  | string | First Name                           |
| middle_name | string | Middle Name                          |
| last_name   | string | Last Name                            |
| sys_root    | string | Full (concatenated) name             |

```json
"sa60d0cace": {
  "title": "1",
  "first_name": "Peter",
  "middle_name": "N",
  "last_name": "Novosel",
  "sys_root": "Mr. Peter N Novosel"
}
```

### IP Address

Allows a user to store multiple IPv4/IPv6 values with country codes.

**Type:** array of objects

| Key          | Type   | Value                    |
| ------------ | ------ | ------------------------ |
| country_code | string | 2 character country code |
| address      | string | IPv4 or IPv6 address     |

```json
[
  {
    "country_code": "us",
    "address": "2001:0db8:11a3:09d7:1f34:8a2e:07a0:765d"
  }
]
```

### Link

Allows a user to store link values. Allow to store multiple links per field.

**Type:** Array of strings

```json
"s1a561b4ae": [
  "www.smartsuite.com"
]
```

### Phone

Add one or more formatted phone numbers.

| Key             | Type   | Value                                                |
| --------------- | ------ | ---------------------------------------------------- |
| phone_country   | string | Country code                                         |
| phone_number    | string | Phone number                                         |
| phone_extension | string | Extension                                            |
| phone_type      | number | 1 = office, 2 = mobile, 4 = home, 5 = fax, 8 = other |
| sys_root        | string | Unformatted phone number                             |
| sys_title       | string | Formatted phone number                               |

```json
"s4209c693e": [
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

### Record Title (Primary Field)

System field that contains the title of a record, also known as the primary field. Note that Record Titles that are set to Auto-Generated are read only.

**Type:** string

```json
"title": "My Record"
```

### SmartDoc

Create entire documents that combine free-form rich text, multimedia and much more.

| Key     | Type   | Value                                         |
| ------- | ------ | --------------------------------------------- |
| data    | object | SmartDoc Object                               |
| html    | string | HTML representation of the SmartDoc's content |
| preview | string | Text representation of the SmartDoc's content |

```json
"s325d95fa1": {
  "data": {
    "type": "doc",
    "content": [
      {
        "type": "paragraph",
        "attrs": { "textAlign": null },
        "content": [
          { "type": "text", "text": "Hello " },
          { "type": "text", "marks": [{ "type": "strong" }], "text": "world" }
        ]
      }
    ]
  },
  "html": "<div class=\\"rendered\\">\\n <p>Hello <strong>world</strong></p>\\n</div>",
  "preview": "Hello <strong>world</strong>"
}
```

### Social Network

Add links to one or more social networks.

| Key                | Type   | Value              |
| ------------------ | ------ | ------------------ |
| facebook_username  | string | Facebook username  |
| twitter_username   | string | Twitter username   |
| instagram_username | string | Instagram username |
| linkedin_username  | string | LinkedIn username  |

```json
"s284633643": {
  "facebook_username": "myuser",
  "twitter_username": "",
  "instagram_username": "",
  "linkedin_username": ""
}
```

### Text Area

Add text that can span multiple lines. Use `\\n` for line breaks.

**Type:** string

```json
"sa1dd2f880": "test\\n123\\ntesting 1,2,3..."
```

### Text

Add a single line of text like a name or a title.

**Type:** string

```json
"sa1dd2f880": "Hello World!"
```

## Date Field Formats

### Date

Add a date with an option to include time.

| Key          | Type     | Value                                   |
| ------------ | -------- | --------------------------------------- |
| date         | datetime | Date in ISO format                      |
| include_time | boolean  | Indicate whether time is to be included |

```json
"sb4c5ca5fc": {
  "date": "2023-05-09T06:00:00Z",
  "include_time": true
}
```

### Date Range

Add a date range.

| Key       | Type        | Value                      |
| --------- | ----------- | -------------------------- |
| from_date | date object | Starting date of the range |
| to_date   | date object | End date of the range      |

```json
"sd8f20e21a": {
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

### Due Date

Visually track and manage due dates.

| Key                 | Type        | Value                                                                     |
| ------------------- | ----------- | ------------------------------------------------------------------------- |
| from_date           | date object | Start date (optional)                                                     |
| to_date             | date object | Due date                                                                  |
| is_overdue          | boolean     | True if overdue (read-only)                                               |
| status_is_completed | boolean     | True if complete (read-only)                                              |
| status_updated_on   | datetime    | Date that the due date's linked status field was last updated (read-only) |

```json
"s1a23f61ca": {
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

### Duration

Track a time duration in days, hours and minutes. Duration values are in seconds.

**Type:** Number as text

```json
"s3031d9687": "94530.0"
```

### Time

Add a specific time. Time is reflected in 24 hour format.

**Type:** string

```json
"sff346911b": "21:15:00"
```

### Time Tracking Log

Track time spent working on a specific task or project.

| Key             | Type                      | Value                   |
| --------------- | ------------------------- | ----------------------- |
| time_track_logs | array of time log objects | Individual time entries |
| total_duration  | number                    | Total time in seconds   |

**Time Log Object:**

| Key        | Type              | Value                                          |
| ---------- | ----------------- | ---------------------------------------------- |
| user_id    | string            | Id of the Member associated with the log entry |
| date_time  | datetime          | Date and time of entry                         |
| duration   | number            | Duration in seconds                            |
| time_range | date range object | Time range for the event (nullable)            |
| note       | string            | Note text attached to the time entry           |

```json
"s09ca45598": {
  "time_track_logs": [
    {
      "user_id": "63a1f65723aaf6bcb564b1f1",
      "date_time": "2023-05-09T19:46:16.751000Z",
      "duration": 45000,
      "time_range": null,
      "timer_start": null,
      "note": "test note"
    }
  ],
  "total_duration": 69021
}
```

## Number Field Formats

### Currency

Add a number that is displayed with currency formatting.

**Type:** number as string

```json
"s584654fd2": "19.95"
```

### Number

Add a number with optional formatting.

**Type:** number as string

```json
"s6878322bd": "120"
```

### Number Slider

Select a number within a range using a numeric slider.

**Type:** number

```json
"s35edcfdbc": 59
```

### Percent Complete

Track a completion percentage using a graphical slider.

**Type:** number

```json
"sd5758e92c": 72
```

### Percent

Add a number that is displayed as a percentage.

**Type:** number as a string

```json
"s95338b75f": "42"
```

### Rating

Add a visual rating using a scale of your choice.

**Type:** number

```json
"s239cbad2a": 4
```

### Vote

Allow team members to vote on things like feature requests.

| Key         | Type                  | Value                      |
| ----------- | --------------------- | -------------------------- |
| total_votes | number                | Total votes for the record |
| votes       | array of vote objects | Individual votes           |

**Vote Object:**

| Key     | Type   | Value                                 |
| ------- | ------ | ------------------------------------- |
| user_id | string | Member Id of the voter                |
| date    | string | Date of the vote in YYYY-MM-DD format |

```json
"sacb0b6750": {
  "total_votes": 1,
  "votes": [
    {
      "user_id": "63a1f65723aaf6bcb564b1f1",
      "date": "2023-05-09"
    }
  ]
}
```

## List Field Formats

### Multiple Select

Add a list where multiple choices can be selected.

**Type:** array of strings (strings are the ids of individual list items)

```json
"s710a06b7f": [
  "120ed618-06bb-4acd-8880-05a0cea3e415",
  "1da865e2-48a6-4e1a-9158-de51cdf9f6b7"
]
```

### Single Select

Add a list where only one choice can be selected.

**Type:** string (id of the selected list item)

```json
"se799fd212": "ace70ec5-b046-4ba6-80b8-cf39b6390fd6"
```

### Status

Track the overall status of things like tasks, activities or projects.

| Key        | Type                   | Value                              |
| ---------- | ---------------------- | ---------------------------------- |
| value      | string                 | Id of the status value             |
| updated_on | Datetime in ISO format | Date Status field was last updated |

```json
"s63d179f79": {
  "value": "backlog",
  "updated_on": "2023-05-09T22:58:48.291000Z"
}
```

### Tag

Allows a user to select tags from the list of tags.

> **Note:** If a Tags Field is private, its tags are available to all private Tags Fields within a solution. If it's public, then every public field within an account can access its tags.

**Type:** array of strings (id of the selected tag)

```json
"sccb7d6601": [
  "645acfd07bb0b8858a01bf30",
  "645acfd07bb0b8858a01bf31"
]
```

### Yes / No

Field type that is used to represent a selected / non selected state.

**Type:** Boolean

```json
"s227a7b29a": true
```

## Reference Field Formats

### Assigned To

Assign a Member or Members to a record.

**Type:** array of strings

> **Note:** Assigned To fields configured for either single and multiple values return an array.

```json
"assigned_to": [
  "63a1f65723aaf6bcb564b1f1"
]
```

### Button

Create a button that triggers an action.

**Type:** string

> **Note:** Buttons configured with a static URL will always return null. Dynamic buttons will return the generated URL value.

```json
"s9d2ba74c3": "https://www.fakesite.com?id=test"
```

### Linked Record

Add a link to a record or records in another Table.

**Type:** array of strings

> **Note:** Linked Record fields configured for either single and multiple values return an array.

```json
"s570c86b38": [
  "6455294a7715e71aecd9c56a",
  "645c1dee9f83b887865d99ec"
]
```

## File Field Formats

### Files and Images

Get information about the files attached to a Files and Images field.

> **Note:** This endpoint cannot be used to attach files to the record.

**Type:** array of file objects

| Key               | Type     | Value                                                    |
| ----------------- | -------- | -------------------------------------------------------- |
| handle            | string   | The file handle                                          |
| metadata          | object   | File metadata (container, filename, key, mimetype, size) |
| transform_options | object   | Always empty, internal use                               |
| icon              | string   | Name of the SmartSuite icon                              |
| file_type         | string   | Short file type                                          |
| created_on        | ISO date | Date file was added                                      |
| updated_on        | ISO date | Date file was last updated                               |
| description       | string   | Reserved for future use                                  |

```json
"see6d6120d": [
  {
    "handle": "a4d988eCTCKZ62XMqUIj",
    "metadata": {
      "container": "smart-suite-media",
      "filename": "image (48).png",
      "key": "wK07pocQeibIB7oSWMya_image (48).png",
      "mimetype": "image/png",
      "size": 51443
    },
    "transform_options": {},
    "icon": "image",
    "file_type": "image",
    "created_on": "2023-05-11T15:15:37.263000Z",
    "updated_on": "2023-05-11T15:15:37.263000Z",
    "description": ""
  }
]
```

### Signature

| Key          | Type   | Value                                                           |
| ------------ | ------ | --------------------------------------------------------------- |
| text         | string | Text entered as signature. Empty string if signature was drawn. |
| image_base64 | string | Base64-encoded drawn image data, null if text was entered       |

```json
"s67210aeb8": {
  "text": null,
  "image_base64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA..."
}
```
