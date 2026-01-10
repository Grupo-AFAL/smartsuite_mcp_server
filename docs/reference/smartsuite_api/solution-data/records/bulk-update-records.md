# Bulk Update Records

**PATCH or PUT** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/bulk/`

Updates multiple records. Your request body should include an array (items) of up to 25 records. Each of those objects should be properly formed record objects and must include the record id.

> **Notice:** Including more than 25 records will result in the server returning a 422 error.

## Example Request

```bash
curl -X PATCH https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/bulk/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "items": [
      {
        "title": "record 1",
        "description": "test",
        "id": "646e62ac4a12462be0d6fb01"
      },
      {
        "title": "record 2",
        "description": "test2",
        "id": "646e62ac7e11a5a6aa50e6e5"
      },
      {
        "title": "record 3",
        "description": "test3",
        "id": "646e62ad5a47d462a9886b2e"
      }
    ]
  }'
```

## Update Types

- **PUT request**: Performs a "destructive" update that clears all values in all records that are not specified in the update
- **PATCH request**: Updates just those fields in all records included in the request

> **Important:** The record id must be included for each object passed to this endpoint in the items array.

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

| Param   | Type   | Description                                               |
| ------- | ------ | --------------------------------------------------------- |
| tableId | string | The Id of the Table (App) in which to update the records. |

## Request Body

| Param | Type             | Optional | Description                                            |
| ----- | ---------------- | -------- | ------------------------------------------------------ |
| items | array of objects | No       | An array of record objects (must include id for each). |

## Response

Returns an array of updated record objects.
