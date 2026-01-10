# Add Comment

**POST** `https://app.smartsuite.com/api/v1/comments/?record=[Record_Id]`

Creates a comment. Returns a comment object.

## Example Request using SmartDoc object

```bash
curl -X POST https://app.smartsuite.com/api/v1/comments/?record=[Record_Id] \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "assigned_to": [Member Id or null],
    "message": {
      "data": {
        "type": "doc",
        "content": [
          {
            "type": "paragraph",
            "content": [
              {
                "type": "text",
                "text": "[Comment Text]"
              }
            ]
          }
        ]
      }
    },
    "parent_comment": "[Parent Comment Id if applicable]",
    "application": "[Table_Id]",
    "record": "[Record_Id]"
  }'
```

## Example Request using HTML

```bash
curl -X POST https://app.smartsuite.com/api/v1/comments/?record=[Record_Id] \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "assigned_to": [Member Id or null],
    "message": {
      "html": "<b>A test</b>"
    },
    "application": "[App_Id]",
    "record": "[Record_Id]"
  }'
```

## Request Parameter

| Param  | Type   | Description                                  |
| ------ | ------ | -------------------------------------------- |
| record | string | Record Id of the record to attach comment to |

## Request Body

| Param          | Type                   | Nullable | Description                                                           |
| -------------- | ---------------------- | -------- | --------------------------------------------------------------------- |
| assigned_to    | string                 | No       | Member Id or null for unassigned                                      |
| message        | comment content object | No       | The comment as either a SmartDoc object or html string (data or html) |
| parent_comment | array of objects       | No       | Parent comment Id if comment is a reply                               |
| application    | string                 | No       | Record's Table Id                                                     |
| record         | string                 | No       | Id of the record the comment should be associated with                |
