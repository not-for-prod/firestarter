# SDD Prompts

This folder contains reusable prompts for Firestarter's spec-driven development workflow.

Use them in order for non-trivial features:

1. [00-proposal-to-requirements.md](./00-proposal-to-requirements.md)
2. [01-requirements-to-acceptance-criteria.md](./01-requirements-to-acceptance-criteria.md)
3. [02-architecture-constraints.md](./02-architecture-constraints.md)
4. [03-verification.md](./03-verification.md)
5. [04-task-list.md](./04-task-list.md)
6. [execute.md](./execute.md)

Each feature lives in its own folder under `spec/`.

Select that feature directory before running a stage. Every input and output path in the prompts is relative to the selected directory; do not rely on the shell's current working directory or overwrite artifacts from another feature.

Example:

```text
spec/001-feature-init/
  proposal.md
  requirements.md
  acceptance_criteria.md
  constraints.md
  verification.md
  plan.md
```
