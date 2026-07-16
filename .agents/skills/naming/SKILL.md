---
name: naming
description: Choose or review intent-revealing names in Firestarter Go code. Use when the user asks to name or rename identifiers, when a refactor introduces new public concepts, or when variables, methods, types, packages, files, DTOs, enums, or helpers are genuinely ambiguous; do not load it for routine code whose names are already clear.
---

# Naming

Use this skill when choosing or reviewing names. Good names should make code understandable without comments that translate what the identifier really means.

## Core Rule

Name the concept, not the implementation accident.

Prefer names that answer:

- what domain or technical concept is this?
- what role does it play in this scope?
- why does this value or function exist?

Do not make names long for ceremony. A longer name is better only when it removes real ambiguity.

## Prefer

- domain words over technical placeholders
- precise nouns for values and types
- precise verbs for actions and state transitions
- names that make call sites read naturally
- short names only in tiny scopes where the meaning is obvious
- project and domain abbreviations only when they are already common

Examples:

```go
sortOrder := req.Order
tradableEvents := filterTradableEvents(events)
```

## Avoid

Avoid generic names unless the scope is tiny and the meaning is obvious:

- `data`
- `item`
- `value`
- `info`
- `result`
- `manager`
- `processor`
- `helper`
- `handler`
- `handle`

Avoid encoded type noise:

- `eventMapString`
- `listData`
- `requestObj`
- `eventSlice`

Avoid names that merely repeat the type:

```go
event := event.Event{}
request := CreateRequest{}
```

Use the role instead:

```go
marketEvent := event.Event{}
createReq := CreateRequest{}
```

## Variables

Variable names should fit their scope.

- one-line loop indexes can be short: `i`, `j`
- short loops over obvious collections can use singular names: `event` in `for _, event := range events`
- longer scopes need role names: `storedEvent`, `incomingEvent`, `marketEvent`
- booleans should read like predicates: `isFinal`, `hasMarkets`, `canRetry`
- maps and sets should reveal key and value meaning when not obvious

Bad:

```go
data := make(map[string]event.Event)
```

Better:

```go
eventsByID := make(map[string]event.Event)
```

## Functions And Methods

Function names should describe the operation at the call site.

Prefer:

- verb phrases for commands: `CreateOrder`, `MarkExpired`, `PublishEvents`
- predicate names for questions: `HasTradableMarkets`, `CanRetry`, `IsFinal`
- conversion names that show boundary direction: `toDomainOrder`, `toProviderRequest`

Avoid:

- `process`
- `handle`
- `do`
- `run`
- `prepare`
- `buildData`

Generic verbs can be acceptable only when the type or package gives enough context.

## Types And Interfaces

Types should name the concept they model.

- structs should be nouns: `Order`, `CreateOrderRequest`, `GatewayConfig`
- interfaces should describe required behavior, not the implementation
- avoid suffixes such as `Manager`, `Processor`, or `Helper` unless they are established project language
- avoid interface names that only mirror one implementation

Keep `Request` and `Response` suffixes for boundary DTOs and service/gateway method contracts where the project already uses that pattern.

## Packages And Files

Package names should be short, specific, and lower-case.

Avoid new packages named:

- `common`
- `util`
- `utils`
- `models`
- `helpers`

Name files by the concept or method pattern used in the package. Follow existing project layout and method-per-file rules when they apply.

## Final Check

Before finishing:

- Would the name still make sense after reading only the call site?
- Does the name describe domain meaning or role, not just type?
- Is a generic word hiding a more precise concept?
- Is the abbreviation common in this project?
- Did the name remove the need for an explanatory comment?
