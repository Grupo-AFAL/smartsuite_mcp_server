# Validate Solution Name

**POST** `https://app.smartsuite.com/api/v1/solutions/validate_name_uniqueness/`

Validates the uniqueness of a potential new Solution name. This function should be called prior to creating a new Solution to verify that the Solution's name is unique within the target Workspace.

## Request Body

| Param | Type   | Optional | Description                            |
| ----- | ------ | -------- | -------------------------------------- |
| name  | string | No       | The proposed name of the new Solution. |

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/solutions/validate_name_uniqueness/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "name": "Test 1"
  }'
```

## Response (200)

| Param     | Type    | Description                          |
| --------- | ------- | ------------------------------------ |
| is_unique | boolean | true if unique, false if not unique. |

## Example Response

```json
{
  "is_unique": true
}
```
