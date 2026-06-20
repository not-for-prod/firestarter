---
name: domain-entity
description: Design, review, or refactor Go domain entities under `internal/domain/entity`. Use for aggregate roots, value objects, typed IDs/states, public entity/event fields, constructor-owned initialization, guarded state transitions, domain methods as mutation boundaries, and Debezium-like domain events carrying before/after snapshots.
---

# Domain Entity

## Overview

Use this skill when a domain model should behave like an aggregate root rather than a passive DTO.

The target shape is:

- explicit microtypes for aggregate IDs and relation IDs
- typed state enums instead of raw strings
- constructor-owned initialization
- constructor-created aggregates may emit a `created` domain event when creation itself is a meaningful lifecycle transition
- no public setters for business state
- aggregate methods as the only mutation path
- each successful mutation returns a Debezium-like domain event with `before`, `after`, event type, aggregate ID, and timestamp

## Main Rules

Model aggregate data and behavior together.

- Put invariants and transition rules on the aggregate root.
- Treat aggregate creation as part of the lifecycle, not as a raw struct literal in services.
- Represent relations with typed IDs such as `DepositID`, `PaymentID`, and `RequisiteID`.
- Keep mutation methods intention-revealing: `Confirm`, `Cancel`, `Fail`, not `SetState`.
- Put domain preparation methods on the aggregate when they assign business state, default language, lifecycle flags, or other domain-owned fields. For example, an event entering translation should expose an `Event.PrepareForTranslation(...)` method instead of an application helper such as `prepareEventForTranslation`.
- Prefer constructors such as `NewX(...)` or `NewY(...)` over exported struct literals for domain-owned aggregates.
- Copy the aggregate before mutation and use snapshots in emitted events.
- Use exported fields for domain entities and domain events. Do not add trivial getters for domain data.

## Public Fields

Domain entities and domain events expose data as exported fields:

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

Public fields are for reading, persistence mapping, serialization mapping, and explicit rehydration. They do not make lifecycle state assignment acceptable in application services; business state changes still go through intention-revealing domain methods.

When creating domain events, assign copied snapshots:

```go
return &OrderEvent{
    Before: before.Copy(),
    After:  after.Copy(),
}
```

Do not force domain events to implement getter-heavy interfaces for repositories, outbox consumers, or workers. Prefer concrete event types or minimal marker interfaces where polymorphism is only used for type switching.

## Event Shape

If a generic event type is needed, keep the interface minimal and avoid getter contracts:

```go
type Event interface{}
```

Use:

- a generic `EventType` string type for cross-aggregate handling
- an aggregate-specific event type enum such as `DepositEventType`
- one aggregate event struct with exported fields carrying:
  - event ID
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

Each domain method should follow this order:

1. validate the transition and inputs
2. copy the previous aggregate state
3. mutate the aggregate
4. copy the new aggregate state
5. create and return the domain event

If validation fails, return a typed domain error and do not mutate the aggregate.

Constructors may follow the same shape when creation is eventful:

1. validate inputs
2. initialize aggregate in its starting state
3. copy the new aggregate state
4. create and return the `created` event

## Design Constraints

- Do not expose public setters for state, timestamps, or failure reasons.
- Do not instantiate eventful aggregates with exported struct literals in application services.
- Do not let callers build events manually for aggregate state changes.
- Do not move core business preparation logic into application services just because the entity fields are exported. Application code may gather technical inputs such as a trace carrier, but the aggregate method must own the domain field changes.
- Do not return raw strings for event types or states.
- Do not mix repository, database, broker, or transport concerns into the aggregate.
- Do not expand a domain entity to match an external provider response. Add only fields that represent business state the project actually needs.
- When a new domain-specific field supersedes an older generic field, replace the generic field rather than keeping both in parallel.
- Prefer value copying for snapshots. If nested reference fields exist, deep-copy them.

## Practical Check

Before calling this entity an aggregate, check:

- creation goes through a constructor, not a struct literal
- lifecycle changes happen through methods, not field assignment
- constructor and transition methods return domain events
- services persist the aggregate and map the emitted event, rather than inventing aggregate lifecycle events themselves
- event fields are read directly instead of through trivial getters

## Reference

For a complete example, read:

- `references/deposit_aggregate.go`

That file shows:

- `Deposit` aggregate root
- `DepositID`, `PaymentID`, `RequisiteID`
- `DepositState`, `DepositEventType`, and `EventType`
- constructor and `Copy`
- guarded `Confirm`, `Cancel`, and `Fail`
- immutable Debezium-like `DepositEvent`
- typed validation errors
