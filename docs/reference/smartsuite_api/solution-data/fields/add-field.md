# Add Field

**POST** `https://app.smartsuite.com/api/v1/applications/[tableId]/add_field/`

Creates a field in the specified Table (App).

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/applications/646536cac79b49252b0f94f5/add_field/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "field": {
      "slug": "[Random 10 digit alphanumeric value]",
      "label": "[Field Name]",
      "field_type": "[Field Type]",
      "params": {
        [Field-Specific Parameters]
      },
      "is_new": true
    },
    "field_position": {
      "prev_sibling_slug": "[Previous Field Slug (or null)]"
    },
    "auto_fill_structure_layout": true
  }'
```

## Path Parameters

| Param   | Type   | Description                                       |
| ------- | ------ | ------------------------------------------------- |
| tableId | string | The Id of the Table in which to create the field. |

## Request Body

| Param                      | Type    | Optional | Description                                                                                                                              |
| -------------------------- | ------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| field                      | object  | No       | A field object. See Definition                                                                                                           |
| field_position             | object  | Yes      | Object with `prev_sibling_slug` string - the previous field's slug value (added field will be placed after it on the edit record layout) |
| auto_fill_structure_layout | boolean | Yes      |                                                                                                                                          |
