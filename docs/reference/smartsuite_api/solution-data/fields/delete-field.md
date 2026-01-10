# Delete Field

**POST** `https://app.smartsuite.com/api/v1/applications/[tableId]/delete_field/`

Deletes a field in the specified Table (App).

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/{tableId}/delete_field/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "slug": "due_date"
  }'
```

## Path Parameters

| Param   | Type   | Description                                             |
| ------- | ------ | ------------------------------------------------------- |
| tableId | string | The Id of the Table (App) in which to delete the field. |

## Request Body

| Param | Type   | Optional | Description                            |
| ----- | ------ | -------- | -------------------------------------- |
| slug  | string | No       | The slug value of the field to delete. |

## Response

200 Response - Returns the deleted field object
