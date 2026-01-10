# Attach File

**PATCH** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/[recordId]/`

Attaches a file referenced by URL to the specified field.

## Example Request

```bash
curl -X PATCH https://app.smartsuite.com/api/v1/applications/[tableId]/records/[recordId]/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "<file_field_slug>": ["https://picsum.photos/200/300"],
    "id": "record_id"
  }'
```

## Path Parameters

| Param    | Type   | Description                         |
| -------- | ------ | ----------------------------------- |
| tableId  | string | The field's Table (App) Id          |
| recordId | string | The record Id to attach the file to |

## Request Body

| Param      | Type   | Description                                          |
| ---------- | ------ | ---------------------------------------------------- |
| field_slug | string | Key is the field slug, value is the URL for the file |
| id         | string | The record id to update                              |

## Response Format

Returns the updated record object.
