# Comment Object

## Example

```json
{
  "solution": "640a3811c9d3ea77099331e2",
  "application": "640a3811c9d3ea77099331e7",
  "record": "640a385d0a86e2924f8dd382",
  "member": "63a1f65723aaf6bcb564b1f1",
  "message": {
    "data": {
      "type": "doc",
      "content": [
        {
          "type": "paragraph",
          "attrs": { "textAlign": null },
          "content": [
            { "type": "text", "text": "test" }
          ]
        }
      ]
    },
    "html": "<div class=\\"rendered\\">\\n <p>test</p>\\n</div>",
    "preview": "test"
  },
  "parent_comment": null,
  "created_on": "2023-03-20T12:49:05.832000Z",
  "deleted_on": null,
  "updated_on": null,
  "reactions": [],
  "key": 1,
  "assigned_to": null,
  "resolved_by": null,
  "followers": ["63a1f65723aaf6bcb564b1f1"],
  "type": "comment",
  "email": null,
  "id": "64185642174d214da05fa9c2"
}
```

## Object Literals

| Param          | Type             | Nullable | Description                                   |
| -------------- | ---------------- | -------- | --------------------------------------------- |
| solution       | string           | No       | The Solution Id                               |
| application    | string           | No       | The Table (app) Id                            |
| record         | string           | No       | The Record Id                                 |
| member         | string           | No       | The Member Id who created the comment         |
| message        | object           | No       | A SmartDoc object containing the comment body |
| parent_comment | string           | Yes      | Parent comment Id if this is a reply          |
| created_on     | string           | No       | ISO date created                              |
| deleted_on     | string           | Yes      | ISO date deleted                              |
| updated_on     | object           | Yes      | ISO date updated                              |
| reactions      | array of strings | No       | Reactions on the comment                      |
| key            | number           | No       | Comment key number                            |
| assigned_to    | string           | Yes      | Member Id if comment is assigned              |
| resolved_by    | string           | Yes      | Member Id who resolved the comment            |
| followers      | array of strings | No       | Array of following Member Ids                 |
| type           | string           | No       | Set to "comment" or "email"                   |
| email          | string           | Yes      | Email address (if email comment)              |
| id             | string           | No       | Unique Id of the comment                      |
