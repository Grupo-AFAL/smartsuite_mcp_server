# Errors

The SmartSuite REST API follows HTTP status code semantics. 2xx codes signify success, 4xx mostly represent user error, 5xx generally correspond to a server error.

The error messages will return a JSON-encoded body that contains field ids and a string containing the error message. Those will provide specific error conditions and human-readable messages to identify the source of the error.

## Success code

| Code | Message | Description                     |
| ---- | ------- | ------------------------------- |
| 200  | OK      | Request completed successfully. |

## User error codes

| Code | Message         | Description                                                                                                                                                |
| ---- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 400  | Bad Request     | The request was invalid or could not be parsed.                                                                                                            |
| 401  | Unauthorized    | Provided credentials were invalid or do not have authorization to access the requested resource.                                                           |
| 403  | Forbidden       | Accessing a protected resource with API credentials that don't have access to that resource.                                                               |
| 404  | Not Found       | Route or resource is not found. This error is returned when the request hits an undefined route, or if the resource doesn't exist (e.g. has been deleted). |
| 422  | Invalid Request | The request data is invalid.                                                                                                                               |

## Server error codes

| Code | Message               | Description                                                                                                                                                                                     |
| ---- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 500  | Internal Server Error | The server encountered an unexpected condition.                                                                                                                                                 |
| 502  | Bad Gateway           | SmartSuite's servers are restarting or an unexpected outage is in progress. You should rarely encounter this error, and should retry requests if it is generated.                               |
| 503  | Service Unavailable   | The server could not process your request in time. The server could be temporarily unavailable, or it could have timed out processing your request. You should retry the request with backoffs. |
