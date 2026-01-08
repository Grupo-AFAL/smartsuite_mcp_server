# Create Webhook

**POST** `https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/CreateWebhook`

Creates a new webhook with the specified filter criteria.

Three levels of filtering are available:

1. **Solution** - Receive events for the entire SmartSuite Solution.
2. **Application (Table)** - Receive events for one or more Tables (Apps) in a Solution.
3. **Application (Table) fields** - Limit events to specific fields in a Table (App).

> **Note:** You can currently create any number of webhooks, but be aware that this may be limited in the future. You must call list payloads at least once every 7 days for the webhook to stay active.

## Request Body

| Param               | Type                       | Optional | Description                                                 |
| ------------------- | -------------------------- | -------- | ----------------------------------------------------------- |
| filter              | filter object              | No       | Specifies filters for the webhook                           |
| kinds               | array of strings           | No       | Event types: RECORD_CREATED, RECORD_UPDATED, RECORD_DELETED |
| locator             | object                     | No       | Contains workspace and Solution information                 |
| webhook_id          | string                     | Yes      | Leave blank or omit when creating                           |
| notification_status | notification_status object | Yes      | Webhook notification settings                               |

## Filter Object Options

### Solution level (no tables/fields)

```json
"filter": {
  "solution": {}
}
```

### Table (application) level

```json
"filter": {
  "applications": {
    "application_ids": ["some application id"]
  }
}
```

### Field level

```json
"filter": {
  "application": {
    "application_id": "some application id",
    "field_ids": ["some field id 1", "some field id 2"]
  }
}
```

## Example Request (Solution filter)

```bash
curl -X POST https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/CreateWebhook \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "webhook": {
      "filter": {
        "solution": {}
      },
      "kinds": ["RECORD_CREATED"],
      "locator": {
        "account_id": "{{accountId}}",
        "solution_id": "{{solutionId}}"
      },
      "notification_status": {
        "enabled": {
          "url": "https://your-webhook-url.com/"
        }
      }
    }
  }'
```

## Response

Returns the created webhook object with webhook_id, locator, filter, kinds, created_at, updated_at, notification_status, and system_status.
