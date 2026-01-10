# List Members

**POST** `https://app.smartsuite.com/api/v1/members/list/`

List Workspace Members (users). Responses are similar to List Records responses. Returned records do not include any fields with "empty" values, e.g. "", [], or false.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/members/list/?offset=0&limit=3 \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "sort": [],
    "filter": {}
  }'
```

## Query Parameters

| Param  | Type   | Optional | Description                                                                                                           |
| ------ | ------ | -------- | --------------------------------------------------------------------------------------------------------------------- |
| offset | number | Yes      | For use in pagination - specify the offset value returned by the prior record response to retrieve the next page.     |
| limit  | number | Yes      | Number of records to return per request. If not set, defaults to 100. Note: Value must be less than or equal to 1000. |

## Request Body

| Param  | Type          | Optional | Description                         |
| ------ | ------------- | -------- | ----------------------------------- |
| sort   | sort object   | Yes      | Object specifying sort parameters   |
| filter | filter object | Yes      | Object specifying filter parameters |

## Response Format

| Param  | Type             | Description                       |
| ------ | ---------------- | --------------------------------- |
| items  | array of objects | Array of member objects.          |
| total  | number           | Total number of Members returned. |
| offset | number           | Offset value for returned data.   |
| limit  | number           | Limit value for returned data.    |
| time   | timestamp        | ISO datetime of response.         |
