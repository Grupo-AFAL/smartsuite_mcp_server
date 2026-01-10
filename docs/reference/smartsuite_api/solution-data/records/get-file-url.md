# Get File URL

**GET** `https://app.smartsuite.com/api/v1/shared-files/[fileHandle]/url/`

Returns a public URL to the specified file. Note that the URL lifetime is set to 20 years.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/shared-files/[fileHandle]/url/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Path Parameters

| Param      | Type   | Description                                                     |
| ---------- | ------ | --------------------------------------------------------------- |
| fileHandle | string | The file handle of the file you want to return a public URL for |

## Response Format

| Param | Type   | Optional | Description                |
| ----- | ------ | -------- | -------------------------- |
| url   | string | No       | The public URL to the file |

## Example Response

```json
{
  "url": "https://…"
}
```
