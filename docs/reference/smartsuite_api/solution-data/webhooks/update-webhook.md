# Update Webhook

**POST** `https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/UpdateWebhook`

Updates a webhook.

## Example Request

```bash
curl -X POST https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/UpdateWebhook \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "webhook": {
      "webhook_id": "2f7cc6e0-b709-4b04-964a-3706c89c78e3",
      "kinds": ["RECORD_CREATED"],
      "locator": {
        "account_id": "{{accountId}}",
        "solution_id": "{{solutionId}}"
      },
      "filter": {
        "solution": {}
      },
      "notification_status": {
        "disabled": {}
      }
    }
  }'
```

## Request Body

| Param               | Type             | Optional | Description                                                 |
| ------------------- | ---------------- | -------- | ----------------------------------------------------------- |
| webhook_id          | string           | No       | Id of webhook to update                                     |
| kinds               | array of strings | No       | Event types: RECORD_CREATED, RECORD_UPDATED, RECORD_DELETED |
| locator             | object           | No       | Contains workspace and Solution information                 |
| filter              | object           | No       | Specifies filter criteria                                   |
| notification_status | object           | Yes      | Set to `{"enabled": {"url": "..."}}` or `{"disabled": {}}`  |

## Response

Returns the updated webhook object.
