# Progress

The milestone and task checklist (PRD section 13). Each pull request ticks its task here. Milestones run in order;
M2 to M6 are broken into tasks when each one starts.

## M0 Foundations (`v0.0.1`)

Goal: repository, project skeleton, CI/CD proven end to end.

- [x] M0-T01 `LICENSE`, README skeleton, `.gitignore`, `docs/` with the PRD
- [x] M0-T02 `AGENTS.md`
- [x] M0-T03 Xcode project and app shell with sidebar placeholders
- [x] M0-T04 `ShuckKit` package skeleton, linked into the app
- [x] M0-T05 `swift-format` configuration and lint script
- [x] M0-T06 CI workflow; branch protection documented in `docs/repository-setup.md`
- [x] M0-T07 Static-check script, wired into CI
- [x] M0-T08 Release workflow, DMG and notarize scripts; secrets documented in `docs/releasing.md`
- [x] M0-T09 Pull request template, `docs/progress.md`, `docs/decisions.md`

Exit criteria:

- [x] Create `nutabi/shuck` on GitHub, push `main`, and apply `docs/repository-setup.md`.
- [x] CI green on a pull request. UI tests run on the `xcode-27` runner with ad hoc signing (D-31).
- [x] Set up the `release` environment and secrets (`docs/releasing.md`).
- [x] A `v0.0.1` tag produces a notarized draft release of the app shell (D-36, D-37).

Also ready: the local release fallback (ENG-012). The App Store Connect API key is stored on the owner's Mac as the
notarytool profile `shuck-notary`, checked against Apple's notary service on 2026-11-02. The Developer ID Application
certificate is in the owner's login keychain too, so `scripts/build-dmg.sh` can run end to end locally (not yet
exercised).

## M1 Safety core + File Cleanup (Large Files, Old Files) + Restore (`v0.1.0`)

- [ ] M1-T01 Fixture-root test harness and file factory (SAF-016)
- [ ] M1-T02 Path guard and protected locations, with the full test matrix (SAF-007, 8.4)
- [ ] M1-T03 History log writer and reader (SAF-005, HIS-001)
- [ ] M1-T04 Trash executor with re-validation and per-item outcomes (SAF-004, SAF-008, SAF-011). Adds the
  `ShuckExecutionTests` target.
- [ ] M1-T05 Restore (HIS-003, HIS-004)
- [ ] M1-T06 Sub-tool interface, registry and ownership map; File Cleanup landing page (FCL-001 to FCL-005). Replaces
  the app's placeholder `SidebarItem`.
- [ ] M1-T07 Personal-files scanner with shared item state (FCL-006, FCL-008 to FCL-011, SAF-014)
- [ ] M1-T08 Shared results UI for personal files (FCL-012)
- [ ] M1-T09 Large Files sub-tool (LRG-001 to LRG-003)
- [ ] M1-T10 "Last opened" metadata with fallback (OLD-002)
- [ ] M1-T11 Old Files sub-tool (OLD-001, OLD-003)
- [ ] M1-T12 Itemized review sheet, confirmation, summary (SAF-002, LRG-004, OLD-004)
- [ ] M1-T13 De-duplicated totals across sub-tools (FCL-007)
- [ ] M1-T14 History view and Restore action (HIS-002)
- [ ] M1-T15 UI smoke tests with the fixture root (NFR-QA-002, NFR-QA-003)
- [ ] M1-T16 Performance baseline recorded (NFR-PERF-002)

Carried over from M0:

- [ ] Turn the engine coverage report in `scripts/test.sh` into an 80% gate (SM-4, D-32) once the engine has code.
  Belongs with M1-T01 or the first task that adds engine logic.

## M2 to M6

Not broken down yet (PRD section 13).
