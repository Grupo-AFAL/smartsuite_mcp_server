# List Teams

**POST** `https://app.smartsuite.com/api/v1/teams/list/`

List Workspace Teams (groups). Responses are similar to List Records responses. Returned records do not include any fields with "empty" values, e.g. "", [], or false.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/teams/list/?offset=0&limit=3 \\
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

| Param  | Type             | Description                     |
| ------ | ---------------- | ------------------------------- |
| items  | array of objects | Array of team objects.          |
| total  | number           | Total number of Teams returned. |
| offset | number           | Offset value for returned data. |
| limit  | number           | Limit value for returned data.  |
| time   | timestamp        | ISO datetime of response.       |

## Example Response

```json
{
  "items": [
    {
      "first_created": {
        "by": "63a1f65723aaf6bcb564b1f1",
        "on": "2024-02-15T22:44:53.016000Z"
      },
      "last_updated": {
        "by": "63a1f65723aaf6bcb564b1f1",
        "on": "2024-02-20T20:29:00.715000Z"
      },
      "application_id": "63a1f65623aaf6bcb564b00b",
      "ranking": {
        "default": "aamevqverw"
      },
      "id": "65ce93e5e6bd79eeaf37045d",
      "application_slug": "teams",
      "deleted_date": {
        "date": null
      },
      "name": "Project Team: Website Project",
      "color": [
        {
          "value": "#0C41F3"
        }
      ],
      "type": "2",
      "status": {
        "value": "1",
        "updated_on": "2024-02-15T22:44:53.041000Z"
      },
      "owners": ["63a1f65723aaf6bcb564b1f1"],
      "members": ["64591b7288d2ea5cfc582944", "63a1f65723aaf6bcb564b1f1"]
    }
  ],
  "total": 1,
  "offset": 0,
  "limit": 0,
  "time": "2024-06-11T22:57:18.107986Z"
}
```
