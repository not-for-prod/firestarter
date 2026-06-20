---
name: method-per-file
description: Apply this repository's method-per-file notation in Go adapters. Use when adding or refactoring repository or gateway methods so request/response DTOs, constructors, domain conversion helpers, xo/domain converters, and the method implementation are ordered consistently inside one method-focused file.
---

# Method Per File

## Overview

Use one file per public adapter method. Keep method-local DTOs and mapping helpers in the same file as the method that owns them.

The file name must match the public method name in snake_case:

- `ListPositions(...)` belongs in `list_positions.go`
- `GetBalanceAllowance(...)` belongs in `get_balance_allowance.go`
- `RedeemPositions(...)` belongs in `redeem_positions.go`

Do not create broad noun files such as `positions.go` when the public method is `ListPositions(...)`.

This skill applies mainly to:

- `internal/infrastructure/repository/...`
- `internal/infrastructure/gateway/...`
- other adapter packages with boundary DTOs and domain conversion

Prefer existing package conventions when they are already clear, but use this notation for new files and refactors.

## File Order

Order method files from local models to behavior:

1. request DTOs used at the adapter boundary
2. request DTO constructors, such as `newXRequest(...)`
3. response DTOs or row DTOs
4. response/row conversion methods, such as `(r xResponse) toDomain()`
5. xo/domain converters for repository files
6. the public repository/gateway method itself

The method should usually be last, so readers see the local data shapes and conversions before the orchestration.

## Gateway DTOs

For gateway methods:

- use private request/response DTOs with `json` tags for external API payloads
- keep DTOs method-local unless they are truly shared by multiple methods
- add `newXRequest(...)` when mapping from domain request to gateway DTO is non-trivial or consistency is valuable
- use `(r xResponse) toDomain()` when converting external responses into domain responses/entities
- do not leak gateway DTOs into domain, application, or service packages
- do not mirror a provider response into a domain-facing contract just because the provider returns many fields; map only the fields the project currently needs

## Repository DTOs

For repository methods:

- use xo models directly when the query shape matches a generated xo model
- use private row DTOs only for custom query shapes, joins, aggregates, computed columns, or projections that cannot be represented by one xo table model
- treat missing xo models or helpers as a schema/generation problem, not as a reason to create duplicate table-shaped DTOs
- add `db` tags only when the scanner uses tags, such as struct-by-name scanning
- do not add `db` tags for plain `rows.Scan(...)`; they do nothing there
- keep SQL, xo types, row DTOs, and persistence conversion in infrastructure

## Converter Naming

For repository files using xo models, entity conversion belongs in `internal/pkg/convert`.

Use free functions there:

- `convert.<EntityName>FromXO(...)`
- `convert.<EntityName>ToXO(...)`

Use this naming when converting between a domain entity and an xo-generated persistence model. Do not keep entity-to-xo or xo-to-entity converters package-local in repository packages.

For custom response or row DTOs, prefer methods:

- `(r xResponse) toDomain()`
- `(r xRow) toDomain()`

Use package-local helpers only for DTOs, custom response shapes, custom row projections, or gateway payload mapping.

## Boundary Rules

- DTOs belong to the adapter that owns the transport or persistence shape.
- Domain entities and domain events should not gain JSON, DB, topic, header, or provider-specific fields only to satisfy an adapter.
- Infrastructure may convert technical DTOs into real domain models.
- Do not invent adapter-local pseudo-domain types that escape through domain-facing interfaces.
