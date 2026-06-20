---
name: application-layer
description: Design, review, or implement Go application services in this repository under `internal/application/service`. Use when coordinating business use cases from delivery handlers, workers, cron jobs, or consumers; splitting commands from queries; managing transaction boundaries; calling repositories, gateways, aggregate behavior, and outbox publishing without leaking delivery or infrastructure mechanics.
---

# Application Layer

## Overview

Use this skill when adding, refactoring, or reviewing application services.

The application layer is the business use-case coordinator. It is called by delivery code and coordinates:

- domain aggregates and domain behavior
- domain repository interfaces
- domain gateway interfaces
- transaction boundaries
- outbox publishing by business intent
- query/read workflows that do not mutate state

Application services live in `internal/application/service/<feature>-service` and implement interfaces from `internal/domain/service`.

## Main Rule

Application services orchestrate use cases; they do not own low-level details.

They may decide the business sequence:

1. start a trace span
2. check only application-owned preconditions that were not knowable at delivery
3. open a transaction when state must change atomically
4. load aggregates through repositories, often `FOR UPDATE`
5. call aggregate constructors or behavioral methods
6. persist changed aggregate state
7. publish domain events through typed outbox repository methods
8. return a domain service response

They should not implement aggregate invariants, SQL, HTTP DTO mapping, broker envelopes, retry loops, or transport parsing.

## Commands And Queries

Split application methods mentally into commands and queries.

Commands:

- change object state
- usually operate on aggregates or write-side projections
- should use `txManager.Do` when multiple writes or a read-modify-write sequence must be atomic
- should load mutable aggregates with repository select options such as `xo.ForUpdate()` when concurrent updates can conflict
- should mutate state through domain methods such as `Close`, `Deposit`, `MarkTransferred`, `Confirm`, or `Cancel`
- should persist the new state after successful domain mutation
- should publish emitted domain events in the same transaction when outbox consistency matters

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

Typical implementation shape:

```go
var _ service.Payment = &Implementation{}

type Implementation struct {
    balanceRepo repository.Balance
    paymentRepo repository.Payment
    outbox      repository.Outbox
    txManager   repository.TxManager
    gateway     somegateway.Gateway
}

func NewImplementation(
    balanceRepo repository.Balance,
    paymentRepo repository.Payment,
    outbox repository.Outbox,
    txManager repository.TxManager,
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
            xo.ForUpdate(),
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

- assume transport-shaped field validation has already happened in delivery, preferably through protovalidate
- add service-level guards only for application-owned rules that require loaded state, multiple dependencies, or use-case context
- keep the transaction body small and business ordered
- return raw errors inside `txManager.Do`; wrap with `span.Err` at the service boundary
- use repository select options such as `xo.ForUpdate()` for read-modify-write aggregate loads
- call domain behavior before persistence; do not mutate exported fields directly for lifecycle state
- delegate domain preparation to aggregate methods. For example, call `eventEntity.PrepareForTranslation(...)` rather than implementing `prepareEventForTranslation` in an application service that assigns state, language, or other domain fields
- publish outbox events after state persistence inside the same transaction when the event describes the committed state

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
- do not pass lock options such as `xo.ForUpdate()`
- do not persist entities or publish outbox events
- keep display/transport mapping out of this layer; delivery owns transport responses
- repository and gateway calls should use domain-facing request/response types

## Layer Boundaries

Application services may import:

- `internal/domain/entity/...`
- `internal/domain/repository`
- `internal/domain/gateway/...`
- `internal/domain/service`
- shared technical packages such as pagination, tracing, and typed errors

Application services should not import:

- `internal/infrastructure/...`
- `internal/delivery/...`
- concrete SQL, pgx, xo, Resty, Kafka, or HTTP transport DTOs
- generated protobuf request/response types unless an existing domain service contract already uses a generated enum as a stable domain-facing value

Keep delivery handlers thin: run protovalidate, perform delivery-owned validation and mapping, call application service, map response.
Keep infrastructure adapters behind domain interfaces.
Keep domain aggregates free of repository, gateway, transaction, and outbox dependencies.

## Transactions

Use `repository.TxManager` for application-owned transaction boundaries.

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

## Outbox And Events

Application services express publishing intent, not transport mechanics.

Good:

- `outbox.PublishOrderEvent(ctx, event)`
- `outbox.PublishPaymentEvent(ctx, event)`
- `outbox.PublishAggregateEvents(ctx, events)`

Bad:

- choosing broker topics in application code
- building headers, payload JSON, partition keys, or outbox rows in application code
- polling or committing outbox offsets from an application service

If an aggregate method returns a domain event, pass that event to a typed outbox repository method. Infrastructure owns mapping the event to an outbox envelope.

## External Gateways

Application services may call domain gateway interfaces to perform use-case steps, but they should keep provider details out of the service method.

Rules:

- depend on `internal/domain/gateway/...` interfaces, not infrastructure clients
- pass domain-facing request types
- treat gateway responses as facts used by the business workflow
- do not leak provider JSON fields, HTTP status handling, Resty request setup, or signing mechanics into application code
- be cautious about gateway calls inside DB transactions; keep transactions short unless the call and persistence sequence truly requires atomic coordination

## Validation And Errors

Primary request field validation belongs before application services.

Default validation order:

1. protobuf/protovalidate for field shape, required values, enum constraints, numeric ranges, lengths, and simple cross-field rules expressible in the contract
2. delivery handlers for transport parsing, authentication/authorization context, and validation that belongs to the incoming request boundary
3. application services only for use-case preconditions that need domain state, repositories, gateways, or business sequencing
4. domain aggregates for invariant and transition guards

Do not duplicate delivery or protovalidate checks inside application services just because a service request has fields.

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

When continuing asynchronous aggregate work from a persisted trace carrier, restore or extend the context before the application method publishes or persists follow-up events.

## Smell Check

Pause and inspect the design if application code contains:

- SQL, xo models, pgx transactions, Resty requests, Kafka records, or raw HTTP DTOs
- topic names, headers, payload JSON, partition keys, outbox offsets, ack, retry, or polling loops
- direct lifecycle field assignment instead of aggregate methods
- lock options such as `xo.ForUpdate()` in a query method
- a command that reads and updates an aggregate without a transaction
- manual construction of lifecycle domain events that an aggregate method should emit
- helper functions that prepare aggregates for a business step by assigning domain fields, such as `prepareEventForTranslation`; those belong on the domain entity
- large transport mapping blocks that belong in delivery
- provider-specific response parsing that belongs in infrastructure

## Related Skills

Use this skill together with:

- `domain-entity` when aggregate behavior, state transitions, or domain events are involved
- `repository-layer` when adding repository contracts or persistence implementations
- `project-layout` when outbox, broker, worker, provider, or other technical placement questions appear
- `tracing` for asynchronous trace-carrier propagation
- `error-handling` for project-standard error classification
- `field-validation` for request/response validation ownership
