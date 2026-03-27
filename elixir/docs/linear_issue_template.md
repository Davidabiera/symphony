# Linear Issue Template for Delegated Work

Use this template when writing Linear issues that Symphony or a delegated coding agent is expected
to execute end-to-end.

The goal is not to make tickets longer. The goal is to make them mechanically runnable without
hidden chat recovery.

## Use This For

- one bounded deliverable
- one owning repo
- one review path
- one proof surface

If the issue needs multiple repos, architectural invention, product negotiation, or unclear
operator judgment, it is not ready for unattended delegated execution yet.

## Agent-Safe vs Human-Led

`Agent-safe` issues usually have all of these:

- bounded file or surface scope
- explicit source docs
- concrete acceptance criteria
- concrete validation steps
- proof expectations a reviewer can inspect cheaply

`Human-led` issues usually have one or more of these:

- cross-repo scope or hidden dependencies
- unclear success condition
- missing validation or proof expectations
- architectural choice still open
- required secrets, production access, or operator-only judgment

If an issue is still human-led, keep it out of active unattended execution until the missing fields
are made explicit.

## Canonical Template

```md
## Objective
One sentence describing the deliverable.

## Scope boundary
Allowed:
- exact files, modules, or surfaces this issue may change

No-touch:
- exact files, modules, or surfaces this issue must not change

## Source docs
- canonical repo doc
- canonical repo doc
- canonical repo doc

## Acceptance criteria
- concrete and reviewable outcome
- concrete and reviewable outcome
- concrete and reviewable outcome

## Validation
- command, check, or review step
- command, check, or review step

## Proof pack
- PR or branch review surface
- visible workpad update
- artifact or diff the reviewer can inspect

## Risk tier
Low | Medium | High

## Handoff plan
State what the reviewer should inspect first and what would force rework instead of review.
```

## Writing Rules

- Keep the issue to one bounded deliverable.
- Name exact no-touch surfaces so scope drift is obvious.
- Prefer repo-owned docs and commands over chat-only instructions.
- Put validation in the issue body, not only in comments.
- Make proof expectations visible before work starts.

## Example Shapes

### Docs-only

Use when the change is limited to documentation or workflow guidance.

```md
## Objective
Publish a reusable delegated-work issue template for Symphony.

## Scope boundary
Allowed:
- `elixir/WORKFLOW.md`
- `elixir/docs/linear_issue_template.md`

No-touch:
- runtime code under `elixir/lib/**`
- top-level product docs

## Source docs
- `SPEC.md`
- `elixir/WORKFLOW.md`
- existing SSI issue bodies in Linear

## Acceptance criteria
- template contains the required issue fields
- examples cover docs-only, repo/setup, and small implementation work
- workflow points agents to the template when issue structure is thin

## Validation
- `git diff --check`
- manual review against three existing SSI issues

## Proof pack
- PR diff
- visible workpad update
- rendered template examples in the doc

## Risk tier
Medium

## Handoff plan
Reviewer reads the template doc first, then the workflow diff, and routes to rework if scope
widened into runtime code.
```

### Repo/setup

Use when the task changes setup, launch, or local environment behavior without widening into product
features.

```md
## Objective
Make the Windows local-worker startup path deterministic and diagnosable.

## Scope boundary
Allowed:
- launcher/setup path
- startup diagnostics

No-touch:
- unrelated runtime behavior
- non-Windows worker support

## Source docs
- `SPEC.md`
- `elixir/WORKFLOW.md`
- worker launch code or docs tied to the failing path

## Acceptance criteria
- startup path resolves the expected executable deterministically
- failures emit one clear root-cause message
- worker survives long enough to show a live run

## Validation
- reproduce on Windows
- verify dashboard shows a real running issue
- inspect logs for clean startup

## Proof pack
- PR diff
- visible workpad update
- dashboard or log artifact

## Risk tier
High

## Handoff plan
Reviewer inspects the startup path, then the log proof, and routes to rework if the change widened
outside the launch surface.
```

### Small implementation change

Use when the task changes one bounded behavior with explicit validation.

```md
## Objective
Add one bounded improvement to issue pickup or worker behavior.

## Scope boundary
Allowed:
- one small implementation surface
- tests or docs needed to prove it

No-touch:
- unrelated orchestration logic
- dashboard redesign

## Source docs
- `SPEC.md`
- relevant runtime module
- the owning test or workflow surface

## Acceptance criteria
- one concrete behavior changes
- validation proves the new behavior directly
- proof is cheap for a reviewer to inspect

## Validation
- targeted test or manual check
- `git diff --check`

## Proof pack
- PR diff
- visible workpad update
- targeted validation evidence

## Risk tier
Medium

## Handoff plan
Reviewer inspects the bounded behavior diff first, then the validation evidence, and routes to
rework if unrelated runtime logic moved.
```

## Comparison Set Used For This Template

This template shape was checked against:

- `SSI-11` for repo/setup scope
- `SSI-13` for docs-only workflow guidance
- `SSI-55` for a multi-lane validation container that still needs bounded proof rules

## Before/After Normalization Example

### Before

```md
Make the issue template better for delegated work in Symphony.
```

### After

```md
## Objective
Publish a reusable delegated-work issue template for Symphony.

## Scope boundary
Allowed:
- `elixir/WORKFLOW.md`
- `elixir/docs/linear_issue_template.md`

No-touch:
- `elixir/lib/**`
- top-level product docs

## Source docs
- `SPEC.md`
- `elixir/WORKFLOW.md`
- existing SSI issue bodies in Linear

## Acceptance criteria
- template includes the required issue fields
- examples cover docs-only, repo/setup, and small implementation change
- workflow instructs agents to normalize underspecified issues against the template

## Validation
- manual review against `SSI-11`, `SSI-13`, and `SSI-55`
- confirm first-pass pickup is possible without clarifying chat

## Proof pack
- PR diff
- visible workpad update
- rendered examples in the template doc

## Risk tier
Medium

## Handoff plan
Reviewer reads the template doc first, then the workflow diff, and routes to rework if the change
widens into runtime code.
```
