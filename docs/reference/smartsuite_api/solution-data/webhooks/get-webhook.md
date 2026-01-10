# Get Webhook

**POST** `https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/GetWebhooks`

Gets a webhook by Id.

## Example Request

```bash
curl -X POST https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/GetWebhooks \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "webhook_id": "{{webhook_id}}"
  }'
```

## Request Body

| Param      | Type   | Optional | Description                             |
| ---------- | ------ | -------- | --------------------------------------- |
| webhook_id | string | No       | Id of the webhook you want to retrieve. |

## Response

Returns the webhook object with all details including webhook_id, locator, filter, kinds, created_at, updated_at, notification_status, and system_status.
