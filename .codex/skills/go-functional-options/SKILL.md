---
name: go-functional-options
description: Apply the functional options pattern in Go when adding or refactoring constructors or public APIs with optional arguments. Use when optional parameters would otherwise force booleans, nils, zero values, or long parameter lists at call sites, especially when the API is expected to grow. Keep required parameters explicit, model optional behavior with an opaque `Option` type and `WithX(...)` helpers, and avoid using this pattern for small private helpers or when a simple parameter struct is clearer.
---

# Go Functional Options

## Overview

Use functional options for Go constructors and public APIs that have optional behavior.

Prefer this when optional arguments are already making the signature awkward or are likely to grow.

## When to Use

Apply this pattern when one or more of these are true:

- the function is part of a public or cross-package API
- the function has optional config beyond the required inputs
- call sites are passing `nil`, `false`, `0`, or empty strings to mean "use default"
- the API already has three or more parameters and optional ones reduce readability
- you expect new optional settings to be added over time

Typical targets:

- `New...` constructors
- client or gateway builders
- server setup helpers
- exported functions with optional timeouts, loggers, hooks, limits, or feature flags

## When Not to Use

Do not introduce functional options when:

- the function is private and unlikely to grow
- all parameters are required
- the data is best represented as one explicit request or config struct
- there is only one optional field and a clear zero value already expresses the behavior
- the pattern would add more ceremony than value

Prefer the simplest shape that keeps call sites clear.

## Target Shape

Keep required arguments explicit and move optional behavior behind `Option`.

```go
type options struct {
	logger  *zap.Logger
	timeout time.Duration
	cache   bool
}

type Option interface {
	apply(*options)
}

type optionFn func(*options)

func (f optionFn) apply(opts *options) {
	f(opts)
}

func WithLogger(logger *zap.Logger) Option {
	return optionFn(func(opts *options) {
		opts.logger = logger
	})
}

func WithTimeout(timeout time.Duration) Option {
	return optionFn(func(opts *options) {
		opts.timeout = timeout
	})
}

func NewClient(addr string, opts ...Option) (*Client, error) {
	cfg := options{
		logger:  zap.NewNop(),
		timeout: 5 * time.Second,
	}

	for _, opt := range opts {
		opt.apply(&cfg)
	}

	return &Client{}, nil
}
```

Call sites should read like this:

```go
client, err := NewClient(
	addr,
	WithLogger(logger),
	WithTimeout(10*time.Second),
)
```

## Workflow

When applying this skill:

1. identify which parameters are required and keep them explicit
2. group only optional behavior into an internal `options` struct
3. set defaults before applying options
4. define an opaque `Option` type with small `WithX(...)` helpers
5. update call sites to remove placeholder values like `nil` and `false`
6. keep option names behavior-oriented and predictable

## Constraints

- do not hide required dependencies inside options
- do not expose the internal `options` struct unless a plain config struct is the better API
- do not use option names that silently combine unrelated behavior
- validate invalid option combinations in one place near construction
- preserve existing behavior by keeping previous defaults

## Review Heuristics

Prefer a refactor if the current API looks like:

```go
NewClient(addr, nil, false, 0)
```

Be cautious if the proposed result is more complex than the original call sites.
