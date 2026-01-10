# Create Solution

**POST** `https://app.smartsuite.com/api/v1/solutions/`

Creates a new Solution.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/solutions/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: WORKSPACE_ID" \\
  -H "Content-Type: application/json" \\
  --data '{
    "name": "New App",
    "logo_icon": "overline",
    "logo_color": "3A86FF"
  }'
```

## Request Body

| Param      | Type   | Optional | Description                             |
| ---------- | ------ | -------- | --------------------------------------- |
| name       | string | No       | The name of the App.                    |
| logo_icon  | string | No       | Material Design icon name               |
| logo_color | string | No       | Hex color for the icon (see list below) |

## Valid Solution Colors

| Color                   | Hex     |
| ----------------------- | ------- |
| Primary Blue            | #3A86FF |
| Primary Light Blue      | #4ECCFD |
| Primary Green           | #3EAC40 |
| Primary Red             | #FF5757 |
| Primary Orange          | #FF9210 |
| Primary Yellow          | #FFB938 |
| Primary Purple          | #883CD0 |
| Primary Pink            | #EC506E |
| Primary Teal            | #17C4C4 |
| Primary Grey            | #6A849B |
| Dark Primary Blue       | #0C41F3 |
| Dark Primary Light Blue | #00B3FA |
| Dark Primary Green      | #199A27 |
| Dark Primary Red        | #F1273F |
| Dark Primary Orange     | #FF702E |
| Dark Primary Yellow     | #FDA80D |
| Dark Primary Purple     | #673DB6 |
| Dark Primary Pink       | #CD286A |
| Dark Primary Teal       | #00B2A8 |
| Dark Primary Grey       | #50515B |
