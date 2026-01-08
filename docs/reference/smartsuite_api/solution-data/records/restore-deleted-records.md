# Restore Deleted Record

**POST** `https://app.smartsuite.com/api/v1/applications/{app-id}/records/{record-id}/restore/`

Restores a deleted record. The record's title will be appended with (Restored).

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/65f194001c0091a8180f8b2b/records/66be7b5fb8b730607ea959f5/restore/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{}'
```

## Query Parameters

None

## Request Body

Empty

## Response

Returns the restored record object with "(Restored)" appended to the title.
