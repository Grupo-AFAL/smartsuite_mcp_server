# SmartSuite REST API Documentation

This folder contains the complete REST API documentation for SmartSuite, extracted from the official developer documentation at https://developers.smartsuite.com.

## Structure

- **introduction.md** - API overview and introduction
- **authentication.md** - Authentication methods and API keys
- **errors.md** - Error codes and handling
- **rate-limits.md** - API rate limiting information

### Solution Data

- **records/** - Record operations (CRUD, bulk operations, files)
- **fields/** - Field management and field types
- **comments/** - Comment operations
- **tables/** - Table management
- **solutions/** - Solution management
- **views/** - View operations
- **webhooks/** - Webhook configuration and events

### Org Management

- **members/** - Member management
- **teams/** - Team management

## Base URL

```
https://app.smartsuite.com/api/v1/
```

## Authentication

All API requests require:

- `Authorization: Token YOUR_API_KEY` header
- `ACCOUNT-ID: WORKSPACE_ID` header

## Rate Limits

The API is limited to 5 requests per second per API key.
