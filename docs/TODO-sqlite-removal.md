# TODO: Remove SQLite Cache Layer

## Overview

The project currently has two cache implementations:
1. **SQLite cache** (`lib/smart_suite/cache/`) - Used by CLI/standalone mode
2. **PostgreSQL cache** (`app/services/cache/postgres_layer.rb`) - Used by hosted Rails deployment

This creates code duplication and maintenance burden. The decision is to **keep only PostgreSQL** and remove SQLite.

## Rationale

- **Simplicity**: One cache implementation is easier to maintain
- **Feature parity**: PostgreSQL now has all features (views caching, metadata, overdue flags, all filter operators)
- **Performance**: PostgreSQL cache is already performant enough (better than direct API calls)
- **Development**: For CLI/development, developers can run a local PostgreSQL instance

## Files to Remove

When removing SQLite cache, delete these files/directories:

```
lib/smart_suite/cache/
├── layer.rb           # SQLite cache layer (main)
├── metadata.rb        # Cache metadata
├── performance.rb     # Hit/miss tracking
├── migrations.rb      # Schema migrations
├── query.rb           # Query builder (SQLite)
└── schema.rb          # Dynamic schema handling

test/smartsuite/cache/
├── test_layer.rb
├── test_metadata.rb
├── test_migrations.rb
├── test_query.rb
└── test_schema.rb
```

## Files to Update

1. **`lib/smartsuite_client.rb`** - Remove SQLite cache initialization
2. **`smartsuite_server.rb`** - Configure PostgreSQL for CLI mode
3. **`Gemfile`** - Remove `sqlite3` gem (if only used for cache)
4. **`CLAUDE.md`** - Update architecture documentation
5. **`docs/architecture/`** - Update cache documentation

## Migration Steps

1. **Create PostgreSQL setup for CLI**
   - Docker Compose file for local PostgreSQL
   - Environment variable configuration
   - Setup script for first-time users

2. **Update SmartSuiteClient**
   - Remove conditional SQLite/PostgreSQL cache selection
   - Always use PostgresLayer

3. **Remove SQLite files**
   - Delete files listed above
   - Remove tests

4. **Update documentation**
   - Getting started guide
   - Development setup

5. **Test thoroughly**
   - Ensure all filter operators work
   - Verify cache hit/miss tracking
   - Test views caching
   - Test metadata storage

## Development Setup (Future)

For developers running locally:

```bash
# Start PostgreSQL (via Docker)
docker-compose up -d postgres

# Or use existing PostgreSQL
export DATABASE_URL=postgres://localhost:5432/smartsuite_dev

# Run the CLI
ruby smartsuite_server.rb
```

## Timeline

This is a future enhancement, not urgent. Complete when:
- Current PostgreSQL implementation is battle-tested in production
- No bugs reported with filter operations
- Team has bandwidth for the migration

## Related Issues

- Original PR: feature/postgres-cache-parity (this PR)
- Sentry issues fixed: SMARTSUITE-MCP-N, SMARTSUITE-MCP-H, SMARTSUITE-MCP-K
