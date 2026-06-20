---
name: go-code-style
description: Follow this repository's Go code style expectations, based on the official Uber Go Style Guide. Use when writing, refactoring, or reviewing Go implementation details where style choices matter, especially around errors, interfaces, DTOs, imports, concurrency, map/slice boundaries, initialization, and table-driven tests. For naming decisions, use `naming`. For helper extraction or function splitting decisions, use `function-decomposition`.
---

# Go Code Style

## Source

Follow the official Uber Go Style Guide:

- https://github.com/uber-go/guide/blob/master/style.md

Use this skill as the local checklist. If a question is subtle or not covered here, consult the official guide and prefer local repository conventions when they are stricter.

## Baseline

- Always run `gofmt` on edited Go files.
- Prefer `goimports` when import grouping or unused imports are involved.
- Keep code simple, explicit, and idiomatic.
- Match the surrounding package style unless it conflicts with this guide or project skills.
- Write the smallest code shape that fully solves the task.
- Prefer direct readability over cleverness, speculative extension points, or imaginary future performance.
- Do not add argument or field validation as a general code-style reflex. Validation placement is owned by the `field-validation` skill: validate field shape at first occurrence only, and do not repeat it through every layer.

## Interfaces

- Do not use pointers to interfaces.
- Accept interfaces and return concrete types when that keeps ownership clear.
- Verify interface compliance when a type is meant to satisfy an important contract:

```go
var _ repository.Outbox = (*Implementation)(nil)
```

## Errors

- Handle each error once.
- Wrap or classify errors at the lowest meaningful layer according to project error skills.
- Do not panic for normal error paths.
- Error strings should be lower-case and should not end with punctuation.
- Prefer specific error context over generic messages.

## Data Boundaries

- Copy slices, maps, and mutable byte-like values when crossing ownership boundaries.
- Do not expose internal mutable state from entities, DTOs, caches, or config.
- Use field tags only on structs that are actually marshaled, scanned, or bound by a tool using those tags.

## Concurrency

- Use `defer` for cleanup such as unlocks and closing resources.
- Do not fire-and-forget goroutines. Make lifecycle, cancellation, and error handling explicit.
- Channels should usually be unbuffered or size one; larger buffers need a concrete reason.
- Avoid mutable globals.
- Avoid `init()` unless there is no clearer explicit wiring path.

## Names And Layout

- For variable, function, type, package, file, DTO, and helper names, apply `naming`.
- Avoid names that shadow built-ins.
- Keep import groups ordered: standard library, third-party, local project.
- Use import aliases only when they improve clarity or avoid a real conflict.
- Group related declarations, but keep method-per-file notation when that skill applies.
- Reduce nesting with early returns.
- Do not use unnecessary `else` after a returning branch.
- For helper extraction, function splitting, or abstraction decisions, apply `function-decomposition`.

## Initialization

- Use field names when initializing structs unless the type is a tiny local value where positional initialization is obviously clearer.
- Omit zero-value fields from struct literals unless the zero value carries important meaning.
- Prefer `var value T` for zero-value structs.
- Prefer specifying capacity for slices and maps when the size is known.

## Performance Hygiene

- Prefer `strconv` over `fmt` for simple numeric/string conversions.
- Avoid repeated string/byte conversions in hot or repeated paths.
- Do not optimize at the cost of clarity unless there is a measured reason.
- Use maps, sets, sorting, batching, or concurrency when the data shape or task justifies them, not as default ornamentation.

## Tests

- Prefer table-driven tests for multiple cases.
- Keep test case names descriptive.
- Test behavior and boundary conditions, not implementation details.

## Review Checklist

Before finalizing Go changes, check:

- edited files are formatted
- errors are classified/wrapped consistently with project conventions
- no pointer-to-interface, avoidable globals, or unnecessary `init()`
- mutable boundary data is copied where ownership changes
- imports are clear
- names follow `naming`
- function decomposition decisions follow `function-decomposition`
- DTO tags are present only when used
- tests or compile checks cover the touched package
