---
name: tracing
description: Add or update tracing in Go code. Use for context-aware delivery, application, repository, gateway, worker, and adapter methods that need `prospan` spans, `prospan.WithRequest(req)` at delivery boundaries, `span.Err(...)` recording without error reclassification, or trace propagation across async boundaries using `internal/pkg/trace-carrier`.
---

# Tracing

## Overview

Apply `prospan` tracing consistently to existing Go methods that already accept `context.Context`. Add span start and end calls, use `prospan.WithRequest(req).Start(ctx)` for delivery-layer request handlers when a request model is present, and use `span.Err(...)` to record errors on the current span without reclassifying errors owned by lower layers.

Use:

```go
import "github.com/not-for-prod/observer/tracer/prospan"
```

For async boundaries, use `internal/pkg/trace-carrier` to persist propagation fields instead of trying to store a whole context.

## Workflow

Follow this sequence:

1. Inspect each target method that accepts `ctx context.Context`.
2. Add tracing start and end if missing.
3. Classify whether each error originates in the current method or is returned by a deeper method.
4. Use `span.Err(...)` on returns where the current span should record the error.
5. Add `errors.Join`, `fmt.Errorf`, or `proterror` classification only where the error originates.
6. Preserve existing behavior and keep the diff minimal.

## Start Rules

If a method accepts `ctx context.Context`, add tracing at the top:

```go
ctx, span := prospan.Start(ctx)
defer span.End()
```

Do not add tracing to methods that do not accept `context.Context`.

## Delivery Rule

For delivery-layer methods that accept a request model such as `req`, use:

```go
ctx, span := prospan.WithRequest(req).Start(ctx)
defer span.End()
```

Use `WithRequest(req)` only when both are true:

- the method belongs to the delivery layer
- a request model like `req` is available

Do not use `WithRequest(req)` in application, repository, gateway, or helper methods.

## Error Ownership

Treat `span.Err(...)` as trace/span recording. Treat `errors.Join`, `fmt.Errorf`, and `proterror` as error construction/classification.

When the current method creates or receives the original low-level error, it may both classify and record:

Use:

```go
return span.Err(errors.Join(&proterror.Internal{}, err))
```

or:

```go
return nil, span.Err(errors.Join(&proterror.Internal{}, err))
```

If the current method creates a new error at its own layer, construct and record that new error here:

```go
return nil, span.Err(fmt.Errorf("build response: %w", err))
```

If the error comes from a deeper method that already owns classification, do not add another `errors.Join`, `fmt.Errorf`, or new `proterror` type. If the current method's span should record the failure, return it through `span.Err(err)`; otherwise propagate it unchanged.

```go
if err != nil {
	return span.Err(err)
}
```

Do not double-classify or add redundant context wrappers.

## Lowest-Level Detection

Treat a method as the lowest-level error origin when it directly performs work such as:

- repository SQL calls
- HTTP client calls
- RPC or external client calls
- JSON or XML marshal/unmarshal
- parsing or validation errors produced here
- file operations
- external SDK calls
- transaction begin, commit, or rollback errors created here

If the method mainly delegates to another internal method that accepts `context.Context`, assume the deeper method owns error classification first.

## Async Trace Propagation

Use trace carriers when a workflow crosses a boundary where `context.Context` cannot travel directly:

- outbox rows
- persisted events
- queue or broker messages
- scheduled workers
- relay or retry jobs

The goal is one causal trace:

```text
request -> service -> persisted event -> worker -> downstream side effect
```

not unrelated root traces split at the async boundary.

### Ownership

- Delivery/application code passes the live `ctx` into publish methods.
- Infrastructure serializes trace metadata into transport storage such as outbox rows.
- Workers extract trace metadata from transport storage and call downstream services with the restored context.
- Domain events should not know about OpenTelemetry or storage mechanics unless the event model explicitly owns propagation metadata by design.

Keep this aligned with `project-layout`: trace carriers are technical propagation data, not business event data.

### Publish And Consume Shape

At durable handoff:

```go
carrier := trace_carrier.NewTraceCarrierFromContext(ctx)
payload := mustMarshalJSON(carrier)
```

At async consume time:

```go
var carrier trace_carrier.TraceCarrier
// load carrier from persisted transport record
workerCtx := carrier.Context()
workerCtx, span := prospan.Start(workerCtx)
defer span.End()
```

Use `ContextWith(ctx)` when a worker must preserve cancellation, transaction, or other values from the live worker context while restoring trace propagation.

### Async Workflow

When adding or refactoring an async path:

1. Find the synchronous origin that still has the request context.
2. Persist `trace_carrier.NewTraceCarrierFromContext(ctx)` at the durable handoff.
3. Preserve the carrier through transport models, repository scanning, and conversion.
4. At the async entrypoint, restore context from the stored carrier before continuing work.
5. Pass the restored context through the worker into downstream services.
6. Verify the async leg continues the originating trace instead of starting a new root.

When aggregate lifecycle work continues asynchronously, prefer the durable aggregate row as the trace anchor when the schema supports it. The outbox may also carry trace data as a relay envelope.

Do not:

- write `{}` as a placeholder trace carrier when a live `ctx` is available
- start from `context.Background()` when a consumed message carries trace metadata
- discard trace metadata during DTO or repository conversion
- leak trace propagation logic into aggregate business methods
- serialize whole contexts

## Examples

Plain context-aware method:

```go
func (s *Service) Do(ctx context.Context) error {
	ctx, span := prospan.Start(ctx)
	defer span.End()

	err := s.repo.Save(ctx)
	if err != nil {
		return span.Err(err)
	}

	return nil
}
```

Lowest-level repository call:

```go
func (r *Repository) Save(ctx context.Context) error {
	ctx, span := prospan.Start(ctx)
	defer span.End()

	_, err := r.db.ExecContext(ctx, query)
	if err != nil {
		return span.Err(err)
	}

	return nil
}
```

Delivery-layer method with request:

```go
func (h *Handler) Create(ctx context.Context, req CreateRequest) error {
	ctx, span := prospan.WithRequest(req).Start(ctx)
	defer span.End()

	return h.app.Create(ctx, req)
}
```

## Transformation Rules

When applying this skill:

- inspect each method with `context.Context`
- add tracing start and end if missing
- decide between `Start` and `WithRequest(req).Start`
- use `span.Err(...)` to record errors on the current span when local package conventions do so
- leave already-classified errors free of extra `errors.Join`, `fmt.Errorf`, or `proterror` wrapping
- keep business logic unchanged
- avoid unrelated refactors

## Constraints

- No tracing in methods without `context.Context`
- No double-wrapping
- No business-logic refactors
- No `WithRequest(req)` outside the delivery layer
- Prefer minimal diffs
