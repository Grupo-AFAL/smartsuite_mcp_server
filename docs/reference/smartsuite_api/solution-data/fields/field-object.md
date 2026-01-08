# Field Object

## Example

```json
"field": {
  "slug": "random_10_digit_alphanumeric_value",
  "label": "Field Name",
  "field_type": "field_type",
  "params": {
    ...field_specific_params
  },
  "is_new": true
}
```

## Object Literals

| Param      | Type    | Optional | Description                           |
| ---------- | ------- | -------- | ------------------------------------- |
| slug       | string  | No       | A random 10 digit alphanumeric value. |
| label      | string  | No       | The field name.                       |
| field_type | string  | No       | The field type (see below).           |
| params     | object  | No       | field-specific parameters.            |
| is_new     | boolean | No       | Set to true for new fields.           |

## Field Types

| Field Name        | Field Type           | Notes                                 |
| ----------------- | -------------------- | ------------------------------------- |
| Single Select     | singleselectfield    |                                       |
| Multiple Select   | multipleselectfield  |                                       |
| Status            | statusfield          |                                       |
| Tag               | tagsfield            |                                       |
| Text              | textfield            |                                       |
| Address           | addressfield         |                                       |
| Date              | datefield            |                                       |
| Date Range        | daterangefield       |                                       |
| Due Date          | duedatefield         |                                       |
| Duration          | durationfield        |                                       |
| Time              | timefield            |                                       |
| Time Tracking Log | timetrackingfield    | Bulk add unsupported.                 |
| Checklist         | checklistfield       | Bulk add unsupported.                 |
| Color Picker      | colorpickerfield     |                                       |
| Email             | emailfield           |                                       |
| Full Name         | fullnamefield        |                                       |
| IP Address        | ipaddressfield       |                                       |
| Link              | linkfield            |                                       |
| Phone             | phonefield           |                                       |
| Title (Primary)   | recordtitlefield     | System Field, cannot be added via API |
| SmartDoc          | richtextareafield    |                                       |
| Social Network    | socialnetworkfield   | Bulk add unsupported.                 |
| Text Area         | textareafield        |                                       |
| Currency          | currencyfield        |                                       |
| Number            | numberfield          |                                       |
| Number Slider     | numbersliderfield    |                                       |
| Percent Complete  | percentcompletefield |                                       |
| Percent           | percentfield         |                                       |
| Rating            | ratingfield          |                                       |
| Vote              | votefield            | Bulk add unsupported.                 |
| Count             | countfield           | Bulk add unsupported.                 |
| Files and Images  | filefield            | Bulk add unsupported.                 |
| Signature         | signaturefield       | Bulk add unsupported.                 |
| Formula           | formulafield         | Bulk add unsupported.                 |
| Lookup            | lookupfield          |                                       |
| Rollup            | rollupfield          | Bulk add unsupported.                 |
| Record Id         | recordidfield        | Bulk add unsupported.                 |
| First Created     | firstcreatedfield    | System Field, cannot be added via API |
| Last Updated      | lastupdatedfield     | System Field, cannot be added via API |
| Sub-Items         | subitemsfield        | Bulk add unsupported.                 |
| Open Comments     | commentscountfield   | System Field, cannot be added via API |
| Button            | buttonfield          | Bulk add unsupported.                 |
| Linked Record     | linkedrecordfield    |                                       |
| Assigned To       | userfield            |                                       |
| Auto Number       | autonumberfield      | System Field, cannot be added via API |
