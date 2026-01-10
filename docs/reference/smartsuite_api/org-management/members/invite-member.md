# Invite Member

**POST** `https://app.smartsuite.com/api/v1/invite/`

Invite a new Member to join your SmartSuite Workspace.

## Example Request

```bash
curl -X POST https://app.smartsuite.com/api/v1/invite/ \\
  -H "Authorization: Token YOUR_API_KEY" \\
  -H "ACCOUNT-ID: snbvtl7z" \\
  -H "Content-Type: application/json" \\
  --data '{
    "emails": ["peter@smartsuite.com"],
    "role": "1",
    "type": "5",
    "teams": ["63f7a0f59f4259e9e63ad0bd"],
    "invited_to": "s25rfeyz"
  }'
```

## Request Body

| Param      | Type             | Description               |
| ---------- | ---------------- | ------------------------- |
| emails     | array of strings | Email addresses to invite |
| role       | string           | Member role (see below)   |
| type       | string           | Member type (see below)   |
| teams      | array of strings | Team Ids to add member to |
| invited_to | string           | Workspace Id to invite to |

## Member Roles

| Value | Role             |
| ----- | ---------------- |
| 1     | ADMIN            |
| 2     | SOLUTION_MANAGER |
| 3     | GENERAL          |
| 4     | SYSTEM           |
| 5     | GUEST            |

## Member Types

| Value | Type       |
| ----- | ---------- |
| 1     | EMPLOYEE   |
| 2     | CONTRACTOR |
| 3     | CONSULTANT |
| 4     | CLIENT     |
| 5     | VENDOR     |
| 6     | OTHER      |
