# List Deleted Records

**POST** `https://app.smartsuite.com/api/v1/deleted-records/?preview=true`

List deleted records in a Solution.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/deleted-records/?preview=true \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "solution_id": "{solutionId}"
  }'
```

## Query Parameters

| Param   | Type    | Optional | Description                                                                                     |
| ------- | ------- | -------- | ----------------------------------------------------------------------------------------------- |
| preview | boolean | Yes      | True causes the system to return a limited number of fields, including the deletion information |

## Request Body

| Param       | Type   | Optional | Description     |
| ----------- | ------ | -------- | --------------- |
| solution_id | string | No       | The Solution Id |

## 200 Response - Example

```json
[
  {
    "last_updated": {
      "by": "63a1f65723aaf6bcb564b1f1",
      "on": "2024-08-15T22:13:07.816000Z"
    },
    "title": "record 1a (Restored)",
    "deleted_by": "63a1f65723aaf6bcb564b1f1",
    "deleted_date": {
      "date": "2024-08-15T22:14:37.945000Z",
      "include_time": true
    },
    "id": "66be7b5fb8b730607ea959f4",
    "application_slug": "sbwchxhv",
    "application_id": "65f194001c0091a8180f8b2b",
    "application_name": "Table 1",
    "application_record_term": "record",
    "solution_id": "65e62c77bb8beb915abaa9a2"
  }
]
```
