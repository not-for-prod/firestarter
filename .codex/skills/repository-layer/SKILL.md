---
name: repository-layer
description: Design, review, refactor, or implement this repository's Go repository layer. Use for `implement repo @<repository path>` requests and any work under `internal/domain/repository` or `internal/infrastructure/repository`, including interface placement, PostgreSQL implementation structure, transaction access, squirrel SQL, xo-generated models, repository filters/options, converters, and repository tests.
---

# Repository Layer

## Purpose

Use this skill as the single source of truth for repository contracts and PostgreSQL repository implementations. It covers both design questions and implementation tasks such as `implement repo @internal/infrastructure/repository/...`.

Repositories retrieve and persist data. They do not decide business eligibility, hide use-case policy, or expose persistence mechanics upward.

## Ownership

- `internal/domain/repository` owns interfaces, request/filter types, and domain-facing repository result types.
- `internal/infrastructure/repository/<feature>-repository` owns PostgreSQL queries, row scanning, xo models, transaction access, and persistence-specific helpers.
- `internal/generated/xo` owns generated table names, column names, DAO structs, aliases, select helpers, and reusable SQL clauses.
- `internal/pkg/convert` owns reusable domain-to-xo and xo-to-domain mapping.

Do not put SQL, xo models, pgx types, transport DTOs, or business policy in domain repository contracts.

## Package Shape

Repository implementation packages usually contain:

- `implementation.go` for shared wiring, `sq`, interface assertion, constructor, and `tr(ctx)`
- one public method per file, named after the method in snake_case
- optional `query/` SQL files plus `query.go` for complex embedded SQL
- method-local row DTOs only for custom projections that xo cannot represent

Use feature-local repository packages. Do not create generic persistence packages for unrelated methods.

## Implementation Wiring

Match the package's existing constructor first. For new PostgreSQL repositories, prefer:

```go
var sq = squirrel.StatementBuilder.PlaceholderFormat(squirrel.Dollar)

type Implementation struct {
    db        *pgxpool.Pool
    ctxGetter *txManagerPgxv5.CtxGetter
}

func NewImplementation(db *pgxpool.Pool, ctxGetter *txManagerPgxv5.CtxGetter) *Implementation {
    return &Implementation{
        db:        db,
        ctxGetter: ctxGetter,
    }
}

func (i *Implementation) tr(ctx context.Context) txManagerPgxv5.Tr {
    return i.ctxGetter.DefaultTrOrDB(ctx, i.db)
}
```

Every DB call must go through `i.tr(ctx)`.

## Select Options

Every repository method that executes a caller-controlled `SELECT` should accept trailing `opts ...xo.SelectOption` and apply them before `ToSql()`:

```go
func (i *Implementation) List(ctx context.Context, req repository.ListRequest, opts ...xo.SelectOption) (*repository.ListResponse, error) {
    builder := sq.Select(...).From(...)
    builder = applyFilter(builder, req.Filter)
    builder = req.Pagination.Apply(builder)
    builder = xo.ApplySelectOptions(builder, opts...)
}
```

Use `xo.ForUpdate()` and `xo.SkipLocked()` at call sites instead of request booleans such as `ForUpdate`. This keeps lock behavior near transaction boundaries without creating one-off request flags.

## xo Rules

Use xo-generated artifacts for table-shaped queries:

- `xo.Table_<Entity>` for insert, update, delete, and unaliased table references
- `xo.Table_<Entity>_With_Alias` when selected, filtered, joined, grouped, or ordered columns are qualified
- generated field constants for select, update, filter, and ordering columns
- generated model helpers such as `Columns()`, `Values()`, `ToMap()`, and `SelectColumns()`

Do not invent table names, column strings, parallel DAO structs, or table-shaped row DTOs when xo should provide them. If xo output is missing, inspect migrations/schema and run the project generation path instead of hand-writing generated equivalents.

Use private row DTOs only for genuine custom projections: joins, aggregates, computed columns, CTE outputs, or query-specific shapes.

## Query Construction

Use `github.com/Masterminds/squirrel` for ordinary CRUD, readable selects, joins, filters, ordering, pagination, and simple updates.

Use embedded raw SQL under `query/` when the query is clearer as SQL, especially for:

- large batch writes
- `unnest`-driven inserts, updates, or upserts
- CTE-heavy queries
- PostgreSQL-specific statements that squirrel makes harder to read

Avoid one-query-per-row loops for complex batch writes.

## Converters

Put full entity persistence mapping in `internal/pkg/convert`:

- `convert.<Entity>ToXO(...)`
- `convert.<Entity>FromXO(...)`

Keep package-local conversion only for method-owned custom row DTOs or projections, using small helpers such as `(r listRow) toDomain()`.

Do not place domain-to-xo or xo-to-domain entity converters inside repository packages.

## Method Workflow

When implementing or refactoring a repository method:

1. Inspect the domain repository interface.
2. Inspect the target implementation package.
3. Inspect adjacent repositories for local style.
4. Inspect xo models, aliases, helper clauses, and converters.
5. Decide whether squirrel or embedded SQL is clearer.
6. Apply `opts ...xo.SelectOption` for caller-controlled `SELECT` methods.
7. Execute through `i.tr(ctx)`.
8. Convert persistence shapes to domain shapes before returning.
9. Preserve tracing and error conventions already used by the package.
10. Run focused formatting, tests, and lint for the touched package when feasible.

## Method Shape

Typical traced method:

```go
func (i *Implementation) Get(ctx context.Context, id entity.ID, opts ...xo.SelectOption) (*entity.Entity, error) {
    ctx, span := prospan.Start(ctx)
    defer span.End()

    builder := sq.Select(xo.Entity{}.SelectColumns()...).
        From(xo.Table_Entity_With_Alias).
        Where(squirrel.Eq{xo.Field_Entity_ID_With_Alias: id})
    builder = xo.ApplySelectOptions(builder, opts...)

    query, args, err := builder.ToSql()
    if err != nil {
        return nil, span.Err(errors.Join(&proterror.Internal{}, err))
    }

    var row xo.Entity
    if err = i.tr(ctx).Get(ctx, &row, query, args...); err != nil {
        return nil, span.Err(proterrors.FromPG(err))
    }

    return convert.EntityFromXO(&row), nil
}
```

Match local package style over forcing this exact shape.

## Boundary Smells

Pause and re-check the design if repository code:

- returns `bool` decisions such as `HasCompleted...` that hide use-case policy
- hardcodes table or column names that xo provides
- bypasses `i.tr(ctx)`
- adds `ForUpdate` request booleans instead of select options
- exposes xo, pgx, SQL fragments, or row DTOs through domain interfaces
- implements business eligibility instead of returning data for application/domain code to evaluate
