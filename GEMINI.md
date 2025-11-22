# GEMINI.md

## Project Overview

This project is a Model Context Protocol (MCP) server for SmartSuite. It's a Ruby application that acts as a bridge between an AI assistant (like Claude) and the SmartSuite API. The server allows the AI assistant to interact with a user's SmartSuite workspace using natural language.

Key features include:

- **Comprehensive SmartSuite API Coverage:** Provides an interface to most of the SmartSuite API, including managing solutions, tables, records, fields, and more.
- **Aggressive Caching:** Uses a SQLite-based caching layer to reduce API calls and improve performance.
- **Token Optimization:** Filters and formats responses to minimize token usage.
- **Session and API Usage Tracking:** Monitors API usage by user, session, and endpoint.

The main entry point of the application is `smartsuite_server.rb`, which starts a server that listens for JSON-RPC 2.0 requests on standard input. The core logic for interacting with the SmartSuite API is encapsulated in the `SmartSuiteClient` class (`lib/smartsuite_client.rb`), which is organized into several modules for different API resources.

## Building and Running

### Dependencies

The project uses Ruby and manages its dependencies with Bundler. To install the required gems, run:

```bash
bundle install
```

### Running the Server

The server can be started by running the `smartsuite_server.rb` script:

```bash
ruby smartsuite_server.rb
```

The server requires two environment variables to be set for authentication with the SmartSuite API:

- `SMARTSUITE_API_KEY`: Your SmartSuite API key.
- `SMARTSUITE_ACCOUNT_ID`: Your SmartSuite account ID.

These can be set in a `.env` file or directly in the shell:

```bash
export SMARTSUITE_API_KEY="your_api_key"
export SMARTSUITE_ACCOUNT_ID="your_account_id"
```

### Testing

The project uses `minitest` for testing. To run the test suite, use the following command:

```bash
bundle exec rake test
```

## Development Conventions

- **Code Style:** The project uses RuboCop for code style enforcement. The configuration is in `.rubocop.yml`.
- **Testing:** Tests are written using `minitest` and are located in the `test/` directory. The test setup is in `test/test_helper.rb`.
- **Documentation:** The project has extensive documentation in the `docs/` directory, including API references, guides, and architectural overviews.
- **Contributing:** Contribution guidelines are outlined in `CONTRIBUTING.md`.

## Git Workflow

When implementing any change, adhere to the following workflow:

1. **Create a Branch:**

   - Start by creating a new branch with a descriptive name and a prefix based on the type of work:
     - `feature/` for new capabilities.
     - `fix/` for bug repairs.
     - `refactor/` for code restructuring without behavioral changes.
     - `docs/` for documentation updates.
     - `test/` for adding or updating tests.
     - `chore/` for maintenance tasks.
   - Example: `git checkout -b feature/add-user-authentication`

2. **Implement and Commit:**

   - Make your changes in the branch.
   - Commit changes with clear, concise messages.

3. **Verify (Local):**

   - Ensure all tests pass: `bundle exec rake test`
   - Verify code style/linting if applicable.
   - Confirm that the changes meet the requirements.

4. **Push to Remote:**

   - Push the commits to the origin: `git push origin <branch_name>`

5. **Create Pull Request (PR):**

   - Create a Pull Request using the GitHub CLI (`gh pr create`) if available, or provide the link for the user to create it.
   - Provide a clear title and description of the changes.

6. **Ensure Checks Pass:**

   - Monitor the Pull Request checks (CI/CD, linting, tests).
   - If any checks fail, analyze the errors, implement fixes, commit, and push updates to the branch.
   - Repeat until all checks pass.

7. **Stop and Await Review:**
   - **DO NOT MERGE.**
   - Inform the user that the PR has been created (or the branch pushed) and is ready for review.
   - The user will review the PR and merge it manually.
