---
name: field-validation
description: Own field-shape validation at the earliest trusted boundary in Firestarter Go code. Use when adding or changing request or DTO fields, protobuf `buf.validate` rules, ProtoValidate wiring, non-protobuf boundary checks, or duplicated validation logic; pair with the relevant layer skill and keep domain invariants in `domain-entity`.
---

# Field Validation

## Overview

Apply a strict validation ownership rule in Go backend code:

- validate externally supplied fields once at each independent trust boundary
- place the rule at the earliest defining boundary that all relevant callers actually cross
- for gRPC requests, the `.proto` field plus validation middleware is that boundary
- prefer contract-level validation with `buf.validate` rules in `.proto` files plus `grpcmw.ProtoValidate(validator)` middleware whenever the rule can be expressed there
- feel free to add or update `buf.validate` annotations in proto contracts when introducing or touching protobuf request fields
- do not scatter field-by-field validation across application, repository, or gateway methods
- do not duplicate validation after a field has already been validated at its first occurrence
- if a lower layer still needs validation, keep it in one helper such as `validate()` or `validateRequest()`

This skill is about field-shape validation ownership, not about moving or removing domain invariants.

## Main Rule

Validate field shape at the earliest trusted boundary for that caller path. Do not assume an API validator covered worker, consumer, cron, or direct application callers.

## First Trusted Occurrence Rule

Validate each field where it is first defined or introduced, not wherever it is later consumed.

- If a field first appears in a `.proto` message, add `buf.validate` rules in that proto contract when possible.
- If a field first appears in a non-protobuf transport DTO, validate it at that DTO boundary.
- If a field is first introduced at an application, repository, gateway, or converter boundary and callers can supply it independently, that layer owns the first validation for that path.
- After a field is validated at first occurrence, do not repeat the same presence, emptiness, enum, range, format, or positivity
  check in later layers.
- A lower layer may validate the same field only when:
  1. that lower-layer method has another real caller that bypasses the first occurrence owner, or
  2. the check is a domain invariant, not field-shape validation.

Do not add duplicate lower-layer validation merely because a method has side effects.

For gRPC transport DTOs, the preferred first-occurrence mechanism is protobuf contract validation:

- define request field rules with `buf.validate` in the proto contract when the rule can be expressed there
- rely on `grpcmw.ProtoValidate(validator)` middleware to enforce those rules before the handler logic runs
- avoid re-implementing the same request field checks manually in handler or service code

If a protobuf request shape can be validated with `buf.validate`, that is the best option in this codebase.

Examples of first-occurrence checks when a transport DTO owns the field:

- required request fields
- enum presence checks
- string trimming and emptiness checks for request DTOs
- numeric ranges and positivity
- string formats and lengths
- pagination limit bounds
- mutually exclusive request fields

Do not repeat those checks in downstream public methods unless the lower layer truly has an independent entry path.

For protobuf-backed gRPC handlers, prefer this order:

1. `buf.validate` annotations in the proto contract
2. `grpcmw.ProtoValidate(validator)` middleware
3. manual code validation only for rules that cannot be expressed in the contract or are true domain invariants

## Public Method Rule

After first-occurrence validation has already happened, avoid this style in later public method bodies:

```go
if req.TokenID == "" { ... }
if req.Address == "" { ... }
if req.Amount.IsZero() { ... }
```

Prefer one of these:

1. no validation there because the field was already validated at first occurrence
2. a single helper call near the top:

```go
if err := req.validate(); err != nil {
	return nil, err
}
```

or:

```go
if err := validateRequest(req); err != nil {
	return nil, err
}
```

Do not leave a long sequence of field checks in the main public method body.

## Lower-Layer Exceptions

A later layer may validate request data only when at least one of these is true:

- there is an existing caller that bypasses the original first-occurrence owner
- the value is first introduced in that later layer
- the check is a domain invariant or protocol rule, not field-shape validation

Before adding lower-layer validation:

1. inspect call sites
2. identify where the field first occurs in code
3. classify the check as field-shape validation or a deeper invariant

If all callers come through the same first-occurrence owner and the field was already validated there, do not add
the same check later.
Side effects alone are not a reason to duplicate first-occurrence validation.

Even then:

- centralize the checks in one helper
- keep the public method body focused on flow
- avoid re-validating basic field shape already enforced at first occurrence

## Domain Invariants vs Field Validation

Keep this distinction:

- Field-shape validation:
  - belongs at first occurrence in code
  - examples: empty string, missing enum, malformed cursor, missing address field

- domain invariant / protocol constraint:
  - may belong deeper
  - examples: unsupported network-currency pair, impossible state transition, insufficient allowance, unsupported chain asset mapping

If deeper validation is domain-specific, prefer a single helper with a domain name that makes that explicit.

## Refactoring Pattern

When you encounter scattered validation:

1. identify which checks are plain field-shape validation
2. move those to the field's first occurrence when feasible
3. remove repeated lower-layer checks
4. for remaining lower-layer rules, extract a single helper
5. keep the main method body focused on orchestration and side effects

## Preferred Shapes

Validation at first occurrence:

```go
func (h *Handler) Create(ctx context.Context, req CreateRequest) (*CreateResponse, error) {
	if err := req.Validate(); err != nil {
		return nil, err
	}

	return h.app.Create(ctx, req.toDomain())
}
```

Lower-layer helper when still needed:

```go
func (i *Implementation) Withdraw(ctx context.Context, req WithdrawRequest) (*WithdrawResponse, error) {
	if err := validateWithdrawRequest(req); err != nil {
		return nil, err
	}

	// main flow
}
```

Preferred gRPC path:

```go
server.WithGRPCUnaryMiddlewares(
	grpcmw.ProtoValidate(validator),
)
```

```proto
message CreateRequest {
  string wallet = 1 [(buf.validate.field).string.min_len = 1];
}
```

Avoid:

```go
func (i *Implementation) Withdraw(ctx context.Context, req WithdrawRequest) (*WithdrawResponse, error) {
	if req.AddressFrom == "" { ... }
	if req.AddressTo == "" { ... }
	if req.Network == 0 { ... }
	if req.Currency == 0 { ... }
	// more checks...
}
```

Avoid duplicated service validation after delivery already mapped the same fields:

```go
func (i *Implementation) BookOutcome(ctx context.Context, req service.BookOutcomeRequest) error {
	if req.ClientID == "" { ... }
	if req.TokenID == "" { ... }
	if req.PrivateKey == "" { ... }
	if !req.Amount.IsPositive() { ... }
}
```

Prefer:

```go
func (i *Implementation) BookOutcome(ctx context.Context, req service.BookOutcomeRequest) error {
	// business flow only
}
```

## Workflow

When applying this skill:

1. identify where each field first appears
2. inspect all callers of the lower-layer method before adding validation there
3. if the field first appears in a `.proto` message, add or update `buf.validate` annotations when the rule can be expressed there
4. prefer proto-contract validation plus `grpcmw.ProtoValidate(validator)` over manual request field checks
5. classify each remaining check as field-shape validation or deeper domain invariant
6. keep field-shape validation at first occurrence only
7. add lower-layer validation only when an exception is proven
8. collapse any remaining lower-layer checks into one helper
9. keep public method bodies short and readable
10. preserve behavior unless the user asked to change validation semantics

## Constraints

- Do not duplicate the same field validation across layers
- Do not manually validate protobuf request fields in code when `buf.validate` can express the rule
- Do not skip proto validation when adding or touching protobuf fields whose field-shape rules are known
- Do not inline many repeated request checks in later public methods
- Do not move true domain invariants to an earlier layer just for style
- Prefer one helper over many tiny boolean helpers
- Keep diffs minimal when refactoring existing code
