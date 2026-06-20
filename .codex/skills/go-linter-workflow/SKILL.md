---
name: go-linter-workflow
description: Ensure completed Go changes satisfy this repository's golangci-lint rules from .golangci.yaml. Use after writing or refactoring Go code, or during reviews focused on formatting, lint, generated-code boundaries, and package-level verification.
---

# Go Linter Workflow

## Source Of Truth

The lint contract is `.golangci.yaml` at the repository root. Read it when a lint failure is unclear or when adding code that may hit strict rules.

This repository uses `golangci-lint` v2 config format and enables strict linters plus formatters:

- formatters include `goimports` and `golines`
- local line target is 120 characters through `golines`
- many correctness, style, security, complexity, SQL, test, and error linters are enabled

## Completion Rule

Go feature work is not complete until the relevant lint target passes after changes.

Before relying on lint results, confirm the installed `golangci-lint` binary can load the project's Go version. If `golangci-lint run` panics or fails with a message like `file requires newer Go version`, the linter binary was built with an older Go toolchain and must be upgraded/rebuilt before lint can be considered passing.

Prefer the narrowest meaningful lint run while iterating, then broaden when the change touches shared behavior:

```bash
golangci-lint run ./internal/infrastructure/repository/outbox-repository
golangci-lint run ./internal/delivery/worker/outbox-consumer
golangci-lint run ./internal/...
```

Use the same package scope as the related `go test` run unless the change is cross-cutting.

## Formatting

Before linting edited Go files:

- run `gofmt` on edited `.go` files
- run `goimports` or `golangci-lint fmt` when imports or long lines changed
- do not run Go formatters on Markdown, YAML, SQL, or generated non-Go files

If `golangci-lint` reports formatter failures, fix formatting rather than ignoring the formatter.

## Fixing Lint Failures

Fix the code instead of suppressing the linter by default.

Common local rules to remember:

- no deprecated UUID imports such as `github.com/gofrs/uuid`; prefer `github.com/google/uuid` unless generated code forces otherwise
- no pointer-to-interface patterns
- no unchecked errors, including type assertions
- no named returns
- no `init()` functions or mutable globals
- no embedded `sync.Mutex` / `sync.RWMutex`
- check `rows.Err()` after row iteration
- close SQL/HTTP resources
- avoid `SELECT *` in SQL and SQL builders
- keep switch/map handling exhaustive where enum-like values are involved
- avoid magic numbers unless configured or clearly named
- avoid overly long or cognitively complex functions
- use context-aware calls for HTTP and logging when a context is available

## Nolint Policy

Use `//nolint` only when there is a concrete false positive or a deliberate tradeoff.

The config requires:

- specific linter names
- an explanation for most `nolint` directives

Allowed no-explanation exceptions in config are only:

- `funlen`
- `gocognit`
- `golines`

Even for those, prefer a short explanation when it helps the next reader.

## Generated Code

Do not manually fix generated code unless the generation source is unavailable and the user accepts that tradeoff.

If lint fails inside generated files, first check whether the package has an established exclusion, generator step, or generated-code convention.

## Reporting

In the final response for Go code changes, state:

- which `golangci-lint run ...` command passed
- if lint could not be run, why
- if lint fails due to unrelated existing issues, summarize the first relevant failures and the package scope
