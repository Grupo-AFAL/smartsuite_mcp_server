# Bulk Delete Records

**PATCH** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/bulk_delete/?fields=id`

Deletes multiple records. Your request body should include an array (items) of up to 25 record ids as strings.

> **Notice:** Including more than 25 records will result in the server returning a 422 error.

## Example Request

```bash
curl -X PATCH https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/bulk_delete/?fields=id \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  --data '{
    "items": [
      "6418b7a1f2f4056dd0279a54",
      "6418b7a2fe6b4a731195c245",
      "6418b7a2db77680b279fd3f8"
    ]
  }'
```

## Path Parameters

| Param   | Type   | Description                                          |
| ------- | ------ | ---------------------------------------------------- |
| tableId | string | The Id of the Table (App) that contains the records. |

## Request Body

| Param | Type             | Optional | Description                                                      |
| ----- | ---------------- | -------- | ---------------------------------------------------------------- |
| items | Array of strings | No       | An array of strings containing the Ids of the records to delete. |

## 200 Response - Example

```json
[
  {
    "application_id": "65f194001c0091a8180f8b2b",
    "id": "66be7b5fb8b730607ea959f4",
    "application_slug": "sbwchxhv",
    "deleted_date": {
      "date": "2024-08-15T22:11:57.259000Z",
      "include_time": true
    }
  }
]
```
