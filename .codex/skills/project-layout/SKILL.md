---
name: project-layout
description: Describe or apply this repository's Go project layout when the user asks where code should live, how layers depend on each other, how to add a new feature without breaking boundaries, or how to navigate the Firestarter codebase. Use when placing files under `cmd`, `config`, `api`, `internal/application`, `internal/delivery`, `internal/domain`, `internal/infrastructure`, `internal/generated`, `internal/pkg`, `docs`, or `tools`.
---

# Project Layout

## Overview

Use this skill to explain or enforce the layout of this repository. Prefer matching the existing structure over introducing a new architectural pattern.

When the question narrows to one layer, prefer the dedicated layer skill:

- use `repository-layer` for repository contracts and PostgreSQL implementations
- use `gateway-layer` for gateway contracts and external API clients

This codebase is organized as a layered Go service:

- `cmd` contains entrypoints and dependency wiring when services are added
- `config` contains runtime configuration when the service has runtime config
- `api` contains protobuf contracts and API schemas, currently under `api/firestarter`
- `internal/domain` contains entities and layer interfaces
- `internal/application/service` contains use-case orchestration when application services are introduced
- `internal/delivery/api` contains transport handlers and request/response mapping when delivery handlers are introduced
- `internal/infrastructure` contains concrete gateways and repositories when adapters are introduced
- `internal/generated` contains generated code when generation output exists
- `internal/pkg` contains shared technical helpers such as connectors, middleware, code-generation support, optimizers, worker utilities, and provider-neutral helpers
- `docs` contains domain and flow notes when project documentation is added
- `tools` contains migrations and codegen support files

## Main Rule

Place code by responsibility, not by convenience.

Ask in this order:

1. Is this an entrypoint or DI wiring concern?
2. Is this a domain contract or entity?
3. Is this a use-case orchestration concern?
4. Is this delivery/transport-specific?
5. Is this an external-system or persistence adapter?
6. Is this generated code or a reusable technical helper?

Put the code in the first layer that truly owns that responsibility.

## Dependency Direction

Keep dependencies moving inward:

- `cmd` may depend on every internal layer needed for wiring
- `delivery` depends on `domain` contracts and `application/service`
- `application/service` depends on `domain` entities, repositories, gateways, and service contracts
- `infrastructure` depends on `domain` contracts and shared technical helpers
- `domain` should not depend on `delivery`, `application`, or `infrastructure`

Do not make `domain` import concrete adapters.
Do not put transport DTOs into `domain`.
Do not put business orchestration into `cmd` or `delivery`.

## Business vs Technical Code

Business code defines business meaning, business state, business rules, business transitions, and business events.

Technical code makes the system run, integrate, persist, deliver, observe, or coordinate work. Technical code includes:

- connectors and adapters such as PostgreSQL, Redis, Kafka, HTTP/gRPC clients, object storage, and third-party API gateways
- transport and persistence details such as topics, headers, payload envelopes, partition keys, offsets, trace carriers, database rows, SQL, transactions, and serialization formats
- operational concerns such as logging, tracing, metrics, rate limits, timeouts, circuit breakers, config wiring, code generators, and optimizers
- system design patterns such as outbox, inbox, retries, deduplication, idempotency keys, polling, locking, and acknowledgements

Technical does not automatically mean `internal/pkg`. Place technical code by ownership:

- repository interfaces: `internal/domain/repository`
- repository implementations: `internal/infrastructure/repository/...`
- gateways and provider adapters: `internal/infrastructure/gateway/...`
- workers, consumers, polling loops, acknowledgements: `internal/delivery/worker/...`
- reusable provider-neutral helpers, connectors, middleware, codegen helpers, optimizers, and worker utilities: `internal/pkg/...`

Do not move repositories, gateways, workers, provider-specific adapters, outbox rows, broker envelopes, or payload DTOs into `internal/pkg` just because they are technical. `internal/pkg` is for reusable technical support, not feature ownership.

If a type would disappear or substantially change when replacing PostgreSQL with another database, Kafka with another broker, polling with streaming, or outbox with direct publishing, treat it as technical code. If a type describes what happened in the business, why it is valid, which aggregate changed, or which state transition occurred, treat it as business/domain code even if infrastructure later stores or publishes it.

## Directory Map

### `cmd`

Use `cmd/<service>` for executable entrypoints such as `cmd/firestarter` when a service entrypoint is added.

Typical contents:

- `main.go`
- `fx` wiring
- server startup
- worker startup

Do not put business logic here beyond bootstrapping and composition.

### `config`

Use `config` for application configuration models and loading.

Put here:

- env-backed config structs
- config singleton/bootstrap code
- config defaults only when already consistent with local style

Do not put operational business rules here.

### `api`

Use `api/firestarter/...` for protobuf and public contract files.

Put here:

- `.proto` files
- shared API message definitions
- contract-level validation annotations

Generated Go and gateway files belong in `internal/generated` when generation output is present, not here.

### `internal/domain`

`internal/domain` is the core contract layer.

Use subfolders by responsibility:

- `entity` for domain models and value objects
- `repository` for persistence interfaces
- `gateway` for external integration interfaces
- `service` for application-facing service interfaces
- `query` or `cache` for domain-level abstractions when already established

See `repository-layer` for the repository split and `gateway-layer` for gateway boundaries and package shape.

Put here:

- business-facing types
- interfaces consumed by upper layers
- domain invariants that are not transport-specific

Do not put SQL, HTTP clients, protobuf DTOs, or framework wiring here.

### `internal/application/service`

Use `internal/application/service/<feature>-service` for use-case orchestration.

Put here:

- methods that coordinate repositories and gateways
- transaction boundaries through domain repository abstractions
- business workflows such as user commands, scheduled use cases, and domain state changes

This layer should express the use case, not transport concerns or low-level client details.

### `internal/delivery/api`

Use `internal/delivery/api/<service>-server` for delivery handlers.

Put here:

- gRPC/HTTP handler implementations
- request parsing and DTO-to-domain mapping
- response mapping
- delivery-owned validation

Keep handlers thin. They should validate, map, call a service, and map the result back.

### `internal/delivery/worker`

Use `internal/delivery/worker/<feature>-worker` for scheduled jobs, outbox consumers, queue polling, and similar delivery-owned worker orchestration.

Put here:

- polling or listing work items
- decoding worker payloads
- calling application services
- deleting or acknowledging processed items

Do not put business state transitions here when they belong in aggregates or application services.

### `internal/infrastructure`

Use this for concrete adapters.

Subfolders:

- `gateway` for third-party or blockchain clients
- `repository` for PostgreSQL or other persistence implementations

See `gateway-layer` for gateway client structure and `repository-layer` for repository implementation structure.

Put here:

- Resty/HTTP clients
- blockchain RPC integrations
- SQL queries
- xo-backed repository implementations
- adapter-specific request/response DTOs

Keep adapter details here and expose them upward only through `domain` interfaces.

### `internal/generated`

Use this only for generated artifacts.

Generated areas commonly include:

- `internal/generated/pb` for protobuf-generated code
- `internal/generated/xo` for xo-generated database models

Do not hand-edit generated files unless the task explicitly requires it and regeneration is not available.

### `internal/pkg`

Use `internal/pkg` for shared technical utilities that are not domain-owned and are not owned by one adapter or feature package.

Current examples include:

- `connector` for postgres and redis setup
- `mw` for grpc/http middleware
- `worker` for scheduled worker support
- code-generation helpers, code optimizers, and reusable helper packages when they are provider-neutral and used across features

Do not dump feature logic here. If the code belongs to one bounded feature, keep it near that feature instead.
Do not put repositories, gateways, workers, provider-specific clients, outbox/inbox rows, broker envelopes, or request/response payload DTOs here only because they are technical.

### `docs`

Use `docs` for reference material, flow notes, and integration sequences.

### `tools`

Use `tools` for migrations, templates, and codegen-related helpers.

## Placement Workflow

When adding or moving code:

1. Identify whether the code is a contract, workflow, adapter, or helper.
2. Find the existing feature area that already owns similar code.
3. Reuse the established package naming pattern such as `<feature>-service`, `<entity>-repository`, or `<provider>-gateway`.
4. Keep interfaces in `internal/domain` and implementations in `internal/infrastructure` or `internal/application/service`.
5. Keep delivery-specific request validation and mapping in `internal/delivery/api`.
6. Keep shared converter logic in `internal/pkg/convert` if it is reused across layers.

If two locations seem plausible, prefer the narrower scope:

- feature-local package over global helper package
- concrete adapter package over generic shared package
- delivery/application/infrastructure package over `internal/pkg`

## Naming Patterns

Match the repository’s existing naming:

- service packages: `<feature>-service`
- repository packages: `<feature>-repository`
- gateway packages: `<provider>-gateway` or nested provider packages when a provider needs subpackages
- delivery packages: `<service>-server`
- implementation entry file: `implementation.go`

Preserve existing naming even if it is not your preferred convention.

## Common Decisions

Use `internal/domain/entity` when introducing a business model used across layers.

Use `internal/domain/gateway` or `internal/domain/repository` when introducing a new dependency boundary.

Use `internal/application/service/<feature>-service` when adding a new business workflow that coordinates existing dependencies.

Use `internal/delivery/api/...` when the change is about transport shape, handler behavior, or request/response mapping.

Use `internal/delivery/worker/...` when the change is about worker orchestration, polling, dispatch, ack/delete, or queue/outbox consumption.

Use `internal/infrastructure/gateway/...` when calling an external API, blockchain, or provider SDK.

Use `internal/infrastructure/repository/...` when persisting or querying storage.

Use `internal/pkg/convert` when conversion logic is reused and does not belong to a single adapter file.

## Avoid

- creating new top-level architecture folders without a strong reason
- putting business logic into `cmd`
- putting HTTP/SQL/client code into `internal/domain`
- putting request field validation into repositories or gateways when it belongs at an earlier boundary
- placing one-off feature code into `internal/pkg`
- giving technical delivery patterns domain status, such as `internal/domain/entity/outbox`
- editing generated code instead of changing its source or generator path
