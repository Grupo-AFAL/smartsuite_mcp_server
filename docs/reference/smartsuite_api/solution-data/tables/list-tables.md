# List Tables

**GET** `https://app.smartsuite.com/api/v1/applications/`

Lists all Tables (Apps) in the Workspace.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/applications/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Query Parameters

| Param    | Type   | Optional | Description                                                                                                                                                                                                             |
| -------- | ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| fields   | string | Yes      | Specifies a field slug to include in the response. This parameter can be repeated to add multiple fields. If at least one field is specified, the response will only contain fields referenced by the fields parameter. |
| solution | string | Yes      | Specifies a Solution Id to limit the returned Tables by.                                                                                                                                                                |

## Response Format

| Param     | Type                 | Optional | Description                                          |
| --------- | -------------------- | -------- | ---------------------------------------------------- |
| id        | string               | No       | The Id of the App.                                   |
| name      | string               | No       | The name of the App.                                 |
| solution  | string               | No       | The new App's Solution Id.                           |
| slug      | string               | No       | The slug value of the App (SmartSuite internal use). |
| order     | number               | No       | Number used for ordering app in list of Tables.      |
| structure | array of app objects | No       | An array of app objects.                             |

## Response

Returns an array of Table objects.
