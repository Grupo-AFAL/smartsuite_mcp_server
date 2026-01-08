# Get Solution

**GET** `https://app.smartsuite.com/api/v1/solutions/[solutionId]/`

Retrieve the structure of a Solution.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/solutions/6451093119bcf22befaed847/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Path Parameters

| Param      | Type   | Description     |
| ---------- | ------ | --------------- |
| solutionId | string | The Solution Id |

## Response Format

Returns a Solution object.
