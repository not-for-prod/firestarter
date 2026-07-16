---
name: delivery-layer
description: Design, implement, review, or refactor Firestarter delivery adapters under `internal/delivery`, including generated gRPC or HTTP service handlers, scheduled workers, consumers, transport mapping, independent boundary validation, acknowledgements, and registration in the existing `cmd` Fx modules. Use when exposing an application service through an API or invoking it from a worker; keep business transitions and persistence out of delivery code.
---

# Delivery Layer

## Purpose

Delivery adapters translate an external trigger into one application command or query and translate the result back to the caller or transport. They own protocol mechanics, request mapping, worker loops, and transport progress. They do not own aggregate transitions, transactions, persistence, or provider integration.

Use the generated API contract or the transport's message contract as the delivery boundary. Use `application-layer` for the use case behind that boundary.

## Ownership

- `.proto` files under the existing service subtree in `api/` own public request, response, and service contracts.
- Generated protobuf and Clay artifacts under `internal/generated` own generated handler interfaces and descriptors.
- `internal/delivery/api` owns concrete gRPC or HTTP handlers and transport/domain mapping.
- `internal/delivery/worker` owns scheduled jobs, polling, decoding, grouping, retry or acknowledgement decisions, and calls to application services.
- Existing `cmd/*.go` modules own Fx providers, service descriptor registration, and worker registration.
- `internal/application` owns commands, queries, transactions, aggregate loading, state transitions, persistence intent, and domain-event publication.

Follow the closest existing package shape. Do not hard-code the template's pre-initialization service name; `make init` renames the API subtree and module.

## API Handler Workflow

For a generated API method:

1. inspect the `.proto` source and generated handler interface
2. confirm field-shape rules are expressed with `buf.validate` where possible
3. map the protobuf request into a domain-facing application request
4. call one application command or query
5. map the application response into the generated protobuf response
6. propagate classified errors for the existing middleware to translate
7. register the implementation and generated descriptor through the existing Fx composition path

Keep handlers thin. Small mapping helpers may stay next to the method. Move reusable transport-neutral conversion only when more than one real caller needs it.

Do not:

- load repositories or gateways directly from a handler
- start a database transaction in delivery code
- mutate aggregate fields or construct aggregate lifecycle events
- expose infrastructure DTOs or xo models through protobuf mapping
- duplicate `buf.validate` checks in the handler without a boundary-specific reason
- convert every lower-layer error into `Internal`

## Validation Boundaries

Every independent trust boundary validates the shape it receives:

- API requests should use `buf.validate` plus the configured `grpcmw.ProtoValidate(validator)` middleware when the rule is expressible in protobuf.
- Worker or consumer payloads must be validated after decoding because they may bypass protobuf middleware.
- Authentication, authorization, headers, and transport metadata stay at delivery or dedicated middleware boundaries.
- Domain invariants and state-dependent transition rules stay in domain methods.

Use `field-validation` when adding fields or deciding ownership. Avoid duplicate validation only when all callers are proven to pass through the same trusted validator.

## Error And Tracing Boundaries

Use `error-handling` as the authority for constructing and classifying errors. Delivery may classify a new parsing, decoding, authentication, or boundary-validation error. It must not reclassify an error already owned by application, repository, gateway, or domain code.

Use `tracing` for span lifecycle. Record only request fields that are safe for telemetry; do not attach credentials, tokens, private keys, raw payloads, or unreviewed PII through `prospan.WithRequest`.

Let the existing proterror middleware map classified service errors to protocol responses. Do not duplicate protocol mapping inside every handler unless generated contracts require it.

## Scheduled Worker Workflow

The shared `internal/pkg/worker` package owns scheduling mechanics and the `worker.Worker` interface. A feature worker should provide a focused job function or implementation that:

1. receives the scheduler context
2. decodes the trigger or obtains queue, inbox, or outbox work through an established delivery-owned transport port
3. validates the incoming payload or work item
4. groups items into a batch application request when the use case is naturally batched
5. calls one application command or query
6. acknowledges, deletes, or advances transport progress only according to the transport's success contract

The worker chooses when and how work is delivered. The application service decides the business unit of work.

Do not put these in a worker:

- aggregate loading for a lifecycle transition
- direct state mutation or event construction
- SQL or repository batch loops
- provider response interpretation that belongs in a gateway
- direct provider calls that should be an application use case behind a domain gateway
- one application call per item when a safe batch command is the established use case

Define partial-failure and acknowledgement behavior explicitly. Never acknowledge failed work merely because the worker logged an error.

## Consumers And Asynchronous Messages

For queue or broker consumers, keep envelope decoding, offsets, retry, dead-letter behavior, and acknowledgements in delivery. Map the decoded message into a domain-facing application request before calling the service.

Restore asynchronous trace context only when the repository has an established carrier format. Do not invent a serialized carrier ad hoc or persist an entire `context.Context`.

## Composition

Make the adapter reachable through the current composition root:

- provide the concrete handler, worker, and required application interfaces through Fx
- register generated service descriptors in `cmd/public_service_module.go` using the generated API package's actual descriptor API
- include feature workers in the collection returned by `provideWorkers` or the current group pattern
- add typed config and config-source fields together when a worker or transport needs settings
- keep provider constructors and infrastructure dependencies outside delivery packages

Inspect `cmd/main.go`, `cmd/public_service_module.go`, and `cmd/workers_module.go` before editing. Extend the existing modules instead of introducing another entrypoint layout.

## API Tests

Add focused tests for behavior owned by delivery:

- transport request to application request mapping
- application response to protobuf response mapping
- boundary validation that is not already fully covered by protovalidate
- propagation of classified application errors
- descriptor or handler conformance when generated interfaces make that test useful

Use application mocks or small fakes. Handler tests should not require PostgreSQL or live providers unless the repository already has an explicit integration-test path.

## Worker Tests

Test the worker-specific contract:

- disabled and interval config when feature code owns it
- payload decoding and validation
- grouping or batching behavior
- application request mapping
- acknowledgement on success
- no acknowledgement or the documented retry path on failure
- cancellation and context propagation for blocking work

Do not retest application business rules through the worker.

## Completion Check

Before finishing delivery work, confirm:

- generated contracts were changed at their source and regenerated
- validation occurs at every independent ingress
- the adapter calls an application interface rather than infrastructure directly
- classified errors and trace context are propagated without leaking sensitive payloads
- the handler descriptor or worker is registered in Fx
- focused delivery tests pass
- broader compile, test, and lint checks cover the changed wiring

## Boundary Smells

Re-check the design if delivery code contains SQL, xo models, Resty calls, provider DTOs, database transactions, aggregate field assignment, manual lifecycle events, or repository calls. Those are strong signals that application or infrastructure ownership has leaked outward.
