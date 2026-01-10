# List Comments

**GET** `https://app.smartsuite.com/api/v1/comments/?record=[Record_Id]`

Gets a record's comments. Returns an array of comment objects.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/comments/?record=640a385d0a86e2924f8dd382 \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Query Parameters

| Param       | Type   | Optional | Description                              |
| ----------- | ------ | -------- | ---------------------------------------- |
| record      | string | Yes      | Record id to retrieve comments for.      |
| application | string | Yes      | Table (App) id to retrieve comments for. |
| solution    | string | Yes      | Solution id to retrieve comments for.    |

> **Note:** Query parameters are optional, and serve to restrict the scope for returned comments. A GET made without any query parameters will return all comments for the Workspace.

## Response Format

| Param    | Type             | Description                       |
| -------- | ---------------- | --------------------------------- |
| count    | number           | Total number of records returned. |
| next     | number           | Next page token.                  |
| previous | number           | Previous page token.              |
| results  | Array of objects | Array of comment objects.         |

## 200 Response - Example

```json
{
  "count": null,
  "next": null,
  "previous": null,
  "results": [
    {
      "solution": "640a3811c9d3ea77099331e2",
      "application": "640a3811c9d3ea77099331e7",
      "record": "640a385d0a86e2924f8dd382",
      "member": "63a1f65723aaf6bcb564b1f1",
      "message": {
        "data": {...},
        "html": "<div class=\\"rendered\\">\\n <p>test</p>\\n</div>",
        "preview": "test"
      },
      "parent_comment": null,
      "created_on": "2023-03-20T12:49:05.832000Z",
      "deleted_on": null,
      "updated_on": null,
      "reactions": [],
      "key": 1,
      "assigned_to": null,
      "resolved_by": null,
      "followers": ["63a1f65723aaf6bcb564b1f1"],
      "type": "comment",
      "email": null,
      "id": "64185642174d214da05fa9c2"
    }
  ]
}
```
