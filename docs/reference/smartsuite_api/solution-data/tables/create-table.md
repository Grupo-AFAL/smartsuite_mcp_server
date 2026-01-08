# Create Table

**POST** `https://app.smartsuite.com/api/v1/applications/`

Creates a new Table (App). At least one field must be included in the structure object.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "name": "New Table",
    "solution": "645d47f8246b73b264b78a9a",
    "structure": [
      {
        "slug": "name",
        "label": "Name",
        "field_type": "textfield"
      }
    ]
  }'
```

## Request Body

| Param     | Type             | Optional | Description                          |
| --------- | ---------------- | -------- | ------------------------------------ |
| name      | string           | No       | The name of the Table.               |
| solution  | string           | No       | The new Table's Solution Id.         |
| structure | array of objects | No       | An array of Table Structure objects. |

## Response Format

Returns the created Table object.
