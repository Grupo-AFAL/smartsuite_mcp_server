# Authentication

## Basics

SmartSuite's API uses token-based authentication, allowing users to authenticate API requests by inputting their tokens into the HTTP authorization header.

> **Note:** The header value should be formatted with the word Token, followed by a space, then the API token.
> Example: `Authorization: Token YOUR_TOKEN`

All API requests must be authenticated and made through HTTPS.

## Types of token

We currently support using API tokens and OAuth access tokens during the authentication process.

### API Tokens

API tokens are for personal development, like building an integration for yourself, your client, or your company. They can be created and managed from your account profile menu, just select API key.

API tokens act as your user account, and should be treated with the same care as passwords.

> **Note:** Only users with the Administrator role see API Token listed as a menu item in their user profile, but they exist for all users. Simply scroll down to the API Token section to access your key.

### OAuth Access Tokens

OAuth access tokens are recommended for building an integration where other users grant your service access to SmartSuite's API on their behalf. In this case, your integration is a third-party service with respect to SmartSuite.

After registering your integration with SmartSuite, tokens are available via the OAuth grant flow. Any integrations that allow other users to grant access to SmartSuite should use OAuth.
