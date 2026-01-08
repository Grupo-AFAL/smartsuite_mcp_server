# Bulk Add Records

**POST** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/bulk/`

Creates multiple records. Your request body should include an array (items) of up to 25 records. Each of those objects should be properly formed record objects.

> **Notice:** Including more than 25 records will result in the server returning a 422 error.

Note that the bulk endpoint does not currently enforce required fields and therefore does not return a 422 (as does the single record add) when a required field is missing.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/bulk/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "items": [
      {
        "title": "record 1",
        "description": "test"
      },
      {
        "title": "record 2",
        "description": "test2"
      },
      {
        "title": "record 3",
        "description": "test3"
      }
    ]
  }'
```

## Path Parameters

| Param   | Type   | Description                                               |
| ------- | ------ | --------------------------------------------------------- |
| tableId | string | The Id of the Table (App) in which to create the records. |

## Request Body

| Param | Type             | Optional | Description                |
| ----- | ---------------- | -------- | -------------------------- |
| items | array of objects | No       | An Array of record objects |

## Response

Returns an array of created record objects.
