# List Records

**POST** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/list/`

List records in an App. Note that you must use the Table (App) Id when referencing the App. Returned records do not include any fields with "empty" values, e.g. "", [], or false.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/6451093119bcf22befaed847/records/list/?offset=0&limit=3 \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "sort": [],
    "filter": {}
  }'
```

## Path Parameters

| Param   | Type   | Description        |
| ------- | ------ | ------------------ |
| tableId | string | The Table (App) Id |

## Query Parameters

| Param  | Type    | Optional | Description                                                                                                           |
| ------ | ------- | -------- | --------------------------------------------------------------------------------------------------------------------- |
| offset | number  | Yes      | For use in pagination - specify the offset value returned by the prior record response to retrieve the next page.     |
| limit  | number  | Yes      | Number of records to return per request. If not set, defaults to 100. Note: Value must be less than or equal to 1000. |
| all    | boolean | Yes      | Returns all records, including those marked as deleted. Defaults to false.                                            |

## Request Body

| Param    | Type          | Optional | Description                                                |
| -------- | ------------- | -------- | ---------------------------------------------------------- |
| sort     | sort object   | Yes      | Object specifying sort parameters                          |
| filter   | filter object | Yes      | Object specifying filter parameters                        |
| hydrated | boolean       | Yes      | Returns text labels for id-type fields. Defaults to false. |

## Pagination

The server returns unlimited records by default. You can use the limit parameter to limit the number of records returned per request.

When paginated, if there are more records than limit, the response will contain an offset. To fetch the next page of records, include offset in the next request parameters.

### Example

```
https://app.smartsuite.com/api/v1/applications/[ID]/records/list/?limit=100
```

This will have the effect of returning the first 100 items. You can retrieve subsequent pages by specifying an offset value:

```
https://app.smartsuite.com/api/v1/applications/[ID]/records/list/?limit=100&offset=100
```

This will tell the API to ignore the first 100 items and send the next 100.

## Hydrating Records

To return human-readable values for certain fields, you can include the following JSON in the request body:

```json
{ "hydrated": true }
```

Fields that will return additional information with this setting include:

- Single Select
- Multiple Select
- Status
- First Created
- Last Updated
- Assigned To
- Tags
- Vote
- Time Tracking Log
- Checklist
- Lookup

## Deleted Records

By default, only active (non-deleted) records are returned by this endpoint. To return deleted records along with active records, include the following parameter with your request:

```
?all=true
```

## Response Format

| Param  | Type             | Description                       |
| ------ | ---------------- | --------------------------------- |
| total  | number           | Total number of records returned. |
| offset | number           | Current offset value.             |
| limit  | number           | Current limit value.              |
| items  | Array of objects | Array of record objects.          |

## 200 Response - Example

```json
{
  "total": 1,
  "offset": 0,
  "limit": 0,
  "items": [
    {
      "title": "Record 1",
      "description": {
        "data": {},
        "html": "<div class=\\"rendered\\">\\n \\n</div>"
      },
      "assigned_to": [
        "5dd812b9d8b7863532d3ddd2",
        "5e6ec7dadc8a90f33bcb02c9"
      ],
      "status": {
        "value": "in_progress"
      },
      "due_date": {
        "from_date": {
          "date": "2021-09-03T03:00:00Z",
          "include_time": true
        },
        "to_date": {
          "date": "2021-09-04T03:15:00Z",
          "include_time": true
        },
        "is_overdue": false
      },
      "priority": "1",
      "first_created": {
        "on": "2020-06-05T22:46:20.336000Z",
        "by": "5ec1df770a8617c27a73e3c3"
      },
      "last_updated": {
        "on": "2020-06-19T19:11:46.042000Z",
        "by": "5ec1df770a8617c27a73e3c3"
      },
      "followed_by": [
        "5dd812b9d8b7863532d3ddd2",
        "5e6ec7dadc8a90f33bcb02c9"
      ],
      "comments_count": 1,
      "autonumber": 1,
      "sef1a6a113": {
        "from_date": {
          "date": "2021-09-01T00:00:00Z",
          "include_time": false
        },
        "to_date": {
          "date": "2021-09-03T00:00:00Z",
          "include_time": false
        }
      }
    }
  ]
}
```
