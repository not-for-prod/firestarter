---
name: tracing
description: Apply Firestarter's `prospan` tracing conventions to context-aware delivery, application, repository, gateway, worker, and adapter methods. Use for span lifecycle, safe request attributes, `span.Err(...)` recording without reclassification, or asynchronous propagation when the repository has an established trace-carrier implementation.
---

# Tracing

## Scope

Use this skill for span lifecycle and context propagation. Use `error-handling` as the sole authority for constructing, wrapping, and classifying errors. `span.Err(...)` records an error on a span; it does not replace classification.

Use:

```go
import "github.com/not-for-prod/observer/tracer/prospan"
```

## Workflow

1. Inspect the target method and adjacent package conventions.
2. Decide whether the method is a meaningful traced operation or only a small private helper.
3. Start the span from the incoming context and pass the returned context downstream.
4. Attach only reviewed, non-sensitive request information.
5. Record returned errors with `span.Err(...)` without reclassifying lower-layer errors.
6. Treat asynchronous propagation as a separate boundary and use an established carrier format only.
7. Preserve behavior and keep tracing changes focused.

## Span Start

Trace public or boundary operations that accept `context.Context`, including:

- generated delivery handler methods
- application commands and queries
- repository methods that perform I/O
- gateway methods that call providers
- worker jobs and message consumers

Typical shape:

```go
ctx, span := prospan.Start(ctx)
defer span.End()
```

Pass the returned `ctx` to every downstream call. Do not start a new span in tiny private helpers solely because they accept a context; prefer the owning public operation unless the helper performs a distinct I/O or business step worth observing.

Do not add tracing to methods that have no context. Do not replace an incoming context with `context.Background()`.

## Delivery Request Attributes

Delivery methods may use:

```go
ctx, span := prospan.WithRequest(req).Start(ctx)
defer span.End()
```

Use `WithRequest(req)` only after reviewing what it records. Do not attach credentials, authorization headers, tokens, private keys, signed payloads, raw message bodies, or unreviewed personal data. If the request contains sensitive fields and the helper cannot redact them, use `prospan.Start(ctx)` and add only explicitly safe attributes through the established observer API.

Do not use `WithRequest(req)` in application, repository, gateway, or generic helper methods.

## Error Recording

If a deeper method already owns classification, record and propagate the same error:

```go
if err != nil {
    return span.Err(err)
}
```

For multi-return methods:

```go
if err != nil {
    return nil, span.Err(err)
}
```

If the current method receives the original SQL, HTTP, parse, decode, or other low-level error, classify it according to `error-handling` and then record it:

```go
if err != nil {
    return span.Err(errors.Join(&proterror.Internal{}, err))
}
```

Do not add a second `errors.Join`, `fmt.Errorf`, or `proterror` type merely because an error crosses another traced method. Do not use `span.Err` as a substitute for a returned error; return its result through the method's normal error path.

## Asynchronous Propagation

The base template does not currently provide `internal/pkg/trace-carrier`. Do not reference or invent that package silently.

When a feature must continue a trace across an outbox row, queue message, scheduled retry, or another durable boundary:

1. search for an established carrier type and serialization format
2. if none exists, make the new provider-neutral carrier an explicit planned component under `internal/pkg`
3. inject and extract standard propagation fields rather than serializing `context.Context`
4. persist only trace metadata required for propagation
5. restore it onto the live worker or consumer context so cancellation and deadlines remain meaningful
6. test a publish/consume round trip and malformed or missing carrier data

Ownership remains split:

- delivery or application passes the live context to the publishing port
- infrastructure serializes propagation metadata into the technical envelope
- delivery workers or consumers extract the carrier before calling application services
- domain entities and domain events remain free of OpenTelemetry and transport mechanics unless an approved contract explicitly says otherwise

Missing carrier data should start a normal new operation unless the feature contract requires rejection. Never write placeholder carrier JSON when a live context is available, and never store a whole context.

## Examples

Application or delivery method propagating an already-classified error:

```go
func (s *Service) Do(ctx context.Context) error {
    ctx, span := prospan.Start(ctx)
    defer span.End()

    if err := s.repo.Save(ctx); err != nil {
        return span.Err(err)
    }

    return nil
}
```

Repository method classifying its own database error:

```go
func (r *Repository) Save(ctx context.Context) error {
    ctx, span := prospan.Start(ctx)
    defer span.End()

    if _, err := r.db.ExecContext(ctx, query); err != nil {
        return span.Err(errors.Join(&proterror.Internal{}, err))
    }

    return nil
}
```

## Completion Check

Confirm:

- every span starts from and propagates the incoming context
- spans end on all paths
- request attributes are safe and bounded
- lower-layer errors are not reclassified
- locally originating errors follow `error-handling`
- asynchronous propagation uses an established, tested carrier contract
- no business logic changed as a side effect of instrumentation
