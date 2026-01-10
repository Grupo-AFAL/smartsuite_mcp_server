# Delete Record

**DELETE** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/[recordId]/`

Deletes a record.

## Example Request

```bash
curl -X DELETE https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/645109df887911e1871054b7/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID"
```

## Path Parameters

| Param    | Type   | Description                                         |
| -------- | ------ | --------------------------------------------------- |
| tableId  | string | The Id of the Table (App) that contains the record. |
| recordId | string | The Id of the record to delete.                     |
