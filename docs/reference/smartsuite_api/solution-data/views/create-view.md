# Create View

**POST** `https://app.smartsuite.com/api/v1/reports/`

Creates a new View.

## Example Request (Simple Grid View)

```bash
curl -X POST https://app.smartsuite.com/api/v1/reports/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "application": "[app_id]",
    "autosave": false,
    "description": "",
    "is_dirty": false,
    "is_locked": false,
    "is_password_protected": false,
    "is_private": false,
    "map_state": {},
    "sharing_allow_all_fields": false,
    "sharing_allow_copy": false,
    "sharing_allow_export": false,
    "sharing_allow_open_record": false,
    "sharing_enabled": false,
    "sharing_hash": "",
    "sharing_password": "",
    "sharing_show_toolbar": false,
    "solution": "641b70cb0d94c969a49983aa",
    "state": {
      "filterWindow": {
        "opened": false,
        "filter": {
          "operator": "and",
          "fields": []
        }
      },
      "fieldsWindow": {
        "visibleFields": ["title"],
        "fixedFieldsCount": 1,
        "columnsWidth": {},
        "collapsed": []
      }
    },
    "label": "TEST",
    "view_mode": "grid",
    "order": 2
  }'
```

## Request Body

| Param                      | Type              | Optional | Description                                     |
| -------------------------- | ----------------- | -------- | ----------------------------------------------- |
| application                | string            | No       | Id of the App where you want to create the View |
| autosave                   | boolean           | No       | Autosave state for the new View                 |
| description                | string            | Yes      | Optional description for the View               |
| is_dirty                   | boolean           | No       | -Internal Use-                                  |
| is_locked                  | boolean           | No       | View locked status                              |
| is_password_protected      | boolean           | No       | View password protect status                    |
| is_private                 | boolean           | No       | View private status                             |
| map_state                  | map state object  | Yes      | Map View type configuration                     |
| sharing_allow_all_fields   | boolean           | Yes      | Allow all fields when sharing                   |
| sharing_allow_copy         | boolean           | Yes      | Allow copy when sharing                         |
| sharing_allow_export       | boolean           | Yes      | Allow export when sharing                       |
| sharing_allow_open_records | boolean           | Yes      | Allow opening record details when sharing       |
| sharing_enabled            | boolean           | Yes      | Sharing state enabled or disabled               |
| sharing_hash               | string            | No       | Shared View hash value                          |
| sharing_password           | string            | No       | Shared View password value                      |
| sharing_show_toolbar       | boolean           | No       | Shared View toolbar toggle                      |
| solution                   | string            | No       | Id of the App Solution containing the View      |
| state                      | view state object | Yes      | View state configuration                        |
| label                      | string            | No       | Display name of the View                        |
| view_mode                  | string            | No       | View mode                                       |
| order                      | number            | No       | Display order of the View in the View list      |

## State Object Properties

| Property                      | Data Type | Description                                        |
| ----------------------------- | --------- | -------------------------------------------------- |
| filterWindow                  | Object    | The filter window settings                         |
| filterWindow.opened           | Boolean   | Indicates if the filter window is opened or closed |
| filterWindow.filter           | Object    | The filter settings                                |
| filterWindow.filter.operator  | String    | The operator used for filtering                    |
| filterWindow.filter.fields    | Array     | The array of fields used for filtering             |
| fieldsWindow                  | Object    | The fields window settings                         |
| fieldsWindow.visibleFields    | Array     | The array of fields that are visible               |
| fieldsWindow.fixedFieldsCount | Number    | The number of fixed fields                         |
| fieldsWindow.columnsWidth     | Object    | The object containing the widths of columns        |
| fieldsWindow.collapsed        | Array     | The array of collapsed fields                      |
| sortWindow                    | Object    | The sort window settings                           |
| sortWindow.sort               | Array     | The array of sort settings                         |
| groupbyWindow                 | Object    | The group by window settings                       |
| cardSizeWindow                | Object    | The card size window settings                      |
| rowSizeWindow                 | Object    | The row size window settings                       |
| stackByWindow                 | Object    | The stack by window settings (for Kanban)          |
| calendarFieldsWindow          | Object    | The calendar fields window settings                |
| timelineFieldsWindow          | Object    | The timeline fields window settings                |
| chartSettings                 | Object    | The chart settings                                 |
| isToolbarVisible              | Boolean   | Indicates whether the toolbar is visible           |

## State Object Example

```json
{
  "filterWindow": {
    "opened": false,
    "filter": {
      "operator": "and",
      "fields": []
    }
  },
  "fieldsWindow": {
    "visibleFields": ["title"],
    "fixedFieldsCount": 1,
    "columnsWidth": {},
    "collapsed": []
  },
  "aggregates": {},
  "coverWindow": null,
  "sortWindow": {
    "sort": []
  },
  "groupbyWindow": {
    "collapsed": {},
    "group": []
  },
  "spotlightWindow": {
    "spotlights": []
  },
  "cardSizeWindow": {
    "size": "s"
  },
  "rowSizeWindow": {
    "size": "compact",
    "previousSize": null
  },
  "isToolbarVisible": true
}
```
