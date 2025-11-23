# Evaluation: Migrating to the Official Ruby MCP SDK

## Executive Summary

This document evaluates the benefits, risks, and effort required to migrate the current `smartsuite_mcp` server implementation to the official [Ruby SDK for Model Context Protocol](https://github.com/modelcontextprotocol/ruby-sdk).

**Recommendation:** **Strongly Recommend Migration**
The current implementation manually handles the JSON-RPC 2.0 protocol, which is error-prone and maintenance-heavy. Adopting the official SDK will significantly reduce codebase size, improve reliability, and ensure future compatibility with MCP protocol updates.

---

## Current Implementation Status

The current `smartsuite_server.rb` and associated modules implement the MCP protocol "from scratch":

- **Protocol Handling:** Manually parses JSON from `STDIN`, checks for `jsonrpc` version, and handles `id` matching.
- **Routing:** A large `case` statement in `handle_request` manually routes methods (`tools/list`, `tools/call`, etc.).
- **Error Handling:** Manually constructs error objects with specific codes (e.g., `-32603`, `-32700`).
- **Tool definitions:** Tools are defined as raw Ruby hashes in `ToolRegistry`.

### Pros of Current Approach
- **Zero Dependencies:** No external gems required for the protocol itself.
- **Full Control:** Complete visibility into every byte of I/O.

### Cons of Current Approach
- **High Maintenance:** Any update to the MCP spec requires manual code changes.
- **Fragility:** Error handling and concurrency (if needed later) are difficult to get right manually.
- **Boilerplate:** `smartsuite_server.rb` contains significant boilerplate code (~160 lines) just to keep the server running.
- **Lack of Validation:** Input validation is largely manual or deferred to the API client.

---

## Benefits of Migrating to the SDK

The official `modelcontextprotocol-sdk` (or `mcp-sdk`) provides a standardized way to build servers.

### 1. Code Reduction and Simplification
The SDK abstracts away the JSON-RPC layer. The server loop, request parsing, and error formatting are handled automatically.

**Current:**
```ruby
loop do
  input = $stdin.gets
  request = JSON.parse(input)
  # ... manual dispatch ...
rescue JSON::ParserError => e
  # ... manual error construction ...
end
```

**With SDK (Conceptual):**
```ruby
server = MCP::Server.new(name: "smartsuite-server")

server.tool("list_solutions", "List solutions") do |args|
  # ... business logic ...
end

server.run
```

### 2. Protocol Compliance
The SDK is maintained to strictly adhere to the MCP specification. Using it ensures that edge cases (like notification handling, specific error codes, or future capabilities) are handled correctly without effort from our team.

### 3. Improved Type Safety and Validation
SDKs typically include schema validation. Instead of manually checking if `arguments['table_id']` exists, the SDK can validate incoming requests against the defined tool schema before the handler is even invoked.

### 4. Community and Ecosystem
Using the standard SDK makes it easier for other developers to contribute, as they will recognize the patterns (Tool definitions, Resource registrations) common to other MCP servers.

---

## Migration Plan

### Phase 1: Dependency and Setup
1. Add `gem 'mcp-sdk'` (or specific gem name found) to `Gemfile`.
2. Run `bundle install`.

### Phase 2: Refactoring Tool Definitions
The `ToolRegistry` currently returns raw hashes. This should be adapted to the SDK's builder pattern.

*Current:*
```ruby
{
  'name' => 'list_solutions',
  'inputSchema' => { ... }
}
```

*Target:*
```ruby
MCP::Tool.new(
  name: "list_solutions",
  description: "...",
  schema: { ... }
)
```

### Phase 3: Server Replacement
Replace `SmartSuiteServer` class with an SDK-derived implementation. Connect the existing `SmartSuiteClient` logic to the SDK's tool handlers.

### Phase 4: Validation
Run existing integration tests (`test/integration/test_integration.rb`) to ensure the external behavior (JSON I/O) remains identical.

## Risk Assessment

- **Dependency Risk:** The Ruby SDK might be in early stages (alpha/beta). *Mitigation:* Verify the SDK's maturity and activity level on GitHub before full commitment.
- **Breaking Changes:** The internal API of the SDK might change. *Mitigation:* Lock the gem version in `Gemfile`.

## Conclusion

Migrating is a strategic move to mature the project. It shifts focus from "maintaining a JSON-RPC server" to "building SmartSuite features," which is the core value proposition.
