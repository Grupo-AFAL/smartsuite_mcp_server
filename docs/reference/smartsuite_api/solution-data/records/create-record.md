# Create Record

**POST** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/`

Creates a record in the specified App. Note that you must include any required fields in the POST or the system will return error code 422 "Invalid Request" - a detailed error message will be included in the response body.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/646536cac79b49252b0f94f5/records/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "title": "Record 1",
    "description": {
      "data": {},
      "html": "<div class=\\"rendered\\">\\n \\n</div>"
    },
    "assigned_to": [
      "5dd812b9d8b7863532d3ddd2",
      "5e6ec7dadc8a90f33bcb02c9"
    ],
    "status": {
      "value": "in_progress"
    },
    "due_date": {
      "from_date": {
        "date": "2021-09-03T03:00:00Z",
        "include_time": true
      },
      "to_date": {
        "date": "2021-09-04T03:15:00Z",
        "include_time": true
      },
      "is_overdue": false
    },
    "priority": "1"
  }'
```

## Read-Only Fields

The following SmartSuite Fields are system-generated, computed or set by aggregate user actions (ex. voting) and cannot be set via API:

- Auto Number
- Count
- First Created
- Formula
- Last Updated
- Record ID
- Rollup
- Vote

## Path Parameters

| Param   | Type   | Description                                              |
| ------- | ------ | -------------------------------------------------------- |
| tableId | string | The Id of the Table (App) in which to create the record. |

## Request Body

| Param         | Type   | Optional | Description                                                |
| ------------- | ------ | -------- | ---------------------------------------------------------- |
| record object | object | No       | A record object representing the new record to be created. |

## Response

Returns the created record object.
