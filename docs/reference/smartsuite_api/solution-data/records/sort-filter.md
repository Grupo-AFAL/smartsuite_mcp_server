# Sorting and Filtering Records

The SmartSuite REST API gives you the ability to retrieve record data with the `/records/list/` endpoint. The reason that this endpoint accepts POST requests (typically GET is used for retrieval) is that the body of the request can contain JSON representing sort and filter instructions for the request.

> **Note:** SmartSuite does not consider adding keys to response objects as breaking changes, so the shape of objects may change without notice. Existing keys will not be removed without a deprecation warning and timeframe.

## Authorization

Just like other REST API endpoints, SmartSuite uses token-based authentication for record requests. You can generate or manage your API key in your User Profile.

All API requests must be authenticated and made over HTTPS.

> **IMPORTANT!** Your API key conveys the same privileges as the Member account it is generated in, so it should be treated as securely as a password.

You authenticate to the API by providing your API key in the Authorization header, as well as your Workspace Id in an Account-Id header, as shown below.

| KEY           | VALUE              |
| ------------- | ------------------ |
| Authorization | Token API_KEY_HERE |
| Account-Id    | WORKSPACE_ID_HERE  |

> **Note:** Your Workspace Id is the 8 characters that follow `https://app.smartsuite.com/` in the SmartSuite URL when you're logged in.
> Example: `https://app.smartsuite.com/sv25cxf2/solution/62c4b…`

## Retrieving Records

There are two ways to retrieve records in the SmartSuite API:

### Retrieve a single record

You can use the following endpoint to retrieve a single record:

**GET** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/[Record Id]/`

`[tableId]` is the Table (App) unique id

This endpoint does not accept any sorting or filtering parameters, as a single record is retrieved per call.

### Retrieve a list of records

This endpoint retrieves a list of records from SmartSuite:

**POST** `https://app.smartsuite.com/api/v1/applications/[tableId]/records/list/`

`[tableId]` is the Table (App) unique id

This endpoint supports sort and filter directives that are specified in the JSON body.

> **Note:** You should set Content-Type to application/JSON when including sort and filter JSON as part of your request.

## Specifying Sort and Filter Parameters

Both sort and filter parameters are specified in the body of the POST request, and must be formatted as valid JSON.

Sorting and filtering can be specified independently, or can be combined in the request.

### Example

```json
{
  "filter": {
    "operator": "and",
    "fields": [
      {
        "field": "title",
        "comparison": "is_not_empty",
        "value": ""
      }
    ]
  },
  "sort": [
    {
      "field": "title",
      "direction": "asc"
    }
  ]
}
```

## Sort Syntax

The syntax for sort is simple - you specify a key value of "sort" and a value that is an array of sort objects. Each sort object contains two JSON object literals:

| Key       | Value                                             |
| --------- | ------------------------------------------------- |
| field     | field id ("slug" value) to perform the sort on    |
| direction | direction of the sort, which varies by field type |

You can include multiple sorts in the array. The sort should be returned as an array even if you are sorting by a single field.

### Example of a single sort

```json
"sort": [
  {
    "field": "title",
    "direction": "desc"
  }
]
```

### Example of multiple sorts

```json
"sort": [
  {
    "field": "title",
    "direction": "asc"
  },
  {
    "field": "s228acd4ea",
    "direction": "desc"
  }
]
```

Multiple sorts are applied in the order specified, so in the above example the records would first be sorted by title and then by the field with id s228acd4ea.

## Filter Syntax

Filter syntax resembles sort syntax as it consists of a key value "filter" which contains a filter object. The filter object contains a JSON literal with key "operator" that has a string value, and a second JSON literal with key "fields" that has an array of field objects as its value.

| Key      | Type                    | Value                                                                                                                                                                                                                                                           |
| -------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| operator | string                  | Valid operators include: `and` - requires all specified filters to match, `or` - requires at least one filter specified filter to match                                                                                                                         |
| fields   | array of filter objects | An array of Filter objects that have the following JSON literals: `field` - the field id ("slug"), `comparison` - the comparison operator, which varies by field type, `value` - the value to compare, the format of which depends on field type being filtered |

> **Note:** The operator is required in the request body even if only a single filter is being applied, with a value of and or or being specified (both return the same records).

### Example of an and filter

```json
"filter": {
  "operator": "and",
  "fields": [
    {
      "field": "status",
      "comparison": "is_not",
      "value": "Complete"
    },
    {
      "field": "s251d4318b",
      "comparison": "is_equal_to",
      "value": 0
    }
  ]
}
```

## Filter Values

The value you pass in the filter corresponds to the field's type:

- **Text Type**: Pass a double-quote enclosed string to the filter
- **Number Type**: Pass a number or a number enclosed in quotes (number as string is interpreted properly)
- **Date Type**: Pass a Date Value Object (see below)

### Date Value Object

Dates differ from string and number type fields in that they require passing a Date Value Object as their value. They have two JSON literals: `date_mode` and `date_mode_value`

```json
"value": {
  "date_mode": "exact_date",
  "date_mode_value": "2023-02-01"
}
```

## Operators by Field Type

| Field                                 | Sort Options | Filter Options                                                                                                                       |
| ------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Text (textfield)                      | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Address (addressfield)                | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Email (emailfield)                    | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Phone (phonefield)                    | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Link (linkfield)                      | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Record Title (recordtitlefield)       | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Text Area (textareafield)             | asc, desc    | is, is_not, is_empty, is_not_empty, contains, not_contains                                                                           |
| Currency (currencyfield)              | asc, desc    | is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty |
| Number (numberfield)                  | asc, desc    | is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty |
| Percent (percentfield)                | asc, desc    | is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty |
| Rating (ratingfield)                  | asc, desc    | is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty |
| Single Select (singleselectfield)     | asc, desc    | is, is_not, is_any_of, is_none_of, is_empty, is_not_empty                                                                            |
| Multiple Select (multipleselectfield) | asc, desc    | has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty                                                              |
| Status (statusfield)                  | asc, desc    | is, is_not, is_any_of, is_none_of, is_empty, is_not_empty                                                                            |
| Tag (tagsfield)                       | asc, desc    | has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty                                                              |
| Yes / No (yesnofield)                 | asc, desc    | is                                                                                                                                   |
| Date (datefield)                      | asc, desc    | is, is_not, is_before, is_on_or_before, is_on_or_after, is_empty, is_not_empty                                                       |
| Due Date (duedatefield)               | asc, desc    | is, is_not, is_before, is_on_or_before, is_on_or_after, is_empty, is_not_empty, is_overdue, is_not_overdue                           |
| Duration (durationfield)              | asc, desc    | is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty |
| Files & Images (filefield)            | asc, desc    | file_name_contains, file_type_is, is_empty, is_not_empty                                                                             |
| Linked Record (linkedrecordfield)     | asc, desc    | contains, not_contains, has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty                                      |
| Assigned To (userfield)               | asc, desc    | has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty                                                              |
| Auto Number (autonumberfield)         | asc, desc    | is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than                         |

## Date Modes and Values

| Date Mode       | Values                                                                                                                                                                      |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| is              | today, yesterday, one_week_ago, one_week_from_now, one_month_ago, one_month_from_now, one_year_ago, one_year_from_now, next_number_of_days, past_number_of_days, date_range |
| is_not          | today, yesterday, one_week_ago, one_week_from_now, one_month_ago, one_month_from_now, one_year_ago, one_year_from_now, next_number_of_days, past_number_of_days, date_range |
| is_before       | today, yesterday, one_week_ago, one_week_from_now, one_month_ago, one_month_from_now, one_year_ago, one_year_from_now, exact_date                                           |
| is_on_or_before | today, yesterday, one_week_ago, one_week_from_now, one_month_ago, one_month_from_now, one_year_ago, one_year_from_now, exact_date                                           |
| is_on_or_after  | today, yesterday, one_week_ago, one_week_from_now, one_month_ago, one_month_from_now, one_year_ago, one_year_from_now, exact_date                                           |
| is_empty        | null                                                                                                                                                                        |
| is_not_empty    | null                                                                                                                                                                        |
