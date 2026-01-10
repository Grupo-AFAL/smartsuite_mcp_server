# Team Object

## Object Literals

| Param            | Type                 | Nullable | Description                                                                                                                    |
| ---------------- | -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------ |
| first_created    | first created object | No       | Date and user who created the Team record                                                                                      |
| last_updated     | last updated object  | No       | Date and user who last updated the Team record                                                                                 |
| application_id   | string               | No       | Id of Teams application                                                                                                        |
| ranking          | ranking object       | No       |                                                                                                                                |
| id               | string               | No       | Team's record id                                                                                                               |
| application_slug | string               | No       | Always set to teams                                                                                                            |
| deleted_date     | date object          | Yes      | Date Team was deleted                                                                                                          |
| name             | string               | No       | Name of the Team                                                                                                               |
| color            | color object         | No       | Color associated with the Team                                                                                                 |
| type             | number               | No       | Team's type: PUBLIC = 2 (Note: This value should always be 2 at this time. Additional values may be added in future releases.) |
| status           | team status object   | No       | Team status: ACTIVE = 1, INACTIVE = 2                                                                                          |
| owners           | array of strings     | No       | List of owner ids                                                                                                              |
| members          | array of strings     | No       | List of member ids                                                                                                             |

## Example

```json
{
  "first_created": {
    "by": "63a1f65723aaf6bcb564b1f1",
    "on": "2024-02-15T22:44:53.016000Z"
  },
  "last_updated": {
    "by": "63a1f65723aaf6bcb564b1f1",
    "on": "2024-02-20T20:29:00.715000Z"
  },
  "application_id": "63a1f65623aaf6bcb564b00b",
  "ranking": {
    "default": "aamevqverw"
  },
  "id": "65ce93e5e6bd79eeaf37045d",
  "application_slug": "teams",
  "deleted_date": {
    "date": null
  },
  "name": "Project Team: Website Project",
  "color": [
    {
      "value": "#0C41F3"
    }
  ],
  "type": "2",
  "status": {
    "value": "1",
    "updated_on": "2024-02-15T22:44:53.041000Z"
  },
  "owners": ["63a1f65723aaf6bcb564b1f1"],
  "members": [
    "64591b7288d2ea5cfc582944",
    "63a1f65723aaf6bcb564b1f1",
    "6495c857c7458025319a5f8d"
  ]
}
```
