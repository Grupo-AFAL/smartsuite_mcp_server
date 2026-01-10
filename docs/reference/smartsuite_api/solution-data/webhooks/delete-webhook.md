# Delete Webhook

**POST** `https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/DeleteWebhook`

Deletes a webhook.

> **Note:** Deleting a webhook will also delete all stored events associated with it.

## Request Body

| Param      | Type   | Optional | Description             |
| ---------- | ------ | -------- | ----------------------- |
| webhook_id | string | No       | Id of webhook to delete |

## Example Request

```bash
curl -X POST https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/DeleteWebhook \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "webhook_id": "2f7cc6e0-b709-4b04-964a-3706c89c78e3"
  }'
```

## Response

200 Ok
