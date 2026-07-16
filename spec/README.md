# Feature Specs

Each non-trivial Firestarter feature gets a numbered folder:

```text
spec/001-feature-init/
spec/002-add-user-api/
spec/003-provider-gateway/
```

Use the next available three-digit prefix and a short kebab-case feature name.

Expected files:

```text
proposal.md
requirements.md
acceptance_criteria.md
constraints.md
verification.md
plan.md
```

Start with `proposal.md`, then use prompts from `prompt/` to produce the remaining files one approved stage at a time. An in-progress folder may contain only the artifacts approved so far; it is not implementation-ready until `verification.md` says ready and `plan.md` is explicitly approved.

`001-feature-init` is the seed proposal for the workflow and is intentionally incomplete until its remaining stages are reviewed.
