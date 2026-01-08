# List Events

**POST** `https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/ListEvents`

Lists events for a webhook.

## Example Request

```bash
curl -X POST https://webhooks.smartsuite.com/smartsuite.webhooks.engine.Webhooks/ListEvents \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "webhook_id": "{{webhook_id}}",
    "page_size": "50",
    "page_token": ""
  }'
```

## Request Body

| Param      | Type   | Optional | Description                                          |
| ---------- | ------ | -------- | ---------------------------------------------------- |
| webhook_id | string | Yes      | Specifies a webhook Id to return events for.         |
| page_size  | string | Yes      | Number of records per page                           |
| page_token | string | Yes      | Use next_page_token to fetch the next page of events |

## Response

| Param           | Type                   | Description                                       |
| --------------- | ---------------------- | ------------------------------------------------- |
| events          | array of event objects | Array of events                                   |
| next_page_token | string                 | Token used to request the next page of event data |

## Event Object Structure

| Param             | Type              | Description                                                     |
| ----------------- | ----------------- | --------------------------------------------------------------- |
| webhook_id        | string            | The event's webhook Id                                          |
| locator           | locator object    | Contains workspace and Solution information                     |
| event_id          | string            | The event's Id                                                  |
| kind              | string            | The event type (RECORD_CREATED, RECORD_UPDATED, RECORD_DELETED) |
| event_at          | datetime          | Event's ISO datetime                                            |
| record_event_data | event data object | Event's record data                                             |
| ctx               | ctx object        | Information about the event                                     |

## Example Response

```json
{
  "events": [
    {
      "webhook_id": "2f7cc6e0-b709-4b04-964a-3706c89c78e3",
      "locator": {
        "account_id": "WORKSPACE_ID",
        "solution_id": "63b87cad645b3949631b55bf"
      },
      "event_id": "2f7cc6e0-b709-4b04-964a-3706c89c78e3.994",
      "kind": "RECORD_CREATED",
      "event_at": "2023-06-21T21:14:06.263Z",
      "record_event_data": {
        "record_id": "6493681eba09b400816eb754",
        "locator": {
          "account_id": "WORKSPACE_ID",
          "solution_id": "63b87cad645b3949631b55bf",
          "application_id": "63b87cad645b3949631b55c1"
        },
        "data": {
          "title": "test",
          "id": "6493681eba09b400816eb754"
        },
        "previous": {}
      },
      "ctx": {
        "change_id": "ba1ffa93-0c51-48ab-aff2-64d9128d6c35",
        "change_size": 1,
        "batch_id": "65832e55206fdfd247b84abd",
        "batch_size": 1,
        "source": "UNKNOWN",
        "handler": "INTERACTIVE"
      }
    }
  ],
  "next_page_token": "8991625"
}
```
