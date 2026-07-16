# Agent Guidance

## Project Shape

Firestarter is a Go service template. Treat it as a backend repository unless the task explicitly introduces another product surface.

Key paths:

- `api/`: protobuf API contracts.
- `cmd/`: application entrypoint and dependency wiring.
- `config/`: runtime configuration.
- `internal/domain/`: domain entities, repository interfaces, gateway interfaces, and domain services.
- `internal/application/`: application commands and queries.
- `internal/delivery/`: generated-contract adapters, API handlers, and feature workers when introduced.
- `internal/infrastructure/`: concrete repository and gateway adapters.
- `internal/generated/`: generated protobuf and xo output.
- `internal/pkg/`: shared infrastructure packages such as connectors, middleware, health checks, and workers.
- `tools/migrations/`: Goose database migrations.
- `tools/xo-templates/`: xo database model generation templates.
- `prompt/`: reusable spec-driven development prompts.
- `spec/`: feature specifications.

## Skill Routing

Use repository skills from `.agents/skills/<skill-name>/SKILL.md` when a matching skill exists. Read the full `SKILL.md` before acting.

Common routing:

- End-to-end or cross-layer feature delivery: `deliver-feature`, then only the specialized skills selected for the current task.
- Application service work: `application-layer`.
- API handlers, workers, consumers, and delivery mapping: `delivery-layer`.
- Domain entities and value objects: `domain-entity`.
- Repository interfaces or PostgreSQL implementations: `repository-layer`.
- Gateway interfaces or third-party clients: `gateway-layer`.
- Protobuf contracts and field validation: the external `protobuf-schema-authoring` skill when installed, then `field-validation`.
- Error classification and wrapping: `error-handling`.
- Tracing: `tracing`.
- Repository or gateway method-file organization: `method-per-file`.
- Optional constructor or public API arguments: `go-functional-options`.
- Focused Go style, naming, helper extraction, and uncertain design decisions: `go-code-style`, `naming`, `function-decomposition`, and `engineering-judgment`.
- Lint and verification cleanup: `go-linter-workflow`.
- Project placement questions: `project-layout`.

For an end-to-end feature, use `deliver-feature` as the coordinator and load the most specific skills task by task. For an isolated change, skip the coordinator and use the narrowest matching skill directly. Do not load broad style skills when no corresponding decision is present.

## Go Development Workflow

Follow the existing architecture and generated-code boundaries.

- Keep domain types and interfaces under `internal/domain`.
- Keep shared infrastructure primitives under `internal/pkg`.
- Put migrations in `tools/migrations`.
- Do not edit generated files by hand when they can be regenerated.
- Use `gofmt`/`goimports` style through the project tooling.
- Keep tests close to the package being changed.

Useful commands:

- `make dependency`: install project generator tools and add or update the template's unpinned helper dependencies; review resulting `go.mod` and `go.sum` changes.
- `make infra`: start local dependencies.
- `make migrations-up`: apply migrations.
- `make migrations`: destructively reset and re-apply the local database; use only when a local reset is explicitly safe.
- `make pb`: update Buf dependencies, lint protos, and generate protobuf code.
- `make xo`: regenerate xo database models from the local database.
- `make generate`: run protobuf, xo, and `go generate ./...`.
- `make fmt`: run the configured formatter.
- `make linter`: run `golangci-lint`.
- `make skills-validate`: validate repository-local skill frontmatter, metadata, references, and scaffold cleanup without external Python packages.
- `go test ./...`: run the Go test suite.

Run the narrowest relevant verification during iteration, then broaden to package or repository checks when the change affects shared behavior, generated contracts, or wiring.

## Generated Code

When changing protobuf contracts, migrations, or generation templates, run the matching generation command and include generated output in the same logical change.

- Protobuf changes usually require `make pb`.
- Migration/schema changes usually require `make migrations-up` and `make xo` against local Postgres.
- Cross-cutting generated-code changes usually require `make generate`.

If local infrastructure or required generators are unavailable, report the exact command that could not be run and why.

## Spec-Driven Development

Use the SDD flow for non-trivial feature work. Small bug fixes, documentation updates, mechanical refactors, and narrow test additions do not need a full spec unless the user asks for one.

Before implementation for a non-trivial feature:

1. Start from the current base branch, normally `main`, and create a feature branch when branch management is in scope.
2. Create a feature folder under `spec/<number>-<feature-name>/`.
3. Use the prompts in order:
   - `prompt/00-proposal-to-requirements.md`
   - `prompt/01-requirements-to-acceptance-criteria.md`
   - `prompt/02-architecture-constraints.md`
   - `prompt/03-verification.md`
   - `prompt/04-task-list.md`
   - `prompt/execute.md`
4. After each SDD stage, provide a compact review summary and wait for explicit human approval before continuing to the next stage.
5. Do not start implementation until `verification.md` says ready and `plan.md` is explicitly approved.

Each review summary should include:

- TL;DR: at most 5 bullets.
- Decisions made: at most 7 bullets.
- Assumptions introduced: at most 7 bullets.
- Open questions: at most 5 bullets.
- Risk or rollback notes: at most 5 bullets.
- What changed from the original proposal or previous stage.

During execution, implement one planned task at a time, run the task verification commands, record what changed, and stop at checkpoints before continuing when the SDD plan requires approval.

## Commit Messages

Use conventional commit prefixes matching the repository style:

- `feat:` for user-facing features and implementation tasks.
- `fix:` for bug fixes.
- `docs:` for documentation-only changes.
- `test:` for test-only changes.
- `chore:` for tooling, generated files, or maintenance changes.

Before committing, check `git status --short` and avoid staging unrelated user changes.

## Working Tree Safety

The worktree may contain user edits. Do not revert or overwrite changes you did not make. If unrelated files are dirty, leave them alone. If user edits overlap with the task, read them carefully and build on top of them.
