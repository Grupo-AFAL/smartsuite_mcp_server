# List Solutions

**GET** `https://app.smartsuite.com/api/v1/solutions/`

Lists all Solutions in the Workspace.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/solutions/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Query Parameters

| Param  | Type   | Optional | Description                                                                                                                                                                                                             |
| ------ | ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| fields | string | Yes      | Specifies a field slug to include in the response. This parameter can be repeated to add multiple fields. If at least one field is specified, the response will only contain fields referenced by the fields parameter. |

## Request Body

| Param  | Type          | Optional | Description                         |
| ------ | ------------- | -------- | ----------------------------------- |
| sort   | sort object   | Yes      | Object specifying sort parameters   |
| filter | filter object | Yes      | Object specifying filter parameters |

## Response Format

Returns an array of Solution objects.
