# Get Record

**GET** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/[recordId]/`

Retrieve a single record from an App. Any "empty" fields (e.g. "", [], or false) in the record will not be returned.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/645109df887911e1871054b7/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Path Parameters

| Param    | Type   | Description        |
| -------- | ------ | ------------------ |
| tableId  | string | The Table (App) Id |
| recordId | string | The Record Id      |

## Query Parameters

| Param    | Type    | Optional | Description                                                |
| -------- | ------- | -------- | ---------------------------------------------------------- |
| hydrated | boolean | Yes      | Returns text labels for id-type fields. Defaults to false. |

## Hydrating the Record

To return human-readable values for certain fields, you can include the following query parameter:

```json
{ "hydrated": true }
```

Fields that will return additional information with this setting include:

- Single Select
- Multiple Select
- Status
- First Created
- Last Updated
- Assigned To
- Tags
- Vote
- Time Tracking Log
- Checklist
- Lookup

## Response

Returns a single record object.

## 200 Response - Example

```json
{
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
  "priority": "1",
  "sef1a6a113": {
    "from_date": {
      "date": "2021-09-01T00:00:00Z",
      "include_time": false
    },
    "to_date": {
      "date": "2021-09-03T00:00:00Z",
      "include_time": false
    }
  }
}
```
