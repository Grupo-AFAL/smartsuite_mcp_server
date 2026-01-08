# Bulk Add Fields

**POST** `https://app.smartsuite.com/api/v1/applications/{tableId}/bulk-add-fields/`

Add multiple fields to a Table (App).

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/646536cac79b49252b0f94f5/bulk_add_fields/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "fields": [
      {
        "slug": "123asd456z",
        "label": "Peter Text",
        "field_type": "textfield",
        "icon": "text",
        "params": {
          "help_text": "This is help text",
          "display_format": "importance"
        },
        "is_new": true
      }
    ],
    "set_as_visible_fields_in_reports": []
  }'
```

## Path Parameters

| Param   | Type   | Description                                             |
| ------- | ------ | ------------------------------------------------------- |
| tableId | string | The Id of the Table (App) in which to create the field. |

## Request Body

| Param                            | Type             | Optional | Description                                                                                          |
| -------------------------------- | ---------------- | -------- | ---------------------------------------------------------------------------------------------------- |
| fields                           | array of objects | No       | Array of field objects to bulk add.                                                                  |
| set_as_visible_fields_in_reports | array of strings | Yes      | Array of view (report) ids the added fields should be appended to in the View(s) "fields to display" |

## Response

200 Response - Empty Response
