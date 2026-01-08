# Get Table

**GET** `https://app.smartsuite.com/api/v1/applications/[tableId]/`

Retrieve the structure of a Table.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Path Parameters

| Param   | Type   | Description  |
| ------- | ------ | ------------ |
| tableId | string | The Table Id |

## Query Parameters

| Param  | Type   | Optional | Description                                                                                                                                                                                                             |
| ------ | ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| fields | string | Yes      | Specifies a field slug to include in the response. This parameter can be repeated to add multiple fields. If at least one field is specified, the response will only contain fields referenced by the fields parameter. |

## Response Format

Returns a Table object with full structure including all fields and their parameters.
