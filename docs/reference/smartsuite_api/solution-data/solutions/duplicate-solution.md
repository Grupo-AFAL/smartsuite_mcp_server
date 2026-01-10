# Duplicate Solution

**POST** `https://app.smartsuite.com/api/v1/solutions/duplicate/`

Duplicates a Solution to create a copy. Can copy to the same or different workspace.

## Request Body

| Param          | Type    | Optional | Description                                              |
| -------------- | ------- | -------- | -------------------------------------------------------- |
| solution_id    | string  | No       | The 8 character Id of the Solution to be copied.         |
| name           | string  | No       | The name of the new Solution.                            |
| from_workspace | string  | No       | The 8 character Id of the Workspace to copy from.        |
| to_workspace   | string  | No       | The 8 character Id of the Workspace to copy to.          |
| copy_records   | boolean | No       | true to copy records, false to create an empty Solution. |
| copy_comments  | boolean | No       | true to copy comments, false to ignore comments.         |

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/solutions/duplicate/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "solution_id": "{solution_id}",
    "name": "Test 1 Copy",
    "from_workspace": "snbvtl79",
    "to_workspace": "s25rfeyv",
    "copy_records": true,
    "copy_comments": true
  }'
```

## Response (200)

Empty Response Body

```json
{}
```
