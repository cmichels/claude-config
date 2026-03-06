---
description: Comprehensive code review for a single Go project. Analyzes structure, dependencies, code quality, security, tests, and patterns. Outputs project-review.md with prioritized findings.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding. If a path is provided, use it. Otherwise, use the current working directory.

## Goal

Perform a thorough review of a single Go project, identifying issues across structure, dependencies, code quality, security, testing, and patterns. Produce an actionable `project-review.md` report with prioritized findings.

## Prerequisites

- Project must contain a `go.mod` file
- Project should follow standard Go layout (cmd/, internal/, pkg/)

## Severity Definitions

| Severity | Description | Examples |
|----------|-------------|----------|
| **P0-Critical** | Security vulnerabilities, data loss risks, breaking bugs | SQL injection, secrets in code, race conditions, goroutine leaks |
| **P1-High** | Bugs, performance issues, missing error handling | Ignored errors, no context propagation, panics in handlers |
| **P2-Medium** | Code smells, naming issues, missing tests | Untidy go.mod, magic numbers, poor error messages |
| **P3-Low** | Style, documentation, minor refactors | Naming conventions, missing godoc, verbose code |
| **Info** | Observations, patterns identified, suggestions | Design patterns found, architecture notes |

## Execution Phases

### Phase 1: Validate Project Structure

1. Verify `go.mod` exists in target directory
2. Check for standard Go project layout:
   - `cmd/` - Application entry points
   - `internal/` - Private application code
   - `pkg/` - Public libraries (optional)
3. Check for essential files:
   - `README.md`
   - `Dockerfile`
   - `.gitignore`
   - `go.sum`
4. Record structure findings

### Phase 2: Dependency Analysis

Run these commands to analyze dependencies:

```bash
# Check for available updates
go list -m -u all

# Verify go.mod is tidy
go mod tidy -diff

# Check for security vulnerabilities
govulncheck ./...

# Show dependency graph (for analysis)
go mod graph | head -50
```

For each major dependency found (gin, pgx, zap, viper, testify, kafka-go, redis, etc.):
- Use **Context7 MCP** (`resolve-library-id` then `query-docs`) to lookup current best practices
- Compare project usage against documented patterns
- Flag deprecated APIs or outdated patterns

Record findings:
- Dependencies needing updates (security vs feature)
- Vulnerable dependencies with CVE details
- Deprecated or abandoned packages
- Unnecessary dependencies
- Replace directives that need review

### Phase 3: Static Analysis (Run in Parallel)

Execute these linters:

```bash
# Primary linter suite
golangci-lint run --out-format=json ./...

# Go vet for correctness
go vet ./...

# Additional static analysis
staticcheck ./...
```

If `golangci-lint` is not available, use individual linters:
```bash
go vet ./...
gofmt -d .
```

Record all findings with file locations and severity.

### Phase 4: Security Scan

Check for:
- Hardcoded secrets (API keys, passwords, tokens)
- SQL injection vulnerabilities (string concatenation in queries)
- Command injection risks
- Insecure random number generation
- Missing input validation
- Sensitive data in logs

Use grep patterns:
```bash
# Look for potential hardcoded secrets
grep -rn "password\s*=\s*\"" --include="*.go" .
grep -rn "apikey\s*=\s*\"" --include="*.go" .
grep -rn "secret\s*=\s*\"" --include="*.go" .

# Look for SQL string concatenation
grep -rn "fmt.Sprintf.*SELECT\|fmt.Sprintf.*INSERT\|fmt.Sprintf.*UPDATE\|fmt.Sprintf.*DELETE" --include="*.go" .
```

### Phase 5: Test Analysis

Run tests with coverage and race detection:

```bash
# Run tests with race detection and coverage
go test -race -coverprofile=coverage.out ./...

# Generate coverage report
go tool cover -func=coverage.out
```

Analyze:
- Overall coverage percentage
- Packages with low or no coverage
- Missing edge case tests
- Test quality (table-driven, proper assertions)
- Test isolation (parallel safety)

Use the **test-coverage-review agent** for deeper test analysis if coverage is below 50%.

### Phase 6: Deep Code Review

Use the **godaddy agent** to perform deep analysis of each major package. Focus on:

**Error Handling:**
- [ ] Errors wrapped with context (`fmt.Errorf("...: %w", err)`)
- [ ] No ignored errors (`_ = someFunc()`)
- [ ] Sentinel errors defined appropriately
- [ ] Custom error types where needed

**Concurrency:**
- [ ] Context propagated through call chain
- [ ] Goroutines have exit conditions
- [ ] Channels properly closed
- [ ] No race conditions
- [ ] Proper use of sync primitives

**Code Quality:**
- [ ] No magic numbers (use constants)
- [ ] No inline strings (use constants for messages)
- [ ] Descriptive variable/function names
- [ ] Functions are focused (<50 lines ideal)
- [ ] No dead/unused code
- [ ] No TODO/FIXME without ticket reference

**Logging:**
- [ ] Structured logging (zap/zerolog preferred)
- [ ] Appropriate log levels
- [ ] Context fields included
- [ ] No sensitive data logged

**Configuration:**
- [ ] Environment variables validated
- [ ] Config structs with defaults
- [ ] No hardcoded configuration values

**Performance:**
- [ ] No string concatenation in loops
- [ ] Preallocated slices where size is known
- [ ] Efficient JSON handling
- [ ] Connection pooling configured
- [ ] Proper use of sync.Pool for hot paths

For each issue found, use **Context7 MCP** to verify against current library documentation and best practices.

### Phase 7: Dockerfile Review

If Dockerfile exists:
- Check for multi-stage build pattern
- Verify minimal base image (alpine/scratch/distroless)
- Check for proper layer caching (go.mod before source)
- Verify CGO_ENABLED=0 for static binaries
- Check for -ldflags='-w -s' for size reduction
- Verify non-root user for runtime
- Check for .dockerignore

Use **go-dockerfile-converter agent** if Dockerfile needs optimization.

### Phase 8: Pattern Detection

Identify and document:

**Good Patterns Found:**
- Repository pattern
- Functional options pattern
- Handler middleware chains
- Graceful shutdown handling
- Health check endpoints
- Structured error types
- Dependency injection

**Anti-Patterns to Flag:**
- Empty error checks without context
- Naked returns in long functions
- Context.Background() in request handlers
- Global state / init() abuse
- Panic in library code
- String concatenation in loops
- Unbounded goroutines
- Missing defer for cleanup

## Output Format

Generate `project-review.md` in the project root with this structure:

```markdown
# Project Review: [PROJECT_NAME]

**Path:** [PROJECT_PATH]
**Reviewed:** [DATE]
**Go Version:** [VERSION from go.mod]

## Executive Summary

| Metric | Value | Status |
|--------|-------|--------|
| Structure | cmd/internal/pkg | ✓ / ⚠ / ✗ |
| Dependencies | N direct, M indirect | |
| Deps Needing Update | N | |
| Vulnerabilities | N | |
| Lint Issues | N | |
| Test Coverage | X% | |
| P0 Issues | N | 🔴 |
| P1 Issues | N | 🟠 |
| P2 Issues | N | 🟡 |
| P3 Issues | N | 🔵 |

### Top 3 Areas Needing Attention
1. [Area 1]
2. [Area 2]
3. [Area 3]

### Quick Wins (Easy fixes, high impact)
1. [Quick win 1]
2. [Quick win 2]

---

## Dependency Status

### 🔴 Security Updates Required
| Dependency | Current | Latest | CVE | Severity |
|------------|---------|--------|-----|----------|

### 🟠 Updates Available
| Dependency | Current | Latest | Type | Breaking |
|------------|---------|--------|------|----------|

### ⚠️ Deprecated/Abandoned
| Dependency | Issue | Recommended Replacement |
|------------|-------|------------------------|

### ✅ Healthy Dependencies
- [dep]: vX.Y.Z ✓

---

## Critical Issues (P0) - Fix Immediately

| ID | Location | Issue | Fix |
|----|----------|-------|-----|

---

## High Priority (P1) - Fix Soon

| ID | Location | Issue | Fix |
|----|----------|-------|-----|

---

## Medium Priority (P2) - Plan to Fix

| ID | Location | Issue | Fix |
|----|----------|-------|-----|

---

## Low Priority (P3) - Consider

| ID | Location | Issue | Fix |
|----|----------|-------|-----|

---

## Test Coverage Analysis

| Package | Coverage | Status |
|---------|----------|--------|

### Missing Test Coverage
- [List packages/functions needing tests]

### Test Quality Notes
- [Observations about test patterns]

---

## Pattern Analysis

### ✅ Good Patterns Identified
| Pattern | Location | Notes |
|---------|----------|-------|

### ⚠️ Anti-Patterns Found
| Anti-Pattern | Location | Recommendation |
|--------------|----------|----------------|

---

## Dockerfile Review

| Check | Status | Notes |
|-------|--------|-------|
| Multi-stage build | ✓/✗ | |
| Minimal base image | ✓/✗ | |
| Layer caching | ✓/✗ | |
| Static binary | ✓/✗ | |
| Non-root user | ✓/✗ | |
| .dockerignore | ✓/✗ | |

---

## Recommendations

### Immediate Actions (This Sprint)
1. [Action with specific steps]

### Short-term (Next 2-4 weeks)
1. [Action]

### Long-term (Technical Debt)
1. [Action]

---

## Appendix: Design Patterns for CLAUDE.md

Add this to the project's CLAUDE.md:

\`\`\`markdown
## Design Patterns

This project uses the following patterns:
- [Pattern]: [Location and usage]

## Key Dependencies
- [dep] vX.Y.Z: [Purpose]

## Code Conventions
- [Convention]: [Description]
\`\`\`
```

## Tool Usage Reference

| Phase | Tool | Purpose |
|-------|------|---------|
| Structure | Glob, Read | Verify project layout |
| Dependencies | Bash | go list, govulncheck |
| Dependencies | Context7 MCP | Lookup best practices for major deps |
| Linting | Bash | golangci-lint, go vet, staticcheck |
| Security | Grep | Pattern matching for secrets/vulnerabilities |
| Tests | Bash | go test with coverage |
| Tests | test-coverage-review agent | Deep test analysis |
| Deep Review | godaddy agent | Go-specific code review |
| Deep Review | Context7 MCP | Validate patterns against docs |
| Dockerfile | go-dockerfile-converter agent | Dockerfile optimization |
| Code Smells | code-smell-detector agent | Anti-pattern detection |
| Report | Write | Generate project-review.md |

## Context7 Usage Guide

When reviewing dependencies, use Context7 to validate usage:

1. **Resolve library ID first:**
```
Tool: mcp__context7__resolve-library-id
libraryName: "gin-gonic/gin"
query: "middleware error handling best practices"
```

2. **Query documentation:**
```
Tool: mcp__context7__query-docs
libraryId: "/gin-gonic/gin"
query: "how to properly handle errors in middleware"
```

**Common libraries to lookup:**
- `gin-gonic/gin` - HTTP framework patterns
- `jackc/pgx` - PostgreSQL connection handling
- `uber-go/zap` - Structured logging
- `spf13/viper` - Configuration management
- `stretchr/testify` - Testing patterns
- `segmentio/kafka-go` - Kafka consumer patterns
- `go-redis/redis` - Redis connection management

## Operating Principles

1. **Be thorough but efficient** - Run automated tools first, then deep review
2. **Prioritize actionable findings** - Every issue should have a clear fix
3. **Use Context7 for validation** - Don't guess, verify against current docs
4. **Respect existing patterns** - Note good practices, not just problems
5. **Generate actionable output** - Report should be a todo list, not just findings

## Error Handling

- If `go.mod` not found: Report error and exit
- If linters not installed: Use fallback commands, note in report
- If tests fail: Still generate coverage report, note failures
- If Dockerfile missing: Skip Phase 7, note in report

## Context

$ARGUMENTS
