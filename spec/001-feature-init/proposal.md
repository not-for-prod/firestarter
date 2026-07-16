# Proposal: Feature Init

## Summary

Add a lightweight spec-driven development structure to Firestarter.

## Problem

Firestarter should support a repeatable workflow for designing non-trivial features before implementation starts. The repository currently has code layout conventions, but it does not provide a place for feature specs or reusable prompts that guide an AI coding agent through requirements, acceptance criteria, constraints, verification, planning, and execution.

## Goals

- Add a `prompt/` folder with reusable SDD prompts.
- Add a `spec/` folder where each feature has its own numbered folder.
- Seed the first feature folder as `spec/001-feature-init/`.
- Keep the workflow lightweight enough to use during normal development.
- Align the spec workflow with Firestarter's existing Go layer ownership.

## Non-Goals

- Do not introduce a new code generator.
- Do not require every small code change to have a full spec.
- Do not change application code as part of this feature.
- Do not replace existing `.agents/skills` guidance.

## Initial Shape

```text
prompt/
  00-proposal-to-requirements.md
  01-requirements-to-acceptance-criteria.md
  02-architecture-constraints.md
  03-verification.md
  04-task-list.md
  execute.md

spec/
  001-feature-init/
    proposal.md
```
