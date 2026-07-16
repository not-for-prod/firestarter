---
name: domain-entity
description: Design, implement, review, or refactor Firestarter domain models under `internal/domain/entity`. Use when creating aggregate roots, value objects, typed IDs or states, constructors, invariants, guarded transitions, rehydration paths, or domain events; add before/after event snapshots only when the feature's event contract requires them.
---

# Domain Entity

## Overview

Use this skill when a domain model should behave like an aggregate root rather than a passive DTO.

The target shape is:

- explicit microtypes for aggregate IDs and relation IDs
- typed state enums instead of raw strings
- constructor-owned initialization
- constructor-created aggregates may emit a `created` domain event only when creation is part of the feature's event contract
- no public setters for business state
- aggregate methods as the only mutation path
- successful mutations return domain events only when downstream behavior or an approved event contract requires them
- event snapshots are deep copies when the event contract uses `before` and `after`

## Main Rules

Model aggregate data and behavior together.

- Put invariants and transition rules on the aggregate root.
- Treat aggregate creation as part of the lifecycle, not as a raw struct literal in services.
- Represent relations with typed IDs such as `DepositID`, `PaymentID`, and `RequisiteID`.
- Keep mutation methods intention-revealing: `Confirm`, `Cancel`, `Fail`, not `SetState`.
- Put domain preparation methods on the aggregate when they assign business state, default language, lifecycle flags, or other domain-owned fields. For example, an event entering translation should expose an `Event.PrepareForTranslation(...)` method instead of an application helper such as `prepareEventForTranslation`.
- Prefer constructors such as `NewX(...)` or `NewY(...)` over exported struct literals for domain-owned aggregates.
- Copy the aggregate before mutation when emitted events require snapshots.
- Use exported fields for domain entities and domain events. Do not add trivial getters for domain data.

## Public Fields And Rehydration

Domain entities and domain events may expose data as exported fields when that matches local persistence and mapping conventions:

```go
type OrderEvent struct {
    ID          uuid.UUID
    Type        OrderEventType
    AggregateID OrderID
    Before      *Order
    After       *Order
    OccurredAt  time.Time
}
```

Avoid trivial getters such as:

```go
func (e *OrderEvent) ID() uuid.UUID
func (e *OrderEvent) After() *Order
func (e *OrderEvent) OccurredAt() time.Time
```

Public fields are for reading and mapping. They do not make lifecycle state assignment acceptable in application services; business state changes still go through intention-revealing domain methods.

Provide an explicit rehydration path when repositories need to restore persisted state. Rehydration validates persisted shape but must not emit a creation event or replay transitions. Keep it distinct from the constructor used for new aggregates.

When an event contract carries snapshots, assign copied snapshots:

```go
return &OrderEvent{
    Before: before.Copy(),
    After:  after.Copy(),
}
```

Do not force domain events to implement getter-heavy interfaces for repositories, outbox consumers, or workers. Prefer concrete event types or minimal marker interfaces where polymorphism is only used for type switching.

## Event Shape

Do not add events to every aggregate by default. Add them when another use case, outbox, audit contract, or integration consumes the business occurrence.

If polymorphism is needed, keep the interface minimal and avoid getter-heavy contracts. Prefer a concrete event type or a small marker interface over `interface{}` that adds no value.

```go
type Event interface {
    isDomainEvent()
}
```

Use:

- a generic `EventType` string type for cross-aggregate handling
- an aggregate-specific event type enum such as `DepositEventType`
- one aggregate event struct with exported fields carrying only what the approved contract needs, commonly:
  - event ID when durable publication requires one
  - event type
  - aggregate ID
  - before snapshot
  - after snapshot
  - occurred-at timestamp

The event type should describe the business action, not a persistence operation:

- `created`
- `confirmed`
- `cancelled`
- `failed`

## Mutation Workflow

For a mutation that emits a snapshot event, follow this order:

1. validate the transition and inputs
2. copy the previous aggregate state
3. mutate the aggregate
4. copy the new aggregate state
5. create and return the domain event

If validation fails, return a domain-specific sentinel or typed error and do not mutate the aggregate.

For a mutation without an event contract, validate, mutate, and return an error only. Do not manufacture unused event types merely to match this skill.

Constructors may follow the same shape when creation is explicitly eventful:

1. validate inputs
2. initialize aggregate in its starting state
3. copy the new aggregate state
4. create and return the `created` event

## Design Constraints

- Do not expose public setters for state, timestamps, or failure reasons.
- Do not instantiate aggregates with exported struct literals in application services when constructors or rehydration functions own their valid shape.
- Do not let callers build events manually for aggregate state changes when the aggregate owns that event contract.
- Do not move core business preparation logic into application services just because the entity fields are exported. Application code may gather technical inputs such as a trace carrier, but the aggregate method must own the domain field changes.
- Do not return raw strings for event types or states.
- Do not mix repository, database, broker, or transport concerns into the aggregate.
- Do not expand a domain entity to match an external provider response. Add only fields that represent business state the project actually needs.
- When a new domain-specific field supersedes an older generic field, replace the generic field rather than keeping both in parallel.
- Prefer value copying for snapshots. If nested reference fields exist, deep-copy them.

## Practical Check

Before calling this entity an aggregate, check:

- new creation goes through a constructor, while persistence restoration uses a distinct rehydration path
- lifecycle changes happen through methods, not field assignment
- constructor and transition methods return domain events only where an approved event contract requires them
- services persist the aggregate and map the emitted event, rather than inventing aggregate lifecycle events themselves
- event fields are read directly instead of through trivial getters

## Testing

For every changed constructor or transition, test:

- the valid path and resulting state
- every rejected state or invariant boundary
- no mutation when validation fails
- UTC or clock behavior when timestamps are part of the contract
- rehydration without creation side effects
- deep-copy isolation for nested reference fields
- before/after snapshot aliasing when events carry snapshots

When event snapshots may contain credentials, personal data, or large nested objects, review the event contract for data minimization before adding serialization or outbox tests.

## Reference

For a complete example, read:

- `references/deposit_aggregate.go`

That file shows:

- `Deposit` aggregate root
- `DepositID`, `PaymentID`, `RequisiteID`
- `DepositState`, `DepositEventType`, and `EventType`
- creation constructor, `RehydrateDeposit`, and `Copy`
- guarded `Confirm`, `Cancel`, and `Fail`
- copied before/after snapshots in `DepositEvent`
- domain-specific validation errors
