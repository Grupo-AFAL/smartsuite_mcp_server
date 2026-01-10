# Update Member Profile

**PUT or PATCH** `https://app.smartsuite.com/api/v1/members/{memberId}/`

Update a Member profile. Responses are similar to List Records responses.

## Example Request

```bash
curl -X PATCH https://app.smartsuite.com/api/v1/members/645109df887911e1871054b7/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "language": "en"
  }'
```

## Update Types

The update endpoint supports two types of record updates:

- **PUT request**: Performs a "destructive" update that clears all values that are not specified in the update
- **PATCH request**: Updates just those fields included in the request

## Path Parameters

| Param    | Type   | Description                               |
| -------- | ------ | ----------------------------------------- |
| memberId | string | The Id of the Member to apply updates to. |

## Request Body

| Param         | Type   | Description                                            |
| ------------- | ------ | ------------------------------------------------------ |
| member object | object | A record object representing the Member to be updated. |

## Response

Returns the updated Member object.
