<!--
Title: [<task ID>] <deliverable>, for example "[M1-T02] PathGuard". It becomes the commit title on main.
One pull request = one roadmap task, about 200 changed lines of production code (ENG-002).
-->

## Summary

<!-- What this pull request does and why, in a few sentences. -->

## Requirement IDs

<!-- The task ID and every requirement it implements or touches, for example M1-T02, SAF-007, SAF-016. -->

## How to review this

<!--
- Files to read first, in order.
- Risky areas, and why. Call out every change to Safety or Execution (ShuckExecution) explicitly.
- Anything you were unsure about, or a decision recorded in docs/decisions.md.
-->

## SwiftUI concepts used

<!--
For each SwiftUI API or pattern this change uses: a short explanation and a link to Apple's documentation.
Write "None" if the change has no UI code.
-->

## Test evidence

<!-- New or changed tests, what they prove, and the result of scripts/test.sh. Deletion paths need fixture tests. -->

## Checklist

- [ ] Tests added or updated; deletion paths use fixture tests, and SAF tests name their requirement ID
- [ ] `scripts/lint.sh`, `scripts/static-checks.sh` and `scripts/test.sh` pass locally
- [ ] No new dependencies (Apple frameworks only)
- [ ] No network APIs
- [ ] `docs/progress.md` updated, and docs updated where behavior or rules changed
- [ ] Decisions made during the task recorded in `docs/decisions.md`
