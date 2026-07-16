---
name: deliver-feature
description: Coordinate end-to-end delivery of a Firestarter backend feature from request triage or an approved spec through implementation, generated code, verification, and handoff. Use when the user asks to add, build, implement, or deliver a non-trivial feature that spans multiple service layers, changes protobuf or database contracts, introduces an external integration, or must follow the repository's `prompt/` and `spec/` SDD workflow; use a narrower skill directly for isolated edits.
---

# Deliver Feature

## Purpose

Use this skill as the feature coordinator. It selects the delivery route, enforces spec and approval gates, loads only the layer skills needed by the current task, and keeps source contracts, generated code, wiring, tests, and handoff synchronized.

Treat `AGENTS.md` as the repository-wide authority. Treat each narrower skill as the authority for its own layer. Do not copy every layer rule into the feature plan or load the whole skill package preemptively.

## Choose The Delivery Route

Classify the request before editing:

| Route | Use when | Action |
| --- | --- | --- |
| Approved SDD execution | A ready spec and approved `plan.md` already exist | Resume the first incomplete task; do not recreate the spec |
| New non-trivial feature | Behavior, contracts, storage, integration, or multiple layers must be designed together | Run the full SDD workflow and stop at every approval gate |
| Narrow change | The behavior is known and the change is an isolated bug fix, test, documentation edit, adapter method, or mechanical refactor | Skip SDD unless the user asks for it; use the narrowest matching skill |
| Diagnose or review | The user asks for analysis rather than implementation | Inspect and report; do not mutate code or external state |

Treat a change as non-trivial when any of these materially affect the outcome:

- product behavior or acceptance criteria are ambiguous
- protobuf compatibility, a migration, or generated contracts change
- domain, application, delivery, and infrastructure decisions must stay coherent
- an external provider, security boundary, data migration, or rollback path is introduced
- implementation needs multiple independently reviewable tasks or checkpoints

Use risk and decision count, not file count, to classify the change.

## Inspect Before Planning

1. Read `AGENTS.md`, the relevant source files, nearby tests, and local generation or wiring patterns.
2. Run `git status --short` and preserve unrelated user changes. Never assume a clean worktree.
3. Search `spec/` for an existing feature folder before creating another one.
4. Identify source-of-truth files and their generated outputs before editing either.
5. Inspect `Makefile`, `go.mod`, and adjacent packages before adding tools or dependencies.
6. Manage branches or commits only when the user placed them in scope.

State only assumptions that can affect behavior, compatibility, ownership, or verification. Ask for input only when a missing decision would make safe progress impossible.

## Run The SDD Workflow

For a new non-trivial feature, create the next unused three-digit folder under `spec/` with a short kebab-case name. Begin with `proposal.md`, then use these prompts in order:

1. `prompt/00-proposal-to-requirements.md` -> `requirements.md`
2. `prompt/01-requirements-to-acceptance-criteria.md` -> `acceptance_criteria.md`
3. `prompt/02-architecture-constraints.md` -> `constraints.md`
4. `prompt/03-verification.md` -> `verification.md`
5. `prompt/04-task-list.md` -> `plan.md`
6. `prompt/execute.md` -> one approved task at a time

After every stage:

1. write the artifact in the selected feature folder
2. provide the compact review summary required by `AGENTS.md`
3. stop and wait for explicit approval

Do not infer approval from the presence of a file. Do not create `plan.md` while `verification.md` reports blockers or is not ready. Do not implement until the spec is ready and the plan is approved.

If a feature folder already exists, continue from the first missing or explicitly unapproved stage. Do not overwrite approved decisions silently; record and re-approve necessary spec changes before implementation continues.

## Route To Narrower Skills

Read the full skill for every selected concern before editing that concern. Select the minimum useful set:

| Concern | Primary skill | Add when needed |
| --- | --- | --- |
| Uncertain ownership or design | `engineering-judgment` | `project-layout` for the final path decision |
| Protobuf contract | `protobuf-schema-authoring` when available | `field-validation` for `buf.validate` and boundary ownership |
| Aggregate, value object, invariant, event | `domain-entity` | `naming` when public domain language is unsettled |
| Command, query, transaction, orchestration | `application-layer` | `error-handling`, `tracing` |
| API handler, worker, consumer, mapping | `delivery-layer` | `field-validation`, `tracing`, `error-handling` |
| PostgreSQL contract or adapter | `repository-layer` | `method-per-file`, `error-handling`, `tracing` |
| Provider or external client | `gateway-layer` | `method-per-file`, `error-handling`, `tracing` |
| Config or Fx composition | `project-layout` | the skill for the implementation being wired |
| Optional constructor or public API arguments | `go-functional-options` | `go-code-style` for an ambiguous API shape |
| Long or duplicated function | `function-decomposition` | `naming` only when extracted concepts are unclear |
| Completion checks | `go-linter-workflow` | Read `.golangci.yaml` when failures are unclear |

Do not use a broad style skill as a substitute for a layer skill. Do not use `deliver-feature` for a single well-scoped repository or gateway method unless the request also needs cross-layer coordination.

## Plan In Dependency Order

Design from business meaning outward, but execute the approved plan in source dependency order:

1. settle observable behavior, compatibility, and ownership
2. change source contracts and schema such as `.proto` files and migrations
3. regenerate protobuf or xo output
4. implement domain behavior and domain-facing ports
5. implement application commands and queries
6. implement repository and gateway adapters
7. implement delivery handlers or workers
8. update config and Fx composition under `cmd`
9. add focused tests and run broader verification

The approved `plan.md` wins when a feature requires a different safe order. Do not reorder tasks silently.

## Execute One Task At A Time

For each approved task:

1. read its goal, files, acceptance criteria, and verification commands
2. inspect the target package and the selected skill instructions
3. implement only the task's coherent change
4. format and run the narrowest relevant tests during iteration
5. review the diff for generated churn, unrelated edits, and ownership drift
6. run the task verification commands
7. record files changed, behavior changed, verification, deviations, and the next task
8. stop at every checkpoint required by the plan

If implementation exposes a missing decision, contradiction, or unsafe migration, update the spec or plan and obtain approval before continuing. Do not hide scope changes inside implementation.

## Keep Generated Code Synchronized

Edit the source of truth, then use the matching generation path:

| Source change | Expected command |
| --- | --- |
| Protobuf under `api/` | `make pb` |
| New migration | start local Postgres if needed, then `make migrations-up` and `make xo` |
| Interface with `go:generate` directives | run the narrowest applicable `go generate` command |
| Multiple coordinated generated sources | `make generate` only when all required infrastructure is available |

Treat `make migrations` as a destructive local reset, not the default migration command. Do not hand-edit generated files when regeneration is available. After generation, inspect the diff and reject unrelated output churn.

If infrastructure, a generator, or network access is unavailable, report the exact command and failure. Do not claim generated output is current when it was not verified.

## Make The Feature Runnable

Before broad verification, check the integration seams affected by the feature:

- generated handler contracts have concrete delivery implementations
- application, repository, and gateway implementations are provided through Fx
- public service descriptors are registered in the existing `cmd` modules
- workers are constructed and registered with lifecycle wiring
- new config fields exist in both typed config and the relevant config source
- migrations, protobuf output, mocks, and xo models match their sources

Inspect existing `cmd/*.go` modules and config patterns; do not invent a second composition layout.

## Verify Narrow To Broad

Use a risk-based verification ladder:

1. format only changed Go files during iteration
2. run focused package tests
3. run contract, generation, or migration checks for changed sources
4. run `go test ./...` when shared behavior, wiring, contracts, or generated code changed
5. run `make linter` for completed Go changes when the installed linter supports the repository's Go version

For migration work, include an application and rollback review even when a local reset is not safe. For gateway work, use deterministic tests rather than live provider calls by default. For wiring changes, compile or run tests that construct the affected Fx graph when the repository provides them.

Never report a check as passing unless it ran successfully. Distinguish failures caused by the change from unrelated pre-existing failures.

## Completion Contract

Call the feature complete only when:

- approved acceptance criteria are implemented
- every planned task and checkpoint is complete
- source contracts and generated outputs are synchronized
- required wiring makes the feature reachable
- relevant focused and broad checks pass, or exact blockers are reported
- no unrelated user changes were overwritten or staged

Hand off with the outcome first, then list material files or behavior changed, verification run, unverified items, assumptions or approved deviations, and any operational or rollback note. Commit only when the user explicitly asks for it.
