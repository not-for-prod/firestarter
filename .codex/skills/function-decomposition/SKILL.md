---
name: function-decomposition
description: Decide whether code should stay inline, be split into helper functions, move to a domain/application/infrastructure owner, or become an abstraction. Use when writing or refactoring functions that are longer than about 60 lines, contain meaningful duplication, have hard-to-scan flow, or when Codex is tempted to extract helpers for readability.
---

# Function Decomposition

Use this skill to decide function shape. The goal is readable code with practical decomposition, not many small functions by default.

## Trigger Criteria

Apply this skill when at least one is true:

- a function or method is longer than about 60 lines
- meaningful code duplication appears
- nested branches make the main flow hard to scan
- a helper, interface, option, or abstraction is being considered
- a function mixes multiple ownership concepts
- a review comment says the code is over-decomposed, too clever, or hard to follow

The 60-line rule is a signal, not a hard limit. A straight-line orchestration function can be longer if it remains easier to read inline than split apart.

## Default

Default to keeping code inline.

Extract only when the extraction has a practical benefit:

- removes meaningful duplication
- names a real domain or business concept
- isolates a technical boundary such as parsing, persistence mapping, provider DTO conversion, signing, or transport mapping
- makes an already complex function easier to scan
- lets the main use case read clearly from top to bottom
- matches an established local pattern

Do not extract only because:

- code is a few lines long
- a block can be given a name
- "senior code" should have more helpers
- the helper might be reusable someday
- a linter-independent personal length target was exceeded

## Duplication Rule

Treat duplication as meaningful when duplicated code can change for the same reason.

Extract duplicated code when:

- two or more call sites repeat the same rule or conversion
- future changes would likely need to update all copies together
- the helper name can describe the shared concept precisely

Keep duplication inline when:

- the repeated lines are incidental setup
- the call sites are likely to diverge
- extraction would create a vague helper such as `prepareData`, `processItems`, or `handleResult`

## Long Function Review

When a function is longer than about 60 lines, classify why:

- straight-line orchestration: usually keep inline if each step is obvious
- repeated mechanics: extract a focused helper
- domain policy: move to the domain entity or value object
- provider, SQL, transport, or generated-model mechanics: move to the infrastructure boundary
- validation noise: apply `field-validation`; do not add validation at every level
- many unrelated responsibilities: split by real phases or ownership, not by arbitrary chunks

Do not split a readable function into trivial helpers that make readers jump around to understand simple steps.

## Helper Quality Bar

A helper should answer "why does this boundary exist?"

Good helper names usually describe:

- a domain question: `hasTradableMarkets`
- a state transition: `markExpired`
- a conversion boundary: `toDomainOrder`
- a provider operation: `signRequest`
- a repeated technical operation: `scanCursor`

Weak helper names usually describe mechanics without meaning:

- `buildData`
- `prepareRequest`
- `processItems`
- `handleResult`
- `doMapping`

Weak names are not automatically forbidden, but they are a signal to re-check whether the helper should exist or be named by a more precise concept.

## Abstraction Rule

Add an abstraction only when it removes real complexity or follows an existing project pattern.

Do not add an abstraction when:

- there is only one concrete implementation and no current need for another
- it hides simple explicit code
- it adds options, callbacks, hooks, or extension points not required by the task
- it crosses ownership boundaries to look reusable
- it makes call sites less clear

Prefer boring code that makes ownership obvious.

## Final Check

Before finishing:

- Can the main use case be read without jumping through trivial helpers?
- Does every extracted function have a practical reason to exist?
- Did any domain concept move to the domain layer instead of becoming an application helper?
- Did technical conversion or provider logic stay at the adapter boundary?
- Did validation placement remain governed by `field-validation`?
- Is the final code shorter to understand, not just shorter per function?
