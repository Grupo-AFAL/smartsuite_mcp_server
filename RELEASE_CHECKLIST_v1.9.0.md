# Release Checklist - v1.9.0

## Pre-Release Verification ✅

- [x] All PR checks passing (markdown-lint, rubocop, test, reek, yard-coverage, bundler-audit, check-changelog)
- [x] PR #25 created and ready for review
- [x] CHANGELOG.md updated with all v1.9.0 changes
- [x] Version numbers consistent across all files (1.9.0)
- [x] All tests passing (492 tests, 1,715 assertions, 0 failures)
- [x] Code coverage meets baseline (81.19%)
- [x] Documentation updated (README, ROADMAP, CLAUDE.md, docs/api/records.md)
- [x] REFACTORING_REPORT.md created with code quality analysis

## Release Steps

### 1. Merge Pull Request
```bash
# Review and approve PR #25
# Merge using "Squash and merge" or "Create a merge commit" (your preference)
gh pr merge 25 --merge  # or --squash
```

### 2. Update Main Branch
```bash
git checkout main
git pull origin main
```

### 3. Update CHANGELOG Release Date
```bash
# Edit CHANGELOG.md
# Change: ## [Unreleased]
# To:     ## [1.9.0] - YYYY-MM-DD
```

**Example:**
```markdown
## [1.9.0] - 2025-11-18
```

### 4. Commit CHANGELOG Update
```bash
git add CHANGELOG.md
git commit -m "chore: Prepare v1.9.0 release

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin main
```

### 5. Create Release Tag
```bash
git tag -a v1.9.0 -m "Release v1.9.0 - Extended Record Operations

New Features:
- Bulk record operations (bulk_add, bulk_update, bulk_delete)
- File URL retrieval for attachments
- Deleted records management (list, restore)

Improvements:
- Test helper methods for DRY tests
- Schema constants in ToolRegistry
- Comprehensive test coverage (27 new tests)

Breaking Changes:
- Removed bypass_cache parameter from all operations
- Sort behavior now applies all criteria consistently

See CHANGELOG.md for complete details."

git push origin v1.9.0
```

### 6. Create GitHub Release
```bash
gh release create v1.9.0 \
  --title "v1.9.0 - Extended Record Operations" \
  --notes-file <(cat <<'EOF'
## 🚀 New Features

### Bulk Record Operations
Efficiently process multiple records in a single API call:
- **bulk_add_records**: Create multiple records at once
- **bulk_update_records**: Update multiple records at once
- **bulk_delete_records**: Soft delete multiple records at once

### File Management
- **get_file_url**: Get public URLs for file attachments (20-year lifetime)

### Deleted Records Management
- **list_deleted_records**: View all soft-deleted records from a solution
- **restore_deleted_record**: Restore deleted records back to tables

## 🔧 Improvements

### Code Quality
- **Test helper methods**: Reduced test duplication by 55 lines
- **Schema constants**: 8 reusable constants eliminate 35 lines of duplication
- **Comprehensive tests**: 27 new tests with 100% coverage of new operations

## 💥 Breaking Changes

⚠️ **bypass_cache parameter removed**
- Removed from: `list_records`, `list_tables`, `list_solutions`
- Migration: Remove any `bypass_cache: true` arguments
- Cache expires naturally by TTL (4 hours default)

⚠️ **Sort behavior now consistent**
- Previously: Only first sort criterion applied when cache enabled
- Now: All sort criteria applied regardless of cache state

## 📊 Metrics

- **Test Coverage**: 78.22%
- **Total Tests**: 498 tests, 1,733 assertions
- **Code Reduction**: 90 lines eliminated through refactoring
- **New Operations**: 7 record operations
- **New Tests**: 33 comprehensive test cases

## 📚 Documentation

- Complete API reference for all 7 operations
- Updated user guide and architecture docs
- Refactoring opportunities report
- SecureFileAttacher setup guide

See [CHANGELOG.md](https://github.com/Grupo-AFAL/smartsuite_mcp_server/blob/main/CHANGELOG.md) for complete details.
EOF
)
```

### 7. Update CHANGELOG for Next Development Cycle
```bash
# Edit CHANGELOG.md
# Add new [Unreleased] section at top:
```

```markdown
## [Unreleased]

### Added

### Changed

### Removed

### Fixed

## [1.9.0] - 2025-11-18
...
```

### 8. Commit Unreleased Section
```bash
git add CHANGELOG.md
git commit -m "chore: Prepare CHANGELOG for next development cycle

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin main
```

### 9. Verify Release
```bash
# Check GitHub release page
gh release view v1.9.0

# Check tags
git tag -l "v1.9*"

# Verify CHANGELOG
head -50 CHANGELOG.md
```

### 10. Announce Release (Optional)
- Post in team Slack/Discord
- Update project documentation sites
- Notify users who requested these features

## Post-Release Verification

- [ ] GitHub release created and visible
- [ ] Release notes accurate and complete
- [ ] Tag pushed to remote
- [ ] CHANGELOG.md has [Unreleased] section for next cycle
- [ ] All documentation reflects v1.9.0
- [ ] No broken links in release notes

## Rollback Procedure (if needed)

If critical issues discovered after release:

```bash
# Delete remote tag
git push --delete origin v1.9.0

# Delete local tag
git tag -d v1.9.0

# Delete GitHub release
gh release delete v1.9.0

# Revert commits if necessary
git revert <commit-sha>
git push origin main
```

## Next Steps After v1.9.0

See [ROADMAP.md](ROADMAP.md) for v1.10 and v2.0 planning:
- View operations enhancement
- Additional SmartSuite API coverage
- Performance optimizations
- Token usage improvements

---

**Release Manager**: Federico
**Release Date**: TBD (after PR merge)
**Release Branch**: feature/implement-all-record-operations
**Pull Request**: #25
