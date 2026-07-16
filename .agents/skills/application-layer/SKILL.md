---
name: application-layer
description: Design, implement, review, or refactor Firestarter application services under `internal/application`. Use when coordinating commands or queries from API handlers, workers, cron jobs, or consumers; owning transaction boundaries; calling domain repositories, gateways, and aggregate behavior; or publishing domain events when the feature has an established durable-event contract.
---

# Application Layer

## Overview

Use this skill when adding, refactoring, or reviewing application services.

The application layer is the business use-case coordinator. It is called by delivery code and coordinates:

- domain aggregates and domain behavior
- domain repository interfaces
- domain gateway interfaces
- transaction boundaries
- durable domain-event publication by business intent when the use case requires it
- query/read workflows that do not mutate state

Application services live in `internal/application/service/<feature>-service` and implement interfaces from `internal/domain/service`.

## Default Use Case Shape

Model state-changing use cases as commands, even when a worker event rather than a user request triggers them. Model read-only use cases as queries.

Delivery code should only:

1. receive the request, message, poll result, or scheduled trigger
2. validate and map the boundary payload
3. decide which application command or query to call
4. pass one request to that service method
5. acknowledge, delete, or respond after the service returns

The application command owns the business unit of work:

1. open the transaction when state changes must be atomic
2. load the aggregate or aggregate set associated with the incoming event/request, usually with a domain-facing `repository.ForUpdate()` option for conflicting read-modify-write flows
3. call the aggregate method that represents the business transition
4. collect any domain event returned by that aggregate method
5. persist the changed aggregate state
6. when durable event publication is part of the feature, publish collected events through its event/outbox port in the same transaction

Do not split this flow across delivery, repository, and application code. Delivery must not load aggregates and perform transitions. Repositories must not decide whether a transition should happen or synthesize domain events. Application services must not bypass aggregate methods with direct field assignment.

## Main Rule

Application services orchestrate use cases; they do not own low-level details.

For most state-changing use cases, the default shape is:

1. load the aggregate or aggregate set from the database, using `FOR UPDATE` when concurrent updates can conflict
2. call aggregate behavioral methods that validate the transition and return domain events when the domain contract is eventful
3. persist the changed aggregate state
4. publish returned domain events in the same transaction only when the feature has an established durable-event contract

They may decide the broader business sequence:

1. start a trace span
2. check only application-owned preconditions that were not knowable at delivery
3. open a transaction when state must change atomically
4. load aggregates through repositories, often `FOR UPDATE`
5. call aggregate constructors or behavioral methods and collect returned domain events when applicable
6. persist changed aggregate state
7. publish domain events through the established event/outbox port when applicable
8. return a domain service response

They should not implement aggregate invariants, SQL, HTTP DTO mapping, broker envelopes, retry loops, transport parsing, or worker acknowledgement mechanics.

## Commands And Queries

Split application methods mentally into commands and queries.

Commands:

- change object state
- represent the business operation selected by a delivery handler, worker, cron job, or consumer
- usually operate on aggregates or write-side projections
- should use `txManager.Do` when multiple writes or a read-modify-write sequence must be atomic
- should load mutable aggregates with domain-facing repository options such as `repository.ForUpdate()` when concurrent updates can conflict
- should mutate state through domain methods such as `Close`, `Deposit`, `MarkTransferred`, `Confirm`, or `Cancel`, and use any domain events those methods return
- should persist the new state after successful domain mutation
- should publish emitted domain events in the same transaction when outbox consistency matters
- should expose collection-shaped variants when the caller naturally receives a batch of events or requests

Queries:

- do not mutate state
- usually operate on read models, filters, projections, and external read gateways
- should not use `FOR UPDATE`
- usually do not need transactions
- may enrich repository results with gateway data if the method is still read-only
- should avoid calling aggregate mutation methods

Do not hide a state change inside a method that reads like a query.

## Package Shape

A service package usually has:

- `implementation.go` with the `Implementation` struct, interface assertion, constructor, and injected dependencies
- one method-focused file per use case
- private guard helpers only when the service owns a cross-field or state-dependent precondition
- private mapping helpers when they are specific to one use case
- focused tests for exported service behavior when requested or when risk justifies it

Typical full state-changing implementation shape is shown below. Inject only dependencies the use case actually needs; omit the outbox or gateway when the feature does not use one.

```go
var _ service.Payment = &Implementation{}

type Implementation struct {
    balanceRepo repository.Balance
    paymentRepo repository.Payment
    outbox      repository.Outbox
    txManager   trm.Manager
    gateway     somegateway.Gateway
}

func NewImplementation(
    balanceRepo repository.Balance,
    paymentRepo repository.Payment,
    outbox repository.Outbox,
    txManager trm.Manager,
    gateway somegateway.Gateway,
) *Implementation {
    return &Implementation{
        balanceRepo: balanceRepo,
        paymentRepo: paymentRepo,
        outbox:      outbox,
        txManager:   txManager,
        gateway:     gateway,
    }
}
```

Keep constructor parameter order stable and readable. Prefer explicit dependencies over service locators or global state.

## Command Workflow

For a command that changes aggregate state, prefer this shape:

```go
func (i *Implementation) Confirm(ctx context.Context, req service.ConfirmRequest) (*service.ConfirmResponse, error) {
    ctx, span := prospan.Start(ctx)
    defer span.End()

    err := i.txManager.Do(ctx, func(ctx context.Context) error {
        aggregate, err := i.repo.Get(
            ctx,
            repository.GetRequest{ID: req.ID},
            repository.ForUpdate(),
        )
        if err != nil {
            return err
        }

        event, err := aggregate.Confirm(req.Value, time.Now().UTC())
        if err != nil {
            return err
        }

        if err = i.repo.Update(ctx, aggregate); err != nil {
            return err
        }

        return i.outbox.PublishAggregateEvent(ctx, event)
    })
    if err != nil {
        return nil, span.Err(err)
    }

    return &service.ConfirmResponse{}, nil
}
```

Rules:

- rely on delivery validation only when every caller crosses a proven validated boundary; workers and consumers must validate their own decoded payloads
- add service-level guards only for application-owned rules that require loaded state, multiple dependencies, or use-case context
- keep the transaction body small and business ordered
- return raw errors inside `txManager.Do`; wrap with `span.Err` at the service boundary
- use domain-facing repository options such as `repository.ForUpdate()` for read-modify-write aggregate loads
- call domain behavior before persistence; do not mutate exported fields directly for lifecycle state
- delegate domain preparation to aggregate methods. For example, call `eventEntity.PrepareForTranslation(...)` rather than implementing `prepareEventForTranslation` in an application service that assigns state, language, or other domain fields
- when the feature uses durable events, publish them after state persistence inside the same transaction when they describe the committed state

## Batch Commands

When a delivery worker, consumer, cron job, or API handler receives many independent items that all need the same aggregate transition, prefer a batch application command. Do not write a delivery loop that calls the single-item command once per item unless the batch is truly tiny, non-performance-sensitive, and no batch repository method is justified.

Batch commands keep the same aggregate workflow at collection scale:

1. load all affected aggregates with one repository call where practical, using a lock option when needed
2. iterate over aggregates in memory and call the domain transition method on each aggregate
3. collect changed aggregates and returned events
4. persist changes with a batch repository method when the repository supports it
5. when durable events are part of the feature, publish them with the event port's batch method

For database-backed batches, repository implementations should normally use set-based queries such as `unnest`-driven updates/inserts/upserts instead of one query per aggregate. The application service should call CRUD-shaped aggregate repository methods such as `List(..., repository.ForUpdate())` with status/ID filters or `BatchUpdate(...)`, plus the established event port when events are required; it should not hide an N+1 persistence loop behind a business-looking method.

Do not replace aggregate transition methods with application-level status switches just because the use case is batched. If a bulk SQL update is necessary for performance, the application service should still make the intended domain transition explicit and preserve the same event semantics.

## Query Workflow

For read-only methods, prefer this shape:

```go
func (i *Implementation) List(ctx context.Context, req service.ListRequest) (*service.ListResponse, error) {
    ctx, span := prospan.Start(ctx)
    defer span.End()

    resp, err := i.repo.List(ctx, repository.ListRequest{
        Filter:     buildFilter(req),
        Pagination: req.Pagination,
    })
    if err != nil {
        return nil, span.Err(err)
    }

    return &service.ListResponse{
        Items:      resp.Items,
        NextCursor: resp.Pagination.Cursor,
        HasMore:    resp.Pagination.HasMore,
    }, nil
}
```

Rules:

- do not open a transaction unless the read requires a consistent snapshot across multiple operations
- do not pass lock options such as `repository.ForUpdate()`
- do not persist entities or publish outbox events
- keep display/transport mapping out of this layer; delivery owns transport responses
- repository and gateway calls should use domain-facing request/response types

## Layer Boundaries

Application services may import:

- `internal/domain/entity/...`
- `internal/domain/repository`
- `internal/domain/gateway/...`
- `internal/domain/service`
- shared technical abstractions such as `trm.Manager`, pagination, tracing, and typed errors

Application services should not import:

- `internal/infrastructure/...`
- `internal/delivery/...`
- concrete SQL, pgx, xo, Resty, Kafka, or HTTP transport DTOs
- generated protobuf request/response types unless an existing domain service contract already uses a generated enum as a stable domain-facing value

Keep delivery handlers thin: run protovalidate, perform delivery-owned validation and mapping, call application service, map response.
Keep worker handlers thin: poll or decode work, group items into service requests when appropriate, call the batch command/query, then ack/delete/commit transport progress.
Keep infrastructure adapters behind domain interfaces.
Keep domain aggregates free of repository, gateway, transaction, and outbox dependencies.

## Testing

Add focused tests for every changed public command or query.

For commands, cover:

- successful aggregate loading, transition, and persistence order
- transaction callback context reaching every repository call
- lock options on conflicting read-modify-write flows
- rollback and no later writes when a dependency or domain transition fails
- durable event publication order and payload when the feature uses it
- propagation or one-time classification of domain, repository, and gateway errors

For queries, cover filters and request mapping, result mapping, dependency errors, and the absence of writes or lock options. Use generated mocks or small fakes and assert business interactions rather than private helper calls.

## Transactions

Use the existing `trm.Manager` abstraction provided by `cmd/postgres_module.go` for application-owned transaction boundaries. Repository implementations receive the matching pgx context getter so calls made with the callback context join the same transaction.

Use a transaction when:

- a use case performs multiple writes
- a use case performs read-modify-write
- aggregate state and outbox publication must be committed atomically
- multiple aggregates or projections must change together

Avoid transactions when:

- the method is a simple query
- the method only calls an external gateway
- consistency across multiple reads is not required

Inside a transaction, every repository call must receive the transaction-scoped `ctx` passed to the callback.

## Events And Outbox

Apply this section only when the feature has an approved durable-event or outbox contract. Application services express publishing intent, not transport mechanics. An event/outbox port is not an aggregate persistence repository, so it may use `Publish` or `PublishBatch` names instead of aggregate CRUD names.

Good:

- `events.Publish(ctx, event)`
- `events.PublishBatch(ctx, events)`
- an existing typed publish method when different aggregate event types require distinct contracts

Bad:

- choosing broker topics in application code
- building headers, payload JSON, partition keys, or outbox rows in application code
- polling or committing outbox offsets from an application service

If an aggregate method returns an event that must be durable, pass it unchanged to the domain-facing event port. Infrastructure owns mapping it to an outbox envelope. Do not add an outbox solely because this skill contains an outbox example.

## External Gateways

Application services may call domain gateway interfaces to perform use-case steps, but they should keep provider details out of the service method.

Rules:

- depend on `internal/domain/gateway/...` interfaces, not infrastructure clients
- pass domain-facing request types
- treat gateway responses as facts used by the business workflow
- do not leak provider JSON fields, HTTP status handling, Resty request setup, or signing mechanics into application code
- be cautious about gateway calls inside DB transactions; keep transactions short unless the call and persistence sequence truly requires atomic coordination

## Validation And Errors

Field-shape validation belongs at each independent trust boundary. API handlers should validate protobuf requests before calling application services, while workers and consumers validate decoded payloads at their own ingress. If one application request is intentionally callable from multiple boundaries that cannot all guarantee the same validation, centralize the shared shape check once at the application boundary instead of trusting one transport implicitly.

Default validation order:

1. protobuf/protovalidate for field shape, required values, enum constraints, numeric ranges, lengths, and simple cross-field rules expressible in the contract
2. delivery handlers for transport parsing, authentication/authorization context, and validation that belongs to the incoming request boundary
3. application services for shared request-shape checks only when caller contracts cannot guarantee them, and for use-case preconditions that need domain state, repositories, gateways, or business sequencing
4. domain aggregates for invariant and transition guards

Do not duplicate delivery or protovalidate checks inside application services when every caller is proven to enforce them. Do not assume that a worker or cron caller passed through protobuf middleware.

Use private service guard helpers only when the rule belongs to the use case:

```go
func ensureWithdrawalAllowed(balanceEntity *balance.Balance, req service.WithdrawRequest) error {
    if !balanceEntity.CanWithdraw(req.Amount) {
        return errors.Join(&proterror.FailedPrecondition{}, errors.New("withdraw: insufficient balance"))
    }

    return nil
}
```

Rules:

- classify field-shape validation errors at delivery, usually as `proterror.InvalidArgument`
- classify application-owned precondition failures with the most specific project error type, often `proterror.FailedPrecondition`
- use specific lower-level errors from repositories, gateways, and domain methods without reclassifying them at every layer
- wrap returned service errors with `span.Err(...)` at the service boundary
- avoid double-wrapping errors inside transaction callbacks

## Tracing

Public application methods that accept `context.Context` should start a `prospan` span if the package uses tracing or the method is a new service entrypoint.

Typical shape:

```go
ctx, span := prospan.Start(ctx)
defer span.End()
```

Return errors through `span.Err(err)` at the public service boundary. Inside transaction callbacks and private helpers, usually return plain errors so the boundary owns tracing.

When continuing asynchronous aggregate work, restore trace context only if the repository has an established persisted carrier format. Do not invent one inside an application method.

## Smell Check

Pause and inspect the design if application code contains:

- SQL, xo models, pgx transactions, Resty requests, Kafka records, or raw HTTP DTOs
- topic names, headers, payload JSON, partition keys, outbox offsets, ack, retry, or polling loops
- direct lifecycle field assignment instead of aggregate methods
- lock options such as `repository.ForUpdate()` in a query method
- a command that reads and updates an aggregate without a transaction
- manual construction of lifecycle domain events that an aggregate method should emit
- delivery code that loads aggregates, calls aggregate transition methods, persists aggregate state, or publishes lifecycle events
- a batch-capable workflow implemented as a delivery loop over single-item commands
- a repository method that performs one update/insert query per item when an `unnest`-style batch write would be straightforward
- helper functions that prepare aggregates for a business step by assigning domain fields, such as `prepareEventForTranslation`; those belong on the domain entity
- large transport mapping blocks that belong in delivery
- provider-specific response parsing that belongs in infrastructure

## Related Skills

Use this skill together with:

- `domain-entity` when aggregate behavior, state transitions, or domain events are involved
- `repository-layer` when adding repository contracts or persistence implementations
- `project-layout` when outbox, broker, worker, provider, or other technical placement questions appear
- `tracing` for `prospan` ownership and asynchronous trace-carrier propagation
- `error-handling` for project-standard error classification
- `field-validation` for request/response validation ownership
