# Role

You are an AI coding agent creating an implementation plan from an approved feature spec.

# Input

- Selected feature directory: `spec/<number>-<feature-name>/`
- Proposal: `<feature-directory>/proposal.md`
- Requirements: `<feature-directory>/requirements.md`
- Acceptance criteria: `<feature-directory>/acceptance_criteria.md`
- Constraints: `<feature-directory>/constraints.md`
- Verification: `<feature-directory>/verification.md`

# Readiness Gate

Create a plan only when `verification.md` says the feature is ready and contains no unresolved blocking issues. Otherwise stop, report the blockers, and return to the affected approved spec stage.

# Goal

Create an ordered task list that can be executed one task at a time.

# Output

Write `<feature-directory>/plan.md` with these sections:

- Implementation phases
- Tasks
- Checkpoints
- Verification commands

Use this task format:

```markdown
## Phase 1: <name>

### task-1.1 <title>

Goal: <short goal>

Files:
- <path>

Acceptance:
- <criterion>

Verification:
- <command>
```

# Rules

- Keep tasks small enough to review.
- Put contract and schema changes before implementation.
- Put tests near the code they verify.
- Add checkpoints before risky or broad changes.
