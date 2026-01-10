# Rate Limits

The API is limited to 5 requests per second per API key. If you exceed this rate, you will receive a 429 status code and will need to wait 30 seconds before subsequent requests will succeed.

SmartSuite may change the enforced API rate limits or enforce additional types of limits in our sole discretion.

Upon receiving a 429 status code, API integrations should back-off and wait before retrying the API request.

If you anticipate a higher read volume, we recommend using a caching proxy.

This rate limit is the same for all plans and increased limits are not currently available.
