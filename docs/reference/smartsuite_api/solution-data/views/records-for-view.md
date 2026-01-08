# Get Records for View

**GET** `https://app.smartsuite.com/api/v1/applications/[tableId]/records-for-report/?report=[report_id]&with_empty_values=false`

Gets the records for a specified View.

## Example Request

```bash
curl -X GET https://app.smartsuite.com/api/v1/applications/63b87cad645b3949631b55c1/records-for-report/?report=[reportId]&with_empty_values=false \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json"
```

## Query Parameters

| Param    | Type   | Description |
| -------- | ------ | ----------- |
| reportId | string | The View Id |

## Response

| Param           | Type                    | Description                                             |
| --------------- | ----------------------- | ------------------------------------------------------- |
| records         | array of record objects | An array containing SmartSuite record objects           |
| related_records | array of strings        | An array containing related record Ids                  |
| fields          | array of strings        | An array containing the field slugs visible in the View |
| filter          | filter object           | The filter applied to the view, if any                  |
| unfiltered      | boolean                 | true if not filtered, false if filter applied           |

## Example Response

```json
{
  "records": [
    {
      "first_created": {
        "by": "63a1f65723aaf6bcb564b1f1",
        "on": "2023-01-06T20:00:15.470000Z"
      },
      "last_updated": {
        "by": "63a1f65723aaf6bcb564b1f1",
        "on": "2023-01-06T20:00:15.470000Z"
      },
      "autonumber": 1,
      "title": "WORKSPACE_ID",
      "comments_count": 0,
      "id": "63b87dcf7acde19eac1fe42a",
      "application_slug": "ssb9kaxn",
      "application_id": "63b87cad645b3949631b55c1"
    }
  ],
  "related_records": [],
  "fields": [
    "title",
    "due_date",
    "comments_count",
    "status",
    "priority",
    "assigned_to"
  ],
  "filter": {},
  "unfiltered": true
}
```
