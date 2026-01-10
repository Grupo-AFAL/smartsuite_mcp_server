# Webhooks Overview

> **BETA:** Webhooks are currently in BETA and we recommend that you use caution when using them in production. We will make announcements in the SmartSuite Community about general availability of this function.

Webhooks are a mechanism for getting user-configurable programmatic notifications of changes to data or metadata within SmartSuite.

> **Notice:** We may add more field types in the future and this will not be considered a breaking change. API consumers are expected to handle unknown field types gracefully. Further, object definitions are not meant to exhaustively describe the shape, new properties can be added and will not be considered a breaking change.

## Authorization

The webhooks API uses token-based authentication. Users will need to send the token in the Authorization header of all requests, just like other API calls:

```
Authorization: TOKEN API_TOKEN
```

We currently support using API tokens and OAuth access tokens (coming soon) during the authentication process.

Finally, please perform all requests to these endpoints server-side. Client-side requests are not allowed because they would expose the user's API token.

## Rate Limits

The API is limited to 5 requests per second per API key. If you exceed this rate, you will receive a 429 status code and will need to wait 30 seconds before subsequent requests will succeed.

## Webhook Notifications

When an event matching one of your configured webhook's specifications occurs, SmartSuite will send notification via a POST to the associated webhook's notification URL containing the Solution Id and the webhook Id.

### Example Webhook Payload

```json
{
  "webhookId": "f0bd5e90-02bb-4017-9294-f885e3e94559",
  "locator": {
    "accountId": "snbvtl79",
    "solutionId": "63b87cad645b3949631b55bf"
  }
}
```

You should respond to this request with an HTTP 200 status code. The response body should be empty.

You are then responsible for retrieving the contents of the updates from the SmartSuite API in separate HTTP requests.

> **Note:** Updates Planned - Currently the webhook payload includes the webhookId and a locator object. This object will contain accountId and solutionId. We have a planned enhancement to add additional locator information (applicationId (table Id) and fields that are being tracked by the webhook), as well as a timestamp.

You will receive at least one notification ping, but we do not guarantee that duplicate notifications will not be sent under some circumstances.

If our notification ping fails for some reason (timeout, failure to connect, etc.) we will retry using an exponential backoff for a period of approximately one day. If the ping is still failing after those retries we will disable it and you will need to toggle it back on to again receive notification pings.

## Webhook Expiration

You must call list payloads at least once every 7 days for the webhook to stay active. After 7 days of inactivity we will disable notifications for your webhook. Webhooks in this state for a further 7 days will be deleted, along with their payloads.

Calling list payloads during the 7 day inactive period will re-enable the webhook and extend the timeout period an additional 7 days.
