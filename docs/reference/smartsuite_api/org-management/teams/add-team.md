# Add Team

**POST** `https://app.smartsuite.com/api/v1/teams/`

Creates a new Team. Responses are similar to List Records responses.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/teams/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "id": null,
    "name": "My New Team",
    "type": "2",
    "status": {
      "value": "1",
      "updated_on": null
    },
    "color": [
      {
        "value": "#0C41F3",
        "name": ""
      }
    ],
    "owners": ["63a1f65723aaf6bcb564b1f1"],
    "members": [],
    "first_created": null,
    "last_updated": null,
    "comments_count": 0,
    "followed_by": []
  }'
```

## Request Body

| Param          | Type             | Nullable | Description                                |
| -------------- | ---------------- | -------- | ------------------------------------------ |
| id             | string           | Yes      | Set value to null when adding team         |
| name           | string           | No       | Name of the new team. NOTE: Must be unique |
| type           | number           | No       | Always set this value to 2 (PUBLIC)        |
| status         | status object    | No       | Team status                                |
| color          | color object     | No       | Color associated with the team             |
| owners         | array of strings | No       | List of the team's owner ids               |
| members        | array of strings | No       | List of team members' ids                  |
| first_created  | date object      | Yes      | Set to null                                |
| last_updated   | date object      | Yes      | Set to null                                |
| comments_count | number           | No       | Set to 0                                   |
| followed_by    | array of strings | No       | List of follower ids (set to empty array)  |

## Status Object

| Param      | Type     | Description                            |
| ---------- | -------- | -------------------------------------- |
| value      | number   | Status value: ACTIVE = 1, INACTIVE = 2 |
| updated_on | ISO date | Date status last updated               |

## Color Object

| Param | Type   | Description                              |
| ----- | ------ | ---------------------------------------- |
| value | string | Hex color value associated with the Team |
| name  | string | Color name or ""                         |

## Response

Returns the created Team object.

```json
{
  "name": "My New Team",
  "color": [
    {
      "value": "#0C41F3"
    }
  ],
  "type": "2",
  "status": {
    "value": "1",
    "updated_on": "2024-06-12T15:37:31.904982Z"
  },
  "owners": ["63a1f65723aaf6bcb564b1f1"],
  "members": [],
  "first_created": {
    "on": "2024-06-12T15:37:31.881579Z",
    "by": "63a1f65723aaf6bcb564b1f1"
  },
  "last_updated": {
    "on": "2024-06-12T15:37:31.881652Z",
    "by": "63a1f65723aaf6bcb564b1f1"
  },
  "id": "6669c0bb3c4a0cff67a91a4c",
  "application_slug": "teams",
  "application_id": "63a1f65623aaf6bcb564b00b",
  "title": null,
  "comments_count": null,
  "autonumber": null,
  "ranking": {
    "default": "aamevqvtmm"
  },
  "deleted_date": {
    "date": null,
    "include_time": false
  },
  "deleted_by": null
}
```
