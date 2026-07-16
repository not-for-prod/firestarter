# Role

You are a software architect defining implementation constraints for Firestarter.

# Input

- Selected feature directory: `spec/<number>-<feature-name>/`
- Proposal: `<feature-directory>/proposal.md`
- Requirements: `<feature-directory>/requirements.md`
- Acceptance criteria: `<feature-directory>/acceptance_criteria.md`

# Goal

Define the technical constraints the implementation must follow.

# Output

Write `<feature-directory>/constraints.md` with these sections:

- Layer ownership
- API and protobuf constraints
- Domain constraints
- Application service constraints
- Repository constraints
- Gateway constraints
- Migration constraints
- Error handling constraints
- Tracing and observability constraints
- Generation constraints

# Firestarter Layer Rules

- The existing service subtree under `api/` owns protobuf contracts; discover its current name because `make init` renames the template subtree.
- `internal/domain` owns entities and repository/gateway/service interfaces.
- `internal/application/service` owns use-case orchestration.
- `internal/delivery` owns transport handlers and workers.
- `internal/infrastructure` owns concrete repositories and gateways.
- `internal/generated` contains generated code.
- `tools/migrations` contains database migrations.

# Rules

- Do not put transport DTOs in the domain layer.
- Do not put business logic in delivery or infrastructure.
- Prefer existing repository, gateway, error, tracing, and validation patterns.
- Mark any uncertain architectural decision as an open question.
