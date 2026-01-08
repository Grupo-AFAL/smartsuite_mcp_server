# List Webhooks

**POST** `https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/ListWebhooks`

Lists webhooks for a solution.

## Example Request

```bash
curl -X POST https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/ListWebhooks \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "solution_id": "{{solution_id}}",
    "page_size": "50",
    "page_token": ""
  }'
```

## Request Body

| Param       | Type   | Optional | Description                                    |
| ----------- | ------ | -------- | ---------------------------------------------- |
| solution_id | string | No       | Specifies the Solution to return webhooks for. |
| page_size   | string | Yes      | Number of records per page                     |
| page_token  | string | Yes      | Token for pagination                           |

## Response Example

```json
{
  "webhooks": [
    {
      "webhook_id": "3c8a1835-a39a-43ba-ba9c-6fbce5581e34",
      "locator": {
        "account_id": "WORKSPACE_ID",
        "solution_id": "641b70cb0d94c969a49983aa"
      },
      "filter": {
        "solution": {}
      },
      "kinds": ["RECORD_CREATED"],
      "created_at": {
        "by": "Peter Novosel",
        "at": "2023-06-20T14:26:47.192Z"
      },
      "updated_at": {
        "by": "Peter Novosel",
        "at": "2023-06-20T14:26:47.192Z"
      },
      "notification_status": {
        "enabled": {
          "url": "https://sswebhooks.requestcatcher.com/"
        }
      },
      "system_status": {
        "enabled": {
          "expires_at": "2023-11-02T14:21:43Z"
        }
      }
    }
  ]
}
```
