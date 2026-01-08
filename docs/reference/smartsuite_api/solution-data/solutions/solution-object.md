# Solution Object

## Example

```json
{
  "name": "Untitled Solution 1",
  "slug": "s61az3ub",
  "logo_color": "#0C41F3",
  "logo_icon": "calendar",
  "description": {
    "data": {},
    "html": "",
    "preview": ""
  },
  "permissions": {
    "level": "all_members",
    "members": [],
    "teams": [],
    "owners": ["63a1f65723aaf6bcb564b1f1"]
  },
  "hidden": false,
  "created": "2023-05-05T21:11:14.165000Z",
  "created_by": "63a1f65723aaf6bcb564b1f1",
  "updated": "2023-05-05T21:11:14.165000Z",
  "updated_by": "63a1f65723aaf6bcb564b1f1",
  "has_demo_data": false,
  "status": "in_development",
  "automation_count": 0,
  "records_count": 0,
  "members_count": 7,
  "sharing_hash": "kmvtUH5B66",
  "sharing_password": null,
  "sharing_enabled": false,
  "sharing_allow_copy": false,
  "applications_count": 1,
  "last_access": "2023-05-15T16:04:45.652000Z",
  "id": "645570f23f026ab0fbd0f60c",
  "delete_date": null,
  "deleted_by": null,
  "template": null
}
```

## Object Literals

| Param              | Type     | Optional | Description                                                          |
| ------------------ | -------- | -------- | -------------------------------------------------------------------- |
| name               | string   | No       | The name of the Solution.                                            |
| slug               | string   | No       | Slug value of the Solution (Internal SmartSuite Use).                |
| logo_color         | string   | No       | The Solution color in hex.                                           |
| logo_icon          | string   | No       | The material design icon for the Solution.                           |
| description        | object   | Yes      | SmartDoc object containing the Solution Guide content.               |
| permissions        | object   | Yes      | Permissions object defining the permissions assigned to the Solution |
| hidden             | boolean  | Yes      | Whether the Solution is hidden from display.                         |
| created            | datetime | No       | ISO Date the Solution was created.                                   |
| created_by         | string   | No       | Member Id of the Solution creator.                                   |
| updated            | datetime | No       | ISO Date the Solution was last updated.                              |
| updated_by         | string   | No       | Member Id of the last updater.                                       |
| has_demo_data      | boolean  | Yes      | Toggles whether to show the demo data keep / remove options.         |
| status             | string   | Yes      | Legacy value - this is always set to "in_development"                |
| automation_count   | number   | Yes      | Number of configured automations in the Solution.                    |
| records_count      | number   | Yes      | Number of records in the Solution.                                   |
| members_count      | number   | Yes      | Number of Members with at least viewer access to the Solution.       |
| sharing_hash       | string   | Yes      | Hash used in constructing the Shared Solution URL.                   |
| sharing_password   | string   | Yes      | The passcode specified for a Shared Solution.                        |
| sharing_enabled    | boolean  | Yes      | True if Solution share is enabled.                                   |
| sharing_allow_copy | boolean  | Yes      | True if Shared Solution copy function is enabled.                    |
| applications_count | number   | Yes      | Number of active Apps in the Solution.                               |
| last_access        | datetime | No       | ISO Date the Solution was last accessed.                             |
| id                 | string   | No       | The Solution's Id.                                                   |
| delete_date        | datetime | Yes      | ISO Date the Solution was deleted. Null if not deleted.              |
| deleted_by         | string   | No       | Id of the Member who deleted the Solution. Null if not deleted.      |
| template           | string   | No       | Id of the Solution's template. Null if no template used.             |
