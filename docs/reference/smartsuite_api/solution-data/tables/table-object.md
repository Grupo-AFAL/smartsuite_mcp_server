# Table Object

## Example

```json
{
  "id": "63a1f65623aaf6bcb564b00b",
  "name": "Teams",
  "solution": "63a1f65523aaf6bcb564b00a",
  "slug": "teams",
  "status": "active",
  "structure": [
    {
      "slug": "name",
      "label": "Name",
      "field_type": "textfield",
      "params": { ... }
    }
  ],
  "primary_field": "name",
  "order": 100,
  "structure_layout": null,
  "show_all_reports_members": [],
  "fields_metadata": {},
  "permissions": {
    "level": "all_members",
    "members": [],
    "teams": []
  },
  "field_permissions": [],
  "first_created": {
    "by": "63a1f65723aaf6bcb564b1f1",
    "on": "2022-12-20T17:52:22.646000Z"
  },
  "settings": {
    "emails": false,
    "meeting_notes": false,
    "call_log": false
  }
}
```

## Object Literals

| Param                    | Type             | Nullable | Description                                             |
| ------------------------ | ---------------- | -------- | ------------------------------------------------------- |
| id                       | string           | No       | The unique Table Id.                                    |
| name                     | string           | No       | The Table (App) display name.                           |
| solution                 | string           | No       | The Id of the Table's Solution.                         |
| slug                     | string           | No       | The Table slug (SmartSuite internal use).               |
| status                   | string           | No       | The Table's status.                                     |
| structure                | array of objects | No       | Array of field objects.                                 |
| primary_field            | string           | No       | Slug of the Table's Title (Primary) field.              |
| order                    | number           | No       | Numeric order of the field, used in edit record layout. |
| structure_layout         | object           | Yes      |                                                         |
| show_all_reports_members | array            | No       |                                                         |
| fields_metadata          | object           | No       |                                                         |
| permissions              | object           | No       | Permissions Object.                                     |
| field_permissions        | array            | No       | Array of field permissions objects.                     |
| first_created            | object           | No       | First created object                                    |
| settings                 | object           | No       | Table settings object                                   |
