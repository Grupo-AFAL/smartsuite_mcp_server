# Member Object

## Object Literals

| Param               | Type                              | Nullable | Description                                                                                         |
| ------------------- | --------------------------------- | -------- | --------------------------------------------------------------------------------------------------- |
| application_id      | string                            | No       | Id of Members application                                                                           |
| availability_status | availability status object        | No       | Member's availability status                                                                        |
| comments_count      | number                            | No       | Total comments made by the Member                                                                   |
| first_created       | first created object              | No       | Date and Member who created the Member record                                                       |
| last_updated        | last updated object               | No       | Date and Member who last updated the Member record                                                  |
| ranking             | ranking object                    | No       |                                                                                                     |
| id                  | string                            | No       | Member's record id                                                                                  |
| application_slug    | string                            | No       | Always set to members                                                                               |
| deleted_date        | date object                       | Yes      | Date Member was deleted                                                                             |
| full_name           | full name object                  | No       | Name of the Member                                                                                  |
| company_name        | string                            | No       | Member's company name                                                                               |
| department          | string                            | No       | Member's department name                                                                            |
| about_me            | string                            | No       | Member's about text                                                                                 |
| job_title           | string                            | No       | Member's job title                                                                                  |
| email               | array of strings                  | No       | Member's email address                                                                              |
| type                | number                            | No       | Member's user type: EMPLOYEE = 1, CONTRACTOR = 2, CONSULTANT = 3, CLIENT = 4, VENDOR = 5, OTHER = 6 |
| role                | number                            | No       | Member's role type: ADMIN = 1, SOLUTION_MANAGER = 2, GENERAL = 3, SYSTEM = 4, GUEST = 5             |
| locale              | string                            | No       | Member's locale                                                                                     |
| timezone            | string                            | No       | Member's time zone                                                                                  |
| language            | string                            | No       | Member's language (2 character abbreviation)                                                        |
| office_location     | office location object            | No       | Member's office location                                                                            |
| work_anniversary    | date object                       | No       | Member's work anniversary                                                                           |
| certifications      | array of strings                  | No       | Member's professional certifications                                                                |
| skills              | array of strings                  | No       | Member's skills                                                                                     |
| hobbies             | array of strings                  | No       | Member's hobbies                                                                                    |
| linkedin            | array of strings                  | No       | Member's linkedin                                                                                   |
| twitter             | array of strings                  | No       | Member's twitter                                                                                    |
| facebook            | array of strings                  | No       | Member's facebook                                                                                   |
| instagram           | array of strings                  | No       | Member's instagram                                                                                  |
| theme               | string                            | No       | Member's selected theme                                                                             |
| dob                 | date object                       | No       | Member's date of birth                                                                              |
| profile_image       | array of file objects             | No       | Member's profile image                                                                              |
| cover_image         | array of file objects             | No       | Member's cover image                                                                                |
| cover_template      | string                            | No       | Member's cover template id (as string)                                                              |
| biography           | array of file objects             | No       | Member's biography document                                                                         |
| phone               | array of phone objects            | No       | Member's phone number                                                                               |
| teams               | array of strings                  | No       | Ids of Member's Teams                                                                               |
| ip_address          | array of ip address field objects | No       | Member's IP address                                                                                 |
| last_login          | last login object                 | No       | Date and time Member last logged in                                                                 |
| status              | member status object              | No       | Member status                                                                                       |

## Example

```json
{
  "application_id": "63a1f65723aaf6bcb564b1f0",
  "availability_status": {
    "emoji": "",
    "status": "",
    "selected_interval": "",
    "clear_after": {
      "date": null,
      "include_time": false
    }
  },
  "comments_count": 0,
  "first_created": {
    "on": "2022-12-20T17:52:23.867000Z",
    "by": "63a1f65723aaf6bcb564b1f1"
  },
  "last_updated": {
    "by": "63a1f65723aaf6bcb564b1f1",
    "on": "2024-06-06T18:58:58.862000Z"
  },
  "ranking": {
    "default": "aagckvjtea"
  },
  "id": "63a1f65723aaf6bcb564b1f1",
  "application_slug": "members",
  "deleted_date": {
    "date": null
  },
  "full_name": {
    "title": "",
    "first_name": "Peter",
    "middle_name": "",
    "last_name": "Novosel",
    "sys_root": "Peter Novosel"
  },
  "company_name": "SmartSuite",
  "department": "Engineering",
  "about_me": "Peter is a Co-Founder and CTO of SmartSuite...",
  "job_title": "CTO",
  "email": ["peter@smartsuite.com"],
  "status": {
    "value": "1",
    "updated_on": "2022-12-20T17:52:24.804000Z"
  },
  "type": "1",
  "role": "1",
  "locale": "en-US",
  "timezone": "America/Chicago",
  "language": "en",
  "office_location": {
    "location_address": "15549 West 166th Street",
    "location_address2": "",
    "location_city": "Olathe",
    "location_state": "Kansas",
    "location_zip": "66062",
```
