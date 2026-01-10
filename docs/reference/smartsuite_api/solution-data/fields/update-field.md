# Update Field

**PUT** `https://app.smartsuite.com/api/v1/applications/[tableId]/change_field/`

Updates a field in the specified Table (App).

## Example Request

```bash
curl -X PUT https://app.smartsuite.com/api/v1/applications/646536cac79b49252b0f94f5/change_field/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "slug": "[Random 10 digit alphanumeric value]",
    "label": "[Field Name]",
    "field_type": "[Field Type]",
    "params": {
      [Field-Specific Parameters]
    }
  }'
```

## Path Parameters

| Param   | Type   | Description                                             |
| ------- | ------ | ------------------------------------------------------- |
| tableId | string | The Id of the Table (App) in which to update the field. |

## Request Body

| Param      | Type   | Optional | Description                           |
| ---------- | ------ | -------- | ------------------------------------- |
| slug       | string | No       | A random 10 digit alphanumeric value. |
| label      | string | No       | The field name.                       |
| field_type | string | No       | The field type.                       |
| params     | object | No       | field-specific parameters.            |
