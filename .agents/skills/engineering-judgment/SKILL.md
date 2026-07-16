---
name: engineering-judgment
description: Make first-pass design decisions for non-trivial Firestarter Go changes before applying narrower skills. Use only when ownership, abstraction shape, data flow, dependency choice, generated-code boundaries, or competing implementation approaches are genuinely uncertain; use `project-layout` for direct placement questions and skip this skill for routine or mechanical edits.
---

# Engineering Judgment

This is the first-pass programmer workflow. Use it to decide what kind of code should exist before applying narrower skills such as domain entities, application services, repositories, gateways, field validation, tracing, lint, or Go style.

The goal is not to add rules for every case. The goal is to make the first design decision explicit enough that code does not land in a package only because it was convenient.

## Workflow

1. Identify the real goal.
2. Inspect nearby code and local conventions.
3. Classify the code by the concept it owns.
4. Choose the smallest correct shape.
5. Apply the narrower skill for the chosen layer.
6. Use `function-decomposition` when deciding whether to split, inline, or extract helpers.
7. Review the diff for accidental scope, behavior, and ownership drift.

Ask the user only when ambiguity blocks safe progress or would likely produce the wrong behavior. Otherwise make the safest reasonable assumption and state it later.

## Feature Design Order

`deliver-feature` owns SDD, approvals, execution order, checkpoints, generation, and completion. This skill owns the design decision that precedes those tasks.

For a new business use case, reason from business meaning outward before choosing storage or transport shapes:

1. identify observable behavior, commands, queries, actors, and failure cases
2. determine aggregates, value objects, invariants, states, and domain events only where an event contract is needed
3. identify application orchestration, transaction boundaries, and domain-facing repository or gateway ports
4. decide how public contracts, persistence, providers, and delivery adapters support that model
5. use scratch event-storming notes when aggregate boundaries or asynchronous flow are not obvious

This is discovery order, not permission to implement ahead of an approved plan. For a non-trivial feature, follow `deliver-feature` and the SDD gates. Execution normally changes source contracts and schema first, regenerates outputs, then implements domain, application, infrastructure, delivery, and Fx wiring in the order approved by `plan.md`.

For a narrow change, skip the ceremony and apply the most specific skill directly. Still avoid letting database tables, protobuf DTOs, or provider responses define business concepts accidentally.

## Domain Interface Templates

When adding domain-layer interfaces, prefer the local GoLand file templates under `tools/goland/file-and-code-templates` instead of hand-writing the boilerplate:

- use `domain_infrastructure_interface` for repository and gateway interfaces under `internal/domain/repository` or `internal/domain/gateway`
- use `domain_service_interface` for service interfaces under `internal/domain/service`

These templates add the expected `go:generate` lines for mocks and implementation generation:

- `moq` for interface mocks
- `implgen` for the matching infrastructure or application implementation package

The template passes a base destination to `implgen`; the generator appends the kebab-case implementation package folder. For example, a `Payment` interface in package `repository` targets `internal/infrastructure/repository/payment-repository`, while a `Payment` service interface targets `internal/application/service/payment-service`.

After generating the interface file, edit only the domain-facing method signatures and request/response types needed by the use case. Do not leak xo, pgx, Resty, provider JSON, protobuf transport messages, or implementation details into the generated domain interface.

## Decision Tree: Where Does This Code Belong?

Start with the question the code answers.

### Is it a business question about one domain object?

Put it on the domain entity.

Examples:

- `Event.HasClobEnabledMarkets()`
- `Payment.IsFinal()`
- `Bet.CanBeBooked()`

Signals:

- the function only reads fields from one domain type
- the name uses domain language: active, ready, eligible, tradable, final, expired, allowed
- another use case could reasonably need the same question
- the implementation would not change if storage, transport, or provider changed

Do not keep this as an application helper only because the application service was the first caller.

### Is it a state transition or invariant?

Put it on the aggregate/domain entity as an intention-revealing method.

Examples:

- `Close`
- `Confirm`
- `Cancel`
- `MarkTransferred`

The application service should call the domain method and persist the result. It should not mutate lifecycle fields directly or manually construct lifecycle domain events.

### Is it use-case orchestration?

Put it in the application service.

Application services may:

- coordinate repositories, gateways, transactions, and domain methods
- decide command/query flow
- own the unit of work after a delivery handler, worker, cron job, or consumer selects the command
- load the affected aggregate or aggregate set, often with `FOR UPDATE`
- persist changed aggregates and publish returned domain events in one transaction
- publish domain events by business intent
- keep small helpers for use-case-specific request building or orchestration mechanics

Application services should not own SQL, provider DTOs, transport parsing, broker envelopes, polling loops, retry mechanics, or domain policy that belongs on entities.

If the input is naturally a batch, design a batch command and collection-shaped repository methods. Do not put a `for` loop in delivery that calls a single-item application command for every message/request when the same use case can load, transition, persist, and publish events as a batch.

### Is it transport/request parsing or first field validation?

Put it in delivery or at the first boundary where the DTO appears.

Examples:

- parse HTTP/gRPC request fields
- validate required request IDs
- map transport errors to protocol errors

Do not scatter the same field-shape validation across delivery, service, repository, and gateway.

### Is it persistence, provider, generated model, or transport mechanics?

Put it in infrastructure.

Examples:

- SQL construction
- xo/generated model conversion
- Resty request/response DTOs
- provider-specific JSON quirks
- auth headers and request signing
- outbox/broker envelopes

Infrastructure may convert technical shapes into real domain models. It should not invent pseudo-domain types that leak inward.

### Is it a polling, ack, retry, or dispatch loop?

Put it in delivery worker code.

Workers own loops and transport progress. Application services own business use cases called by those loops.

Worker code may batch, group, and map incoming payloads before calling an application command. It should not load aggregates, call aggregate transition methods, persist business state, or create lifecycle events.

### Is it reusable technical support?

Only put it in `internal/pkg` when it is provider-neutral, domain-neutral, and genuinely reusable.

`internal/pkg` is not a dumping ground for technical code that has no obvious home.

## Decision Tree: Should I Add a Helper?

Apply `function-decomposition` for detailed helper extraction and function splitting criteria.

Default to inline code unless the helper has clear ownership, removes meaningful duplication, names a real business concept, isolates a technical boundary, or makes a complex flow easier to scan.

Ownership shortcut:

- domain question about one entity: domain method
- use-case coordination: application helper
- transport, SQL, provider, or generated-model conversion: adapter helper
- two-to-five obvious lines: usually inline

Rule: if a helper only inspects one domain entity and answers a domain question, make it a domain method, not an application helper.

## Decision Tree: Should I Add an Abstraction?

Apply `function-decomposition` when an interface, option set, or other abstraction is being considered.

Add an abstraction only when it removes real complexity or matches an existing local pattern. Avoid abstractions that hide one concrete implementation, add unused hooks, cross ownership boundaries, or make call sites less explicit.

## Decision Tree: Should This Query Call a Gateway?

Default: queries read persisted state.

A query may call a gateway only when live external data is explicitly part of the use case and the result is not secretly importing missing data into the system.

Do not use read paths to backfill persisted state when polling, consumers, workers, or import jobs are the intended ingestion path.

Bad shape:

- `ListItems` reads repository results, calls an external provider to fill missing items, then saves those items asynchronously.

Good shape:

- `PollItems` imports provider items.
- `ListItems` reads persisted ready items.

Rule: do not hide writes, imports, or state convergence behind a method that reads like a query.

## Decision Tree: Where Does Config Logic Belong?

Config parsing and validation belongs at config load time. Application services should consume typed, trusted config values.

Do not parse strings, durations, URLs, addresses, timestamps, enums, or feature flags inside business orchestration code. By the time an application service runs, config should already be represented as the type the service needs.

Bad shape:

```go
pollEventsCfg := config.Instance().Worker.PollEvents
var startDateMin time.Time
if pollEventsCfg.StartDateMin != "" {
	startDateMin, err = time.Parse(time.RFC3339, pollEventsCfg.StartDateMin)
}
```

Good shape:

```go
pollEventsCfg := config.Instance().Worker.PollEvents

req := provider.ListItemsRequest{
	StartDateMin: pollEventsCfg.StartDateMin,
}
```

Rule: shared config structs should contain only fields shared by all users. If one worker, provider, gateway, or feature owns a setting, define a specific config type for that owner instead of adding one-off fields to the common struct. Name config fields by the domain/API concept they actually control; do not call an event start-date filter `CreatedAtGreaterThan`.

## Decision Tree: Should I Touch Generated Code, Migrations, or Dependencies?

Generated code:

- edit the source schema/migration/config first
- regenerate through the documented command
- do not manually patch generated output unless the repository explicitly expects it

Migrations:

- do not edit already-applied migrations unless project convention allows it
- prefer a new deploy-safe migration
- consider rollback, data safety, and deployment order

Dependencies:

- do not add a dependency by default
- check standard library and existing internal/project utilities first
- add one only when the task cannot be reasonably solved with the existing stack and the cost is justified
- do not upgrade unrelated dependencies

## Decision Tree: Is This Primitive Actually an Enum?

If a primitive value has a known set of valid meanings, define a typed enum instead of passing raw `string`, `int`, or `bool` values around.

Use typed enums for:

- provider query fields with documented allowed names
- domain states and statuses
- modes, kinds, categories, sides, directions, and order types
- transport options where only a known set is valid

Bad shape:

```go
type ListEventsRequest struct {
	Order []string
}

Order: []string{"startDate"}
```

Good shape:

```go
type ListEventsOrder string

const (
	ListEventsOrderStartDate ListEventsOrder = "startDate"
)

type ListEventsRequest struct {
	Order []ListEventsOrder
}
```

Rule: convert enums to provider strings only at the adapter boundary. Do not leak raw provider string literals into application services.

## Bad Code Signals

Pause and re-check design when you see:

- business-word helpers in application services: active, eligible, tradable, ready, final, expired, allowed, supported
- a function reading only one domain entity but living outside that entity
- provider DTOs, generated models, SQL, HTTP details, or broker envelopes leaking inward
- service methods that combine validation, mapping, orchestration, persistence, and domain policy in one block
- broad formatting, generation, dependency, lockfile, or schema churn unrelated to the task
- a refactor that deletes most of a file but leaves one helper behind from inertia
- code placed where dependencies are available instead of where the concept belongs
- a raw primitive represents a closed set of states, modes, fields, directions, or options
- quick fixes that weaken validation, authorization, authentication, privacy, payments, data integrity, or user trust

## Final Review

Before finishing:

1. Re-read the diff.
2. Confirm each changed file is relevant.
3. Confirm behavior changed only where intended.
4. Confirm helpers live with the concept they encode.
5. Confirm no generated files, lockfiles, schemas, migrations, or dependency versions changed accidentally.
6. Confirm no secrets, credentials, or local paths were added.
7. State important assumptions and verification performed.

## How To Enrich

When the project owner says code is bad, add a concise case here:

- bad shape
- why it is bad
- preferred shape
- general rule

Keep examples concrete. Remove or merge examples when they become redundant.
