# Update Record

**PATCH or PUT** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/[recordId]/`

Updates a record in the specified App.

## Example Request

```bash
curl -X PATCH https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/645109df887911e1871054b7/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "title": "Record 1"
  }'
```

## Update Types

The update endpoint supports two types of record updates:

- **PUT request**: Performs a "destructive" update that clears all values that are not specified in the update
- **PATCH request**: Updates just those fields included in the request

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

| Param    | Type   | Description                                              |
| -------- | ------ | -------------------------------------------------------- |
| tableId  | string | The Id of the Table (App) in which to update the record. |
| recordId | string | The Id of the record to apply updates to.                |

## Request Body

| Param         | Type   | Optional | Description                                            |
| ------------- | ------ | -------- | ------------------------------------------------------ |
| record object | object | No       | A record object representing the fields to be updated. |

## Response

Returns the updated record object.
