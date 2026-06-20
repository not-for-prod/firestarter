---
name: gateway-layer
description: Design, review, refactor, or implement this repository's Go gateway layer. Use for `implement gateway @<gateway path> <docs link>` and `implement http gateway @<gateway path> <docs link>` requests, or work under `internal/domain/gateway` or `internal/infrastructure/gateway`, including domain gateway interfaces, provider docs, config, auth/signing, transport DTOs, conversion boundaries, error handling, gateway tests, and HTTP/Resty client setup when the provider uses HTTP.
---

# Gateway Layer

## Purpose

Use this skill as the single source of truth for gateway contracts and external API implementations. It covers both design questions and implementation tasks such as `implement gateway @internal/infrastructure/gateway/... <docs link>`.

Gateways are infrastructure adapters behind domain-facing interfaces. Most provider gateways in this repository are HTTP gateways; when the provider uses HTTP, apply the HTTP/Resty rules below.

## Ownership

- `internal/domain/gateway` owns interfaces and domain-facing request/response contracts used by application services.
- `internal/infrastructure/gateway/<provider>-gateway` owns provider clients, HTTP/Resty wiring when applicable, provider DTOs, auth/signing, provider error handling, and transport mapping.
- `config` owns provider runtime configuration such as base URL, timeout, credentials, network IDs, and debug flags.
- `internal/pkg/convert` owns reusable transport-neutral mapping only when conversion is shared outside one gateway method/package.

Do not put provider clients, Resty clients, JSON transport structs, provider auth fields, HTTP status codes, SDK response types, or provider-shaped responses into domain gateway contracts.

## Package Shape

Gateway implementation packages usually contain:

- `implementation.go` for shared client wiring, config usage, auth/signing hooks, and interface assertion
- one public method per file, named after the method in snake_case
- private request/response transport models colocated with the method that owns them
- focused tests for request construction, response mapping, auth helpers, and error handling

Prefer provider-local packages over one generic client package containing unrelated integrations.

## Domain Contracts

Domain gateway contracts should be narrower than provider responses. Include only fields the application/domain currently needs.

Avoid:

- JSON tags in domain gateway DTOs
- Resty, HTTP, SDK, or provider client types in domain contracts
- provider-specific auth fields in application-facing requests
- copying entire provider responses upward to avoid mapping

Use typed enums for provider options with a documented closed set, and convert them to provider strings inside the gateway.

## Config

Before adding gateway wiring, inspect the existing config shape. Add only fields required by the provider docs or existing package conventions.

Typical fields:

- `BaseURL string`
- `Timeout time.Duration`
- `Debug bool`
- API key, bearer token, secret, private key, or network identifiers when required

Keep config parsing and validation in config loading. Gateway methods should consume typed, trusted config values.

## HTTP / Resty Wiring

Use `github.com/go-resty/resty/v2` for HTTP gateways unless the target package already uses a provider SDK or another justified client. For non-HTTP gateways, keep the same domain/infrastructure boundary rules and follow the provider client pattern already established in the target package.

Typical constructor:

```go
type Implementation struct {
    httpClient *resty.Client
}

func NewImplementation() *Implementation {
    return &Implementation{
        httpClient: resty.New().
            SetBaseURL(config.Instance().Provider.BaseURL).
            SetTimeout(config.Instance().Provider.Timeout).
            SetDebug(config.Instance().Provider.Debug),
    }
}
```

If provider docs require auth or signing, attach it once through gateway-local wiring such as `OnBeforeRequest`. Do not duplicate signing logic in each method.

## Transport Models

Keep endpoint constants, request payload structs, response payload structs, and mapping helpers in the method file that uses them unless multiple methods genuinely share the same transport contract.

Use private transport DTOs with exact provider JSON field names. Do not reuse domain DTOs as raw HTTP payloads, and do not add provider tags to domain models.

Preferred helper names:

- `new<Method>Request(...)`
- `(r <method>Response) toDomain()`
- `(r <method>Response) toDTO()` when the domain gateway contract returns a DTO

Use `internal/pkg/convert` only for reusable, provider-neutral mapping.

## Implementation Workflow

When implementing a gateway from docs:

1. Inspect the target domain gateway interface and infrastructure package.
2. Inspect config and adjacent gateways for local style.
3. Inspect the provider docs before editing.
4. Identify endpoint path, method, params, body, status codes, response shape, and auth/signing requirements.
5. Add or adjust config fields only when required.
6. Wire the provider client once in shared gateway code. For HTTP providers, wire the Resty client and auth/signing once.
7. Add private transport request/response models near each method.
8. Implement the provider call with context propagation. For Resty HTTP calls, use `SetContext(ctx)`.
9. Map provider responses into domain-facing DTOs/entities.
10. Preserve local tracing and error conventions.
11. Add focused tests that do not require live provider access unless the repo already has explicit env-gated integration tests.

If docs are ambiguous, inspect adjacent code first, choose the safest endpoint only when defensible, and state the ambiguity.

## Method Shape

Typical HTTP method:

```go
func (i *Implementation) GetSomething(ctx context.Context, req gateway.GetSomethingRequest) (*gateway.GetSomethingResponse, error) {
    ctx, span := prospan.Start(ctx)
    defer span.End()

    restyReq := i.httpClient.R().
        SetContext(ctx).
        SetQueryParams(newGetSomethingRequest(req).queryParams())

    resp, err := restyReq.Get(getSomethingEndpoint)
    if err != nil {
        return nil, span.Err(errors.Join(&proterror.Unavailable{}, err))
    }
    if resp.StatusCode() != http.StatusOK {
        return nil, span.Err(errors.Join(&proterror.Internal{}, errors.New(resp.String())))
    }

    var body getSomethingResponse
    if err = json.Unmarshal(resp.Body(), &body); err != nil {
        return nil, span.Err(errors.Join(&proterror.Internal{}, err))
    }

    return body.toDomain(), nil
}
```

Match the package's existing use of `SetResult`, `SetError`, SDK responses, or custom helpers when present.

## Testing

Prefer deterministic tests that validate:

- request DTO mapping
- response-to-domain mapping
- status/error handling
- auth/signing helper behavior
- endpoint/path/query/body construction through `httptest` when needed

Do not add tests that call real external endpoints by default. Use live calls only when the repository already has env-gated integration tests or the user explicitly asks for them.

## Boundary Smells

Pause and re-check the design if gateway code:

- leaks provider JSON DTOs into `internal/domain/gateway`
- makes application services depend on concrete gateway packages
- hardcodes config values in methods
- manually concatenates hosts when `SetBaseURL` should own the base URL for HTTP gateways
- invents auth behavior not supported by docs
- mirrors provider responses into domain contracts without a current business need
