# Shuck — Product Requirements Document

**Shuck — housekeeping for Mac.** MVP scope, requirements and roadmap.

| Field | Value |
|---|---|
| Product | Shuck (working name during planning: "Mac Assistant") |
| Document | Product Requirements Document (PRD) |
| Version | 1.12 — ENG-002: one task is one pull request or one stack (see Revision history) |
| Date | 2026-11-11 |
| Status | Draft for owner review |
| Owner and reviewer | nutabi |
| Repository | `github.com/nutabi/shuck` (to be initialised by the owner) |
| Canonical file | `docs/PRD.md` (Markdown only; no PDF export) |
| License | GPL-3.0-or-later |

**Revision history**

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-01 | Planning baseline |
| 1.1 | 2026-11-01 | File Cleanup becomes one tool with independent sub-tools: Large Files, Old Files, Developer Junk, Caches & Logs. The `LOF` prefix is retired; its requirements moved to `FCL`, `LRG` and `OLD` (D-23). |
| 1.2 | 2026-11-01 | The tier decides review and default selection; each rule or action declares its method, and "Your data" never uses Delete. Adds the Launchctl method and the Docker review (DEV-010) (D-24). Overview reports reclaimable space for File Cleanup only; ownership is scoped to File Cleanup (D-25). Uninstall unloads matching LaunchAgents before trashing them (APP-011, D-26). |
| 1.3 | 2026-11-02 | Settings moves from the sidebar to its own window, opened with ⌘, (D-27). |
| 1.4 | 2026-11-02 | Execution is its own module, `ShuckExecution`, inside the ShuckKit package (D-28). The dependency ban covers third-party packages only (NFR-SEC-002, ENG-006, D-29). |
| 1.5 | 2026-11-10 | Review of 2026-11-10 (D-129 to D-135): synced files are listed, marked and warned about (FCL-010, FCL-012, SAF-002, OQ-06); Old Files uses the latest date it knows (OLD-002); the scan skips `.git` and other volumes (FCL-008); re-validation checks every item's modification date, and Delete needs a rule (SAF-008); the guard also refuses folders that contain a protected bundle or name (SAF-007, section 8.4); one running instance and a locked history log (SAF-018); Clear History (HIS-008, SET-007); user exclusions move to M2 (SET-001); acceptance checks name their milestone (D-133); `SMAppService` may open System Settings (STA-004, ENG-006, D-134). Brings the text in line with decisions D-43, D-62, D-65, D-66, D-70, D-75, D-111, D-115, D-119: protected locations, pull request size and template, CI, debug bundle ID, UI test wording, the history log's `detail` field, the repository layout. Adds tool-rule and Caches & Logs requirements from research (DEV-002, DEV-004, DEV-006, CAC-009, rule notes), new risks R-16 to R-18, open questions OQ-07 and OQ-08, and sources S71 to S78. |
| 1.6 | 2026-11-11 | SAF-015's threshold is 25% of the space in use on the startup volume, since measuring the home folder means walking all of it (D-144). |
| 1.7 | 2026-11-12 | SET-003 (developer project folders) is built in M2 as a minimal list with DEV-R06, not in M5 (D-154); a project's `node_modules` belongs to Developer Junk (D-152). |
| 1.8 | 2026-11-12 | Section 8.5: a `trash` intent record carries the item's `identity` too, so History can find an item whose result record was never written in the Trash (HIS-001, D-162, D-167). |
| 1.9 | 2026-11-12 | DEV-R05 and DEV-R06 name the targets as built: one item per archive bundle (D-145) and a depth limit for projects (D-153). No requirement changes (R-20, D-172). |
| 1.10 | 2026-11-12 | ENG-007 and the release channel: the release workflow publishes the release after the owner approves the `release` environment, instead of creating a draft (owner decision, D-174 supersedes D-17's draft step). |
| 1.11 | 2026-11-12 | DEV-004 names pip's settings (D-157) and records the owner's check that `brew cleanup`, `npm cache clean` and `pip cache purge` open no network connection, which settles its open question (owner decision). |
| 1.12 | 2026-11-13 | ENG-002: one task is one pull request or one stack, and an agent never has two open pull requests outside one stack (D-200). |

## How to read this document

- **Audience.** The project owner (human reviewer) and AI coding agents from any vendor.
- **Normative language.** MUST, MUST NOT, SHOULD and MAY are used as defined in RFC 2119 [S64].
- **Priorities.** Must = required for MVP exit. Should = in the MVP unless it puts the exit criteria at risk; the owner decides. Could = post-MVP candidate.
- **Requirement IDs.** Format `<AREA>-<NNN>`, for example `SAF-007` or `APP-003`. IDs are stable: never renumber or reuse an ID. To drop a requirement, mark it "Withdrawn".
- **Prefixes.** `SAF` safety. `FCL` File Cleanup tool, with sub-tools `LRG` Large Files, `OLD` Old Files, `DEV` Developer Junk and `CAC` Caches & Logs. `APP` Applications. `STA` Startup Items. `HIS` History & Restore. `OVR` Overview. `ONB` Onboarding. `SET` Settings. `NFR-*` non-functional. `ENG` engineering workflow. The `LOF` prefix from v1.0 is retired and must not be reused.
- **Tools and sub-tools.** A *tool* is a top-level entry in the sidebar. A *sub-tool* is an independent unit inside a tool, with its own scan, results, review and action (section 9.1).
- **Decisions.** `D-NN` refers to the decision log: D-01 to D-29 in Appendix A, D-30 onwards in `docs/decisions.md`. `L-NN` refers to the post-MVP backlog (section 7.2). `R-NN` refers to risks (section 14).
- **Sources.** `[S12]` refers to entry S12 in Appendix C.
- **For AI agents.** Read sections 2, 6, 8 and 12 before any task. Reference requirement IDs in every pull request. All file deletion goes through the safety layer described in section 8; no other code path may delete, move or modify user files.
- **Conflicts.** If code and this document disagree, open an issue. Do not silently diverge. The owner decides and records the outcome in `docs/decisions.md`.

## 1. Summary

Shuck is a free, open-source (GPL-3.0-or-later), native macOS app that keeps a Mac tidy. It has three tools:

- **File Cleanup**, made of independent sub-tools: **Large Files**, **Old Files**, **Developer Junk**, and **Caches & Logs**;
- **Applications**, which uninstalls apps together with the files they leave behind;
- **Startup Items**, which shows what starts automatically and lets the user turn off what they don't want.

Every action goes through a review-first safety model with an in-app restore log.

Shuck is built first for its owner's daily use and as a portfolio piece. AI coding agents implement it in small pull requests, and the owner reviews every change. The MVP targets macOS 27 on Apple Silicon, runs fully offline, needs no admin rights, and ships as a signed, notarized DMG.

## 2. Goals, non-goals and success

### 2.1 Goals

| ID | Goal |
|---|---|
| G-1 | **Daily driver.** Replace third-party housekeeping tools for the owner's needs. |
| G-2 | **Portfolio quality.** Clear architecture, tests, CI/CD and documentation that show engineering skill. |
| G-3 | **Safety.** No unintended data loss, ever. |
| G-4 | **Independence.** No third-party code dependencies, no network use, no accounts. |
| G-5 | **Learning.** The owner learns SwiftUI by reviewing pull requests that explain the SwiftUI concepts they use. |

### 2.2 Non-goals for the MVP

- Mac App Store distribution (D-04).
- Any operation that needs admin (root) rights (D-08; planned as L-01).
- Intel Macs and macOS versions earlier than 27 (D-05; macOS 26 planned as L-02).
- Network features of any kind: update checks, telemetry, analytics, crash reporting (D-18).
- Monetization, accounts, license keys (D-02).
- "Speed-up" features: memory purging, "optimization", malware scanning.
- Menu bar item, command-line tool, scheduled or background cleaning (L-09, L-10).
- Localization beyond English (L-12).
- Scanning external or network volumes (L-13).

### 2.3 Success measures

| ID | Measure | Target |
|---|---|---|
| SM-1 | Owner uses Shuck | At least weekly |
| SM-2 | Unintended deletions | Zero. An unintended deletion is any removal the owner did not intend, or any removal of an item outside the reviewed set. |
| SM-3 | Release quality | Every release: CI green, notarized, published by the owner |
| SM-4 | Engine test coverage | At least 80% line coverage of the engine package; every deletion code path covered by fixture tests |
| SM-5 | Portfolio readiness | README with screenshots, architecture overview, decision log |

### 2.4 MVP exit criteria (D-15)

The MVP is done when all three are true:

1. Every Must requirement in sections 8 to 10 is implemented and passes its acceptance check.
2. The owner has used Shuck on their own Mac for 4 consecutive weeks with zero unintended deletions.
3. A signed, notarized `v1.0.0` DMG is published through the release workflow (ENG-007).

There is no time-based deadline (D-15).

## 3. Users

### 3.1 Personas

| Persona | Description |
|---|---|
| **Owner (primary)** | Software engineer. Swift: some experience. SwiftUI: none. Uses macOS 27 on Apple Silicon. Reviews all AI-written code. |
| **Tech-literate users (secondary)** | Students and software engineers. Comfortable with files and terminals, but not necessarily with macOS internals such as `~/Library`, `launchd` or app containers. |

**Design implications**

- Explain macOS-specific concepts where they appear: what `~/Library` is, what a LaunchAgent is, what an app container is.
- Show paths and technical details on demand; never hide them.
- Prefer precise numbers and plain reasons over vague labels such as "junk".

### 3.2 Jobs to be done

| ID | Job |
|---|---|
| J-1 | When my disk is nearly full, show me what takes space and what is safe to remove. |
| J-2 | When I remove an app, remove everything it left behind. |
| J-3 | Show me what starts automatically and let me turn off what I don't want. |
| J-4 | Reclaim space from developer tooling (Xcode, `node_modules`, package caches) without breaking my projects. |
| J-5 | If I removed something by mistake, let me put it back. |

## 4. Product principles

| ID | Principle | Meaning in practice |
|---|---|---|
| P-1 | **Safety first** | Review before acting. Personal data goes to the Trash. Path guards are enforced in the engine, not the UI. |
| P-2 | **Explain, don't just list** | Every item states what it is, why it is (or isn't) safe to remove, and what happens if it is removed. |
| P-3 | **Local and private** | No network connections, no telemetry. Data never leaves the Mac. |
| P-4 | **Build, don't buy** (D-03) | Apple frameworks only. Any third-party package needs a recorded decision. Data owned by a tool (Docker, Xcode simulators, Homebrew, npm, pip) is cleaned by running that tool's own clean command, never by deleting its files. |
| P-5 | **Small, reviewable changes** | One task per pull request. Each pull request tells the reviewer where to look. |
| P-6 | **Native and accessible** | SwiftUI, Apple's Human Interface Guidelines, VoiceOver and full keyboard support. |
| P-7 | **Honest numbers** | Report allocated (on-disk) size. Distinguish estimated savings from the measured change in free space. |

## 5. Landscape and positioning

| Tool | What it covers | License or price | Status | Relevance to Shuck |
|---|---|---|---|---|
| Mole [S1] | Command-line tool: cache and log cleanup, uninstaller with leftovers, disk analyzer, build-artifact purge, dry-run mode, operations log. A separate proprietary GUI app is sold. | GPL-3.0 (command-line tool) | Active; 70k+ GitHub stars | Reference for cleanup rules. License-compatible with Shuck. |
| Pearcleaner [S2] | GUI: uninstaller, orphaned files, developer environments, Homebrew manager | Apache-2.0 with Commons Clause | "On Hold"; development largely stopped since late 2025 | Prior art only. Its code MUST NOT be copied into Shuck (license incompatible). |
| DevCleaner for Xcode [S3] | Xcode: DerivedData, Archives, device support files, simulator and device logs, documentation caches | GPL-3.0 | — | Reference for Xcode rules. License-compatible with Shuck. |
| AppCleaner [S4] | Uninstaller | Free (closed source) | — | Prior art. |
| macOS Storage settings [S5] | Clears caches and logs automatically when space is needed; storage recommendations | Built in | — | Baseline. Cache-cleaning gains can be temporary. |
| macOS Login Items & Extensions [S6] | Turns login items and background items on or off | Built in | — | Shuck links here for items it cannot manage. |

**Positioning.** Shuck does not try to out-feature Mole. It exists because the owner wants:

1. an independent tool they build and control themselves;
2. one native GUI that covers jobs J-1 to J-5;
3. a transparent safety model with review tiers, explanations and restore;
4. built-in developer cleanup.

**Reuse policy.** Write our own code by default. Code or rule data from GPL-3.0 projects (Mole, DevCleaner) MAY be reused with attribution, recorded in `docs/third-party.md`. Code from Pearcleaner MUST NOT be copied.

## 6. Platform, distribution and identity

| Topic | Decision | Ref |
|---|---|---|
| Supported OS | macOS 27 or later. macOS 27 was released on 14 Sep 2026 [S12]. | D-05 |
| Hardware | Apple Silicon (arm64) only. macOS 27 does not support Intel Macs [S12][S13]. | D-05 |
| Engine API floor | The engine package uses only APIs available in macOS 26 (deployment target 26). Adding macOS 26 support (L-02) then becomes a build-settings change. | D-06 |
| Sandbox | Not sandboxed. The Mac App Store requires the sandbox and forbids asking for root rights (App Review Guideline 2.4.5) [S7]. Both conflict with core features. | D-04 |
| Hardened Runtime | Enabled from the first commit. Notarization requires it [S8][S67]. | D-04 |
| Signing | Developer ID Application certificate (owner's paid Apple Developer Program membership) [S9]. | D-04 |
| Notarization | Apple notary service via `notarytool`; ticket stapled to the DMG [S8][S63]. | D-04 |
| Package | DMG (drag to Applications), built with Apple's `hdiutil`. No `.pkg` installer (see below). | D-19 |
| Release channel | GitHub Releases on `nutabi/shuck`. The owner approves the release environment; CI then builds and **publishes** the release. | D-17, D-174 |
| Updates | None in-app for the MVP. Users download a newer DMG and replace the app. | D-18 |
| Network | None. The MVP makes no network connections. | D-18 |
| Name | **Shuck**. Tagline: "Shuck — housekeeping for Mac". | D-21 |
| Bundle ID | `me.nutabi.shuck` | D-21 |
| Derived identifiers | Future admin helper: `me.nutabi.shuck.helper`. Logger subsystem: `me.nutabi.shuck`. Data folder: `~/Library/Application Support/me.nutabi.shuck/`. Settings domain: `me.nutabi.shuck`. Debug builds use the bundle ID `me.nutabi.shuck.debug`, with a settings domain and a data folder of that name; the Logger subsystem stays `me.nutabi.shuck` in both builds. | D-21, D-70 |
| License | GPL-3.0-or-later. The repository `LICENSE` file contains the full GPL-3.0 text [S37]. | D-20 |
| Legal notices | Copyright holder: Nguyen Thai Binh. The About window shows copyright, the no-warranty statement, the license and a link to the source (GPL-3.0 section 5(d) [S37]). README and About include: "Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions." [S35] | D-20 |

**Why a DMG and not a `.pkg` (D-19)**

- A `.pkg` does install over an existing copy, but updating is still manual, exactly as with a DMG.
- By default, macOS Installer may "relocate" an update to any copy of the app with the same bundle ID. On a developer's Mac that can be the Xcode build output. This is preventable (`BundleIsRelocatable = false`), but it is a trap [S32][S33].
- A `.pkg` needs a separate Developer ID Installer certificate and usually an admin password [S8].
- Shuck installs nothing outside its app bundle. The future admin helper registers from inside the bundle via `SMAppService` [S16].

**Why not "Mac Assistant" (D-21).** Apple allows "Mac" in a product name only when "used in combination with another non-generic or non-geographically-descriptive word" [S34]. "Assistant" is generic. A distinct name plus "for Mac" is the compliant pattern [S34].

## 7. MVP scope

### 7.1 In scope

| Area | ID prefix | Summary | Milestone |
|---|---|---|---|
| Safety core | SAF | Scan → plan → review → act → log, path guards, protected locations, one running instance | M1 (Trash), M2 (permanent delete, tool commands) |
| **File Cleanup** (tool) | FCL | One tool holding independent file sub-tools; landing page; shared personal-files scan; ownership and de-duplication rules | M1 |
| ↳ Large Files (sub-tool) | LRG | Personal files above a size threshold; move them to the Trash | M1 |
| ↳ Old Files (sub-tool) | OLD | Personal files not opened for months; move them to the Trash | M1 |
| ↳ Developer Junk (sub-tool) | DEV | Rule-based cleanup of developer tooling data | M2 |
| ↳ Caches & Logs (sub-tool) | CAC | User-level caches and logs | M2 |
| **Applications** (tool) | APP | Uninstall apps with their user-level leftovers | M3 |
| **Startup Items** (tool) | STA | List all launchd items; manage per-user LaunchAgents | M4 |
| History & Restore | HIS | Log of every action; restore trashed items in the app | M1 |
| Overview | OVR | Scan everything; show reclaimable space per File Cleanup sub-tool, and counts for Applications and Startup Items | M5 |
| Onboarding & Permissions | ONB | First launch, Full Disk Access guidance, limited-access handling | M5 |
| Settings | SET | Exclusions, thresholds, project folders, Clear History, About and legal notices | M2 (SET-001 exclusions: engine and a minimal list, D-135; SET-003 project folders: a minimal list with DEV-R06, D-154), M5 (the rest) |

### 7.2 Post-MVP backlog (proposed order; the owner may reorder)

| ID | Item | Notes |
|---|---|---|
| L-01 | **Privileged helper** for admin operations | Removes `/Library` leftovers, LaunchDaemons and system-wide agents, `/Library/Caches`, root-owned apps. Design constraints: launchd daemon registered with `SMAppService` [S16]; app-to-helper calls over XPC with the caller's code signature checked (`setCodeSigningRequirement`) [S66]; a standard macOS authentication prompt before each destructive action; a narrow command set (for example "move these paths to Trash", limited to approved roots); no GUI code in the helper [S18]. Apple DTS warns: "Your daemon can perform an operation, but how does it know whether it should?" [S18] |
| L-02 | macOS 26 support | Test in a macOS 26 virtual machine on Apple Silicon [S15]. |
| L-03 | "Check for Updates" button | Manual check against the GitHub Releases API, which allows 60 unauthenticated requests per hour [S30]. Opens the release page; no self-updater. |
| L-04 | Homebrew manager | New top-level tool. List, install and uninstall packages. Runs `brew` as the user, never as root [S20]. |
| L-05 | Leftovers from deleted apps | Part of the Applications tool; uses its confidence model. Higher false-positive risk. |
| L-06 | Unused apps | Part of the Applications tool. Apps not opened in N days. |
| L-07 | Disk usage map | New File Cleanup sub-tool. Visual map of what fills the disk. |
| L-08 | Duplicate finder | New File Cleanup sub-tool. Detects duplicate files by comparing content. |
| L-09 | Scheduled scans and menu bar item | Zero-click cleaning allowed for the rebuildable tier only. |
| L-10 | Command-line tool | A thin layer over the engine package. |
| L-11 | Homebrew cask distribution | Optional extra install channel. |
| L-12 | Localization | Strings are already in String Catalogs (NFR-L10N-001). |
| L-13 | External volumes | Scanning drives other than the startup volume. |

### 7.3 Out of scope

- Mac App Store version (D-04).
- Cleaning inside `/System` or any location protected by System Integrity Protection.
- Memory purging, "optimization" or malware features.
- A self-updating mechanism. Sparkle [S31] is third-party, which conflicts with D-03.

## 8. Safety model (SAF)

### 8.1 Concepts

| Term | Definition |
|---|---|
| Tool | A top-level feature in the sidebar: File Cleanup, Applications, Startup Items. |
| Sub-tool | An independent unit inside a tool, with its own scan, results, review and action. File Cleanup's sub-tools are Large Files, Old Files, Developer Junk, and Caches & Logs. |
| Item | One file, folder, bundle, launchd job or tool-cleanup target found by a scan. |
| Tier | **Rebuildable** or **Your data** (section 8.2). Decides the review style, the default selection and which methods are allowed (SAF-004). |
| Method | **Trash** (restorable), **Delete** (permanent), **Tool** (runs the owning tool's documented clean command; not restorable) or **Launchctl** (unloads, disables or enables a user's launchd job; reversed by the opposite action). Each rule or action declares its method. |
| Plan | The exact list of operations shown at review time. The executor performs exactly this list. |
| Run | One execution of a plan. It has a run ID and per-item outcomes. |

### 8.2 Tiers

| Tier | Contains | Review | Allowed methods | Selected by default |
|---|---|---|---|---|
| **Rebuildable** | Caches & Logs; Developer Junk (all rules except DEV-R05 and DEV-R10) | One summary confirmation per run showing categories and the total. The item list is available on demand. | Delete or Tool | Only items a rule marks safe, for example stale for 30+ days |
| **Your data** | Large Files, Old Files, Applications, Startup Items; Developer Junk rules DEV-R05 (Xcode Archives) and DEV-R10 (Docker) | Full item list with explicit confirmation | Trash (restorable); Tool for tool-owned data (DEV-R10); Launchctl for user agents (STA-005, APP-011). Never Delete. | Personal files: never. App leftovers: exact bundle-ID matches outside Application Support, Containers and Group Containers. |

The tier belongs to each sub-tool or rule, not to the tool. File Cleanup contains both tiers, and a run never mixes sub-tools (FCL-002).

The tier sets how an action is reviewed and what is selected by default. The method comes from the rule or action, within the tier's allowed methods (SAF-004, D-24).

Rationale: Apple defines caches as data that "can be regenerated as needed. Apps should never rely on the existence of cache files" [S22]. Mole uses the same split between Trash and permanent deletion [S1]. Decisions: D-09, D-10, D-11, D-24.

### 8.3 Requirements

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| SAF-001 | Every scan item MUST carry: tier, method, allocated size, reason text, source tool or sub-tool, and (where relevant) confidence level. | Must | Unit test: the item model cannot be constructed without these fields. |
| SAF-002 | "Your data" actions MUST show an itemized review and an explicit confirmation stating item count and total size. A Tool action counts as one item; its row shows the exact command, what it removes and the tool's size estimate. Tool output is shown for information only and never used to choose targets (R-07). The review of a synced item (FCL-010) says that moving it to the Trash removes it from the user's other devices (D-129). | Must | UI test: confirm stays disabled until the review is shown; the dialog shows count and size; a Tool item shows its command; a synced item shows the warning. |
| SAF-003 | "Rebuildable" actions MUST show one summary confirmation with per-category totals. The full item list MUST be reachable from that confirmation, and it shows each item's full path, because rows such as two DerivedData folders of one project name look alike without it. | Must | UI test. |
| SAF-004 | The tier decides the review style (SAF-002, SAF-003) and the default selection. Each rule or action declares its method within its tier's limits: "Rebuildable" uses Delete or Tool; "Your data" uses Trash (via `FileManager.trashItem` or `NSWorkspace.recycle`) [S42], Tool for tool-owned data (SAF-010) or Launchctl for user agents (STA-005, APP-011), and MUST NOT use Delete. A "Your data" action that cannot be undone MUST say so in its confirmation and is logged as non-restorable (SAF-006). | Must | Unit test: the planner rejects Delete for a "Your data" item and accepts each allowed tier–method pair. UI test: a non-restorable "Your data" confirmation shows the warning. |
| SAF-005 | Every Trash operation MUST be recorded in the history log with the original path and the trashed path returned by the system (`resultingItemURL`) [S42]. | Must | Fixture test: log entries match the actual trashed locations. |
| SAF-006 | Permanent deletions, tool runs and launchctl changes MUST also be logged (path, job label or command, size estimate, outcome). Deletions and tool runs are marked non-restorable. A launchctl change is reversed by the opposite action (STA-005), not by Restore. | Must | Fixture test. |
| SAF-007 | A **path guard** in the engine MUST reject any target that: (a) is empty, `/`, or the home folder itself; (b) is not absolute or contains `..` after normalization; (c) after resolving symlinks, is not strictly inside an allowed root for its tool or sub-tool; (d) lies inside a protected location (section 8.4), or contains one: a fixed protected location, or a protected bundle or name among its direct children (D-43, D-135); (e) is on a volume other than the startup volume (MVP), or is a Trash target that is itself a mount point (D-135). Deletion MUST NOT follow symlinks out of the target. | Must | Fixture tests for each case, including a symlink pointing outside the root and an empty-variable path (the Steam bug pattern [S23]). |
| SAF-008 | Every run MUST re-validate each item just before acting: it still exists, its type is unchanged, and its size is within tolerance. Changed items are skipped and reported. Every item, Trash or Delete, whose modification date differs from the one read at the scan is skipped, even when type and size still match; for an item whose scope is its contents, the date compared is the same deep date the scan used for staleness (D-105, D-132). Rule-backed Delete items must still match their cleanup rule, and a plan refuses a Delete item that has no rule match (D-132). | Must | Fixture test: modify an item between plan and run → skipped with reason; a Trash item or a rule-backed Delete target with only a changed modification date is skipped; a plan with a Delete item that has no rule is refused. |
| SAF-009 | Files belonging to a running app MUST NOT be acted on. Uninstall requires the app to quit first; caches of running apps are skipped. | Must | Fixture test with a stubbed running-app list. |
| SAF-010 | Data owned by a tool MUST be cleaned only through that tool's documented command (section 9.1.3). If the tool is missing, its rule is hidden. | Must | Unit test: tool rules never produce Delete operations. |
| SAF-011 | Every run MUST end with a per-item outcome (succeeded, skipped or failed, with reason). There are no silent failures. | Must | Fixture test with mixed outcomes. |
| SAF-012 | Permission errors (macOS privacy protection, TCC) MUST be reported as "Not accessible" with guidance (ONB-002). They MUST NOT trigger any privilege escalation. | Must | Fixture test using an unreadable folder. |
| SAF-013 | Sizes MUST be allocated sizes (`totalFileAllocatedSizeKey`) [S44]. After a run, the app SHOULD show the measured change in free space next to the estimate and explain gaps: Trash not yet emptied (items in the Trash free nothing until it is emptied), local Time Machine snapshots and APFS clones (they keep blocks alive, so the measured change can be far below the estimate), purgeable space. | Must (size) / Should (comparison) | Unit test for size calculation; manual check for the comparison. |
| SAF-014 | Scans and runs MUST be cancellable. Cancelling a run stops before the next item, and the log reflects the true state. | Must | Fixture test: cancel midway → the log matches the disk. |
| SAF-015 | A single Rebuildable target larger than a sanity threshold (default: 25% of the space in use on the startup volume, D-144) SHOULD require a second confirmation. | Should | Fixture test. |
| SAF-016 | Tests MUST NOT touch the real home folder. A test harness creates a temporary fixture root and asserts that every path used is inside it. | Must | The harness fails any test that resolves a path outside the fixture root. |
| SAF-017 | No code outside the engine's execution layer (the `ShuckExecution` module, D-28) may delete, move, rename or modify user files or launchd state. | Must | CI static check (ENG-006) for file-mutation APIs outside the allowed module. |
| SAF-018 | Only one instance of a build runs. A second launch of the same build activates the first and quits. While a run writes the history log, the log is also locked (`flock`), so two processes never interleave records (D-135). | Must | Unit test: a second lock on the log is refused while the first is held; manual check of a second launch. |

### 8.4 Protected locations (default list)

Shuck MUST NOT act on these, even if the user selects them. Scans skip or show them read-only.

| Location | Reason |
|---|---|
| `/System`, `/usr`, `/bin`, `/sbin`, `/private`, `/Library` (MVP), `/opt` | System or admin-owned. `/opt/homebrew` is touched only through `brew`. |
| `~/Library/Mobile Documents` (iCloud Drive) and `~/Library/CloudStorage` (other sync providers) | Synced storage |
| Photos, Music and TV libraries (as whole bundles, matched by extension wherever they are: `photoslibrary`, `photolibrary`, `musiclibrary`, `tvlibrary`; Music and TV libraries also in their default folders) | Managed by their apps (D-43) |
| `~/Library/Mail`, `~/Library/Messages`, `~/Library/Keychains` | Personal data and credentials |
| `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.azure`, `~/.docker`, `~/.netrc`, `~/.password-store`, `~/.config/gcloud` | Developer credentials (D-43) |
| Time Machine backups and local snapshots, including `Backups.backupdb` and `backupbundle` bundles | Backups (D-43) |
| `~/Library/Developer/CoreSimulator/Devices` and `Volumes`, `~/Library/Containers/com.docker.docker`, `~/Library/Group Containers/group.com.docker` | Stores a tool manages (DEV-007, SAF-010, D-119) |
| Shuck's own app bundle and the data folders of both builds (`me.nutabi.shuck` and `me.nutabi.shuck.debug`) | Self-protection (D-70) |
| Any path the user adds in Settings (SET-001) | User choice |

Protecting a folder also refuses its parents: a target that contains a protected location is rejected (D-43). The same holds for a folder that has a protected bundle or name among its direct children (D-135).

### 8.5 History log format

- **File:** `~/Library/Application Support/me.nutabi.shuck/history.jsonl`, in JSON Lines format (one JSON object per line) [S59].
- **Writing:** append-only; one "intent" record before each operation and one "result" record after it. The log is locked (`flock`) while a run writes it (SAF-018).
- **Permissions:** readable only by the user. File mode 0600; folder mode 0700.

| Field | Type | Notes |
|---|---|---|
| `v` | integer | Schema version, starts at 1 |
| `ts` | string | ISO 8601 timestamp, UTC |
| `run` | string | Run ID (UUID) |
| `tool` | string | Sub-tool or tool ID: `LRG`, `OLD`, `DEV`, `CAC`, `APP`, `STA`, `HIS` |
| `phase` | string | `intent` or `result` |
| `op` | string | `trash`, `delete`, `tool`, `launchctl`, `restore` |
| `path` | string | Original path; for `tool`, the quoted command (D-106, D-115) |
| `trashedPath` | string, optional | From `resultingItemURL` [S42] |
| `identity` | object, optional | Intent and result records of `trash`: the item's file identity, `{"volume": st_dev, "file": st_ino}`, read just before the record is written. Restore moves only an item whose file number still matches. History finds an item whose intent has no result, after a quit or crash, among the Trash's direct entries by this identity (HIS-001, D-167). Logs written by 0.1.0 do not have it, and intent records have it since 0.2.0 (D-84). |
| `bytes` | integer, optional | Allocated size estimate |
| `tier` | string | `rebuildable` or `yourData` |
| `status` | string, result only | `ok`, `skipped`, `failed` |
| `detail` | string, optional | A skip's reason code, alone or followed by a colon and what was found, such as `changed: file, 4096 bytes`; a failure as `<domain> <code>: <message>` (D-88). A tool run: `exit 0` or `exit 0; output: <text>`; a failure is the error, then `; output: <text>`. The output is kept to its last 2048 bytes and marked `…` when cut (D-115). |

## 9. Feature requirements

**Navigation.** The sidebar lists: Overview · **File Cleanup** (Large Files, Old Files, Developer Junk, Caches & Logs) · **Applications** · **Startup Items** · History. Settings opens in its own window from the app menu (⌘,), as is standard on macOS (D-27).

Every tool and sub-tool follows the same flow: **Scan → Results → Select → Review → Act → Summary.** The summary shows the space freed and links to History.

### 9.1 File Cleanup (FCL)

**Purpose.** One tool for reclaiming space from files (J-1, J-4). It holds independent sub-tools, and each one answers a single question: "What is big?", "What haven't I opened?", "What can developer tools rebuild?", "Which caches and logs can go?"

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| FCL-001 | File Cleanup is one sidebar entry. Its MVP sub-tools are Large Files, Old Files, Developer Junk, and Caches & Logs. | Must | UI test: the sidebar shows File Cleanup with its four sub-tools. |
| FCL-002 | Sub-tools are independent. Each has its own scan, results, selection, review and action. Scanning, running or failing one never blocks or changes another. No action spans several sub-tools. | Must | Integration test: a failure injected in one sub-tool leaves another sub-tool's scan and run unaffected. |
| FCL-003 | Each sub-tool is an engine unit behind one common interface (ID, name, description, tier rules, a scan that produces items) and is listed in a sub-tool registry. Adding a sub-tool requires no change to other sub-tools or to the safety layer. | Must | Unit test: a test-only sub-tool registers and runs through the full safety pipeline. |
| FCL-004 | The File Cleanup landing page lists each sub-tool with a one-line description, last scan time, reclaimable estimate and its own Scan button. A "Scan all" button MAY start every sub-tool's scan; it never acts. | Must | UI test. |
| FCL-005 | **Ownership:** every location belongs to exactly one sub-tool. For example, Homebrew's cache belongs to Developer Junk, not Caches & Logs. The only exception is FCL-006. Ownership covers File Cleanup only. Other tools may act on the same locations; for example, an uninstall trashes an app's whole container, including caches that Caches & Logs lists. Such overlaps are never summed (OVR-001), and an item another tool has already removed is skipped at run time (SAF-008) (D-25). | Must | Unit test: the ownership map has no overlaps other than the personal-files pair. |
| FCL-006 | Large Files and Old Files share one personal-files scan and its item state. A file can appear in both; once it is trashed in one, it disappears from the other. | Must | Integration test. |
| FCL-007 | Totals that combine sub-tools (landing page, Overview) count each file once, de-duplicated by file identity. | Must | Unit test with a file that is both large and old. |
| FCL-008 | **Personal-files scope** (used by Large Files and Old Files): the user's home folder on the startup volume; the scan does not enter another volume (D-135). Git's own files are not personal files: the scan does not enter a folder named `.git`, at any depth, and does not list a `.git` file; other hidden folders below the top level stay in scope (D-131). Excluded: `~/Library` (apps manage it; see Applications and Caches & Logs) except an allowlist of user-data locations (initially iPhone and iPad device backups); hidden top-level folders (tool data; see Developer Junk); app bundles (see Applications); protected locations; user exclusions. | Must | Fixture tree with files in each excluded area, including a `.git` folder with a large packfile → none appear in results. |
| FCL-009 | Packages (folders macOS presents as one file, detected with `isPackageKey`) are shown as single items with their total allocated size. | Must | Fixture package → one item with summed size. |
| FCL-010 | iCloud placeholders that are not downloaded locally are excluded, whether they are files, packages or folders (`ubiquitousItemDownloadingStatusKey`) [S45]. A downloaded file that a sync service keeps elsewhere in the home folder, such as `~/Desktop` and `~/Documents` under iCloud's Desktop & Documents, is still listed. The scan records that it is synced (`isUbiquitousItemKey`) and the results mark it "Synced" (FCL-012). iCloud Drive's own folders stay fully protected (section 8.4) (D-129). | Must | Unit test with stubbed resource values, including a placeholder folder and a downloaded synced file. |
| FCL-011 | Data stores owned by a tool that can occur inside the personal files (for example the Go module cache, `~/go/pkg/mod`) are shown read-only, with a pointer to the sub-tool that manages them. Stores in `~/Library` or hidden folders, such as Docker's disk image and Xcode simulator data, lie outside the scope (FCL-008) and are refused by the guard (section 8.4) (D-135). | Must | Fixture test. |
| FCL-012 | Large Files and Old Files results stream in as the scan progresses, can be sorted by size, date, name and kind, and show the total of the selection. Each item shows name, path, kind, size and date, and a "Synced" mark with text (not color alone) when a sync service keeps it (D-129). Space opens a Quick Look preview; "Show in Finder" reveals the file. | Must | UI test with a fixture root. |
| FCL-013 | Known file types get a short explanation, for example disk images and installers in Downloads, or device backups. | Should | Unit test on the classifier. |

#### 9.1.1 Large Files (LRG)

**Question it answers:** "What is taking the most space?"

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| LRG-001 | Lists personal files (FCL-008) whose allocated size is at least the threshold (default 500 MB, configurable), regardless of age. | Must | Fixture test around the threshold. |
| LRG-002 | Sorted by size, largest first, by default. | Must | UI test. |
| LRG-003 | Group results by top-level folder (Downloads, Movies, and so on) with subtotals. | Should | UI test. |
| LRG-004 | Nothing is selected by default (D-10). The action is "Move to Trash" through the safety pipeline (Your data tier), logged for restore. | Must | Fixture test end to end. |

#### 9.1.2 Old Files (OLD)

**Question it answers:** "What haven't I opened in a long time?"

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| OLD-001 | Lists personal files (FCL-008) not opened for at least the chosen period (default 12 months; presets 3, 6, 12 and 24 months; custom value) and at least a minimum size (default 50 MB; can be set to 0), so the list stays focused on space. | Must | Fixture test with stubbed dates. |
| OLD-002 | A file's "last opened" date is the latest of Spotlight's `kMDItemLastUsedDate`, which Launch Services updates whenever a file is opened [S43], its content-modification date, and the date it was added to its folder (`addedToDirectoryDateKey`). A missing date is ignored. The reason names the date that decided: "Not opened", "Not modified" or "Added". For a package or a folder listed as one item, the modification date is the newest among the item and its direct children. No single date proves a file is unused, so the newest one counts (D-130; supersedes the earlier order). | Must | Unit test with a stubbed metadata provider: each date can decide; the reason names it. |
| OLD-003 | Sorted by the last-opened date of OLD-002, oldest first, by default. | Must | UI test. |
| OLD-004 | Nothing is selected by default (D-10). The action is "Move to Trash" through the safety pipeline (Your data tier), logged for restore. | Must | Fixture test end to end. |

#### 9.1.3 Developer Junk (DEV)

**Purpose.** Reclaim space from developer tooling without breaking projects (J-4).

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| DEV-001 | Cleanup rules are data, defined in the engine. Each rule has: ID, name, description, detection (tool path or folder exists), targets (paths inside allowed roots) or tool command, tier, staleness rule, explanation, documentation link. Adding a rule is one small pull request with fixture tests. | Must | Unit test: rules load and validate. |
| DEV-002 | Only rules whose tool or data exists on this Mac are shown. For a tool, "the path exists" is not always enough: `/usr/bin/xcrun` exists on a Mac without Xcode and can raise the "install command line developer tools" prompt, so simctl needs another test; and npm or pip installed through nvm, asdf, mise, fnm, volta or pyenv is not on a minimal explicit `PATH`. How each tool is found is decided in M2-T11. | Must | Unit test with stubbed detection. |
| DEV-003 | Each rule shows a size estimate before acting: the folder's allocated size, or the size the tool reports where available. Homebrew's item (DEV-R09) shows no size before the run, since `brew cleanup` also removes old versions outside the download cache, and the run measures what it removed and shows that after it (D-194). | Must | Fixture test. |
| DEV-004 | Tool commands run as the current user through `posix_spawn`, in a process group of their own (`POSIX_SPAWN_SETPGROUP`) that Stop and the timeout signal as a whole (D-191), with an absolute executable path and an argument array (no shell), an explicit `PATH`, and a timeout (default 10 minutes). Output and exit code go to the history log. A tool command must not reach the network (NFR-SEC-001): every `brew` command sets `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ANALYTICS=1` [S54], `npm` sets `NPM_CONFIG_UPDATE_NOTIFIER=false` and `NPM_CONFIG_OFFLINE=true` [S71], and `pip` sets `PIP_DISABLE_PIP_VERSION_CHECK=1` and `PIP_NO_INPUT=1` (D-157). Their documentation does not say whether `brew cleanup`, `npm cache clean` and `pip cache purge` use the network; the owner checked on their Mac on 2026-11-12 that, run from Developer Junk, they open no network connection. | Must | Unit test with a fake tool executable that prints its environment. |
| DEV-005 | Staleness default: 30 days since last modification (configurable, SET-002). Stale items are selected; others are listed but not selected. | Must | Fixture test with dated folders. |
| DEV-006 | `node_modules` scanning is limited to the project folders configured in Settings (SET-003), with a depth limit. It never descends into `node_modules` itself, and takes only the top-most `node_modules` of a project. A `node_modules` is listed only with a lockfile next to it. A project is stale by the newest file among the project's own files (not `node_modules`, and not the folder's date). The item warns when the project uses `patch-package` or `file:` links, whose changes a reinstall does not restore. | Must | Fixture test: nested `node_modules`, a missing lockfile, a recently edited source file, a `file:` link. |
| DEV-007 | Stores managed by a tool are never deleted directly: Docker's disk image, simulator device data, the Homebrew Cellar. | Must | Unit test: these paths are rejected by the guard. |
| DEV-008 | DerivedData is broken down per project, and folders whose project no longer exists are flagged. | Should | Fixture test. |
| DEV-009 | Implement the rules marked Must in the table below. | Must | One fixture or recorded-output test per rule. |
| DEV-010 | DEV-R10 review (SAF-002) is one item. It shows the command `docker system prune --force`; what it removes (stopped containers, networks not used by any container, dangling images, unused build cache) [S51]; the reclaimable size from `docker system df` without volumes, labelled as an upper bound; and "cannot be undone". Individual containers and images are not listed. | Should | Unit test with recorded `docker system df` output; UI test of the review row. |

**Rule set**

| Rule | Target | Method | Tier | Selected by default | Priority | Source |
|---|---|---|---|---|---|---|
| DEV-R01 Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | Delete | Rebuildable | Stale 30+ days, or project missing | Must | [S3] |
| DEV-R02 Device support files | `~/Library/Developer/Xcode/*DeviceSupport/*` | Delete | Rebuildable | All except the newest version per platform | Must | [S3] |
| DEV-R03 Unavailable simulators | `xcrun simctl delete unavailable` | Tool | Rebuildable | Yes | Must | `xcrun simctl help delete` |
| DEV-R04 CoreSimulator caches | `~/Library/Developer/CoreSimulator/Caches/*` | Delete | Rebuildable | Yes | Must | — |
| DEV-R05 Xcode Archives | `~/Library/Developer/Xcode/Archives/*/*.xcarchive`, one item per archive (D-145) | Trash | Your data | Never. Apple: "You must retain the Xcode archive for each build of your app you distribute." | Must | [S50] |
| DEV-R06 Stale `node_modules` | `<project folders>/**/node_modules`, in a project at most 4 levels below a project folder (D-153) | Delete | Rebuildable | Project stale 30+ days (DEV-006) | Must | — |
| DEV-R07 npm cache | `npm cache clean --force` | Tool | Rebuildable | Yes | Must | [S53] |
| DEV-R08 pip cache | `pip cache purge` | Tool | Rebuildable | Yes | Must | [S52] |
| DEV-R09 Homebrew | `brew cleanup` | Tool | Rebuildable | Yes | Must | [S54] |
| DEV-R10 Docker | `docker system prune --force` (`--force` skips Docker's own prompt; Shuck's review (DEV-010) replaces it. Never `--volumes` or `-a`; volumes are not removed by default "to prevent important data from being deleted") | Tool | Your data | Never | Should | [S51] |
| DEV-R11 SwiftPM cache | `swift package purge-cache` | Tool | Rebuildable | Yes | Should | [S70] |
| DEV-R12 CocoaPods cache | `pod cache clean --all` | Tool | Rebuildable | Yes | Should | [S55] |
| DEV-R13 Yarn / pnpm | `yarn cache clean` / `pnpm store prune` | Tool | Rebuildable | Yes | Could | — |
| DEV-R14 Go module cache | `go clean -modcache` | Tool | Rebuildable | No | Could | [S56] |
| DEV-R15 Gradle caches | `~/.gradle/caches` | Delete | Rebuildable | No | Could | — |
| DEV-R16 Cargo registry cache | `~/.cargo/registry/cache` | Delete | Rebuildable | No | Could | — |

**Rule notes.** What a rule's explanation and checks must say, from the review of 2026-11-10:

- **DEV-R01.** Deleting DerivedData also removes `SourcePackages` (Swift package checkouts), which need the network to restore, and Xcode's compilation cache. The explanation says so.
- **DEV-R03.** `xcrun simctl delete unavailable` is the only supported way to remove simulator devices. `simctl runtime delete` is reported to be undone at restart [S73], so Shuck does not offer it.
- **DEV-R04.** DevCleaner's maintainer reports that `~/Library/Developer/CoreSimulator/Caches` is gone on recent Xcode versions and advises against cleaning these caches [S77]. To verify on the owner's Mac (`docs/progress.md`, M2-T08).
- **DEV-R06.** Shuck has no network (P-3), so the explanation says that restoring `node_modules` needs `npm install` and a connection.
- **DEV-R10.** Never `--volumes` or `-a`. To decide in M5: prefer `docker builder prune` [S72] to `docker system prune`. Docker's disk image on the host does not shrink when space is freed inside it, so the measured change in free space can be zero (SAF-013).

#### 9.1.4 Caches & Logs (CAC)

**Purpose.** Clear user-level caches and old logs (J-1).

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| CAC-001 | Scope: entries in `~/Library/Caches`, entries in `~/Library/Logs`, and sandboxed apps' caches at `~/Library/Containers/*/Data/Library/Caches` (needs Full Disk Access). Excluded: caches owned by Developer Junk rules (FCL-005), for example Homebrew and SwiftPM; Shuck's own caches; protected locations. | Must | Fixture tree → expected entries. |
| CAC-002 | Group entries by owning app. Folders named after a bundle ID are resolved to the app name; unknown folders keep their folder name. | Must | Unit test. |
| CAC-003 | Caches of running apps are unselected and disabled, with the note "app is running". | Must | Fixture test with stubbed running apps. |
| CAC-004 | Delete the contents of each selected cache or log folder, but keep the folder itself. Deleting `~/Library/Logs/DiagnosticReports` itself stopped crash reports from being written [S74]. | Must | Fixture test. |
| CAC-005 | Logs: log files not modified for 7+ days (configurable) are selected; newer logs are listed but not selected. | Must | Fixture test with dated files. |
| CAC-006 | Rebuildable tier: one summary confirmation (SAF-003). | Must | UI test. |
| CAC-007 | The screen states that macOS also "clears caches and logs that are safe to delete" when space is needed, so gains may be temporary [S5]. | Must | Review. |
| CAC-008 | `/Library/Caches`, `/Library/Logs` and `/private/var` need admin rights and are out of the MVP (L-01). | Must | Guard rejects these paths. |
| CAC-009 | A folder is never classified as a cache by its name alone: another tool's cleanup deleted Claude Code's memory folders that way [S76]. An entry whose owning app Shuck cannot resolve (CAC-002) is listed but not selected, because some apps keep state in Caches (for example offline data; anecdotal). Caches of a running app are skipped (CAC-003) [S75]. | Must | Fixture test: an unknown folder is listed and unselected; a folder named `cache` outside the scope (CAC-001) is not listed. |

### 9.2 Applications — uninstaller (APP)

**Purpose.** Remove an app and everything it left in the user's Library (J-2).

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| APP-001 | List apps in `/Applications` and `~/Applications` (including one level of subfolders): icon, name, version, bundle ID, size, last opened. Exclude apps that are part of macOS (in `/System/Applications`, or not removable because of System Integrity Protection) and Shuck itself. | Must | Fixture app folder → expected list. |
| APP-002 | For a selected app, find related user-level items by exact bundle ID in: `~/Library/Application Support`, `Caches`, `Containers`, `Group Containers` (matched through the app's declared app groups), `Preferences` (including `ByHost`), `Saved Application State`, `HTTPStorages`, `WebKit`, `Cookies`, `Logs`, `Application Scripts`, and `LaunchAgents` (plist label or program path inside the app bundle). | Must | Fixture Library tree → expected matches. |
| APP-003 | Every related item gets a confidence level. **High:** exact bundle ID or declared app group. **Medium:** app or vendor name match in Application Support, Caches or Logs. **Low:** other heuristics. Only High items are selected by default, except those in Application Support, Containers and Group Containers (OQ-07). Medium and Low items show the reason for the match. | Must | Unit tests per level. |
| APP-004 | Related items found in system-wide locations (`/Library/Application Support`, `LaunchAgents`, `LaunchDaemons`, `PrivilegedHelperTools`, `Preferences`) are listed as "Needs admin — not removable in this version", with "Show in Finder" (D-08). | Must | Fixture test. |
| APP-005 | If the user cannot remove the app bundle itself (for example a root-owned app installed by a package, or because macOS's App Management permission is missing, R-16), the uninstall is blocked with the reason shown. Leftovers are not removed on their own. | Must | Fixture test with a non-writable bundle. |
| APP-006 | If the app is running, offer "Quit <App>" using a normal quit request (`NSRunningApplication.terminate()`). Continue only after the app has exited. Never force-quit. | Must | Integration test with a stubbed running-app list. |
| APP-007 | Uninstall moves the app bundle and the selected items to the Trash in one run, after an itemized review; matching LaunchAgents are unloaded first (APP-011). Restore puts everything back. | Must | Fixture test end to end, including restore. |
| APP-008 | Apps installed by a package show their receipt (from `pkgutil`) and a note that system-wide files may exist. | Should | Unit test with recorded `pkgutil` output. |
| APP-009 | Apps can be sorted by size, last opened and name, and searched. | Should | UI test. |
| APP-010 | Show the app's code-signing developer name. | Could | — |
| APP-011 | Before trashing a matching plist from `~/Library/LaunchAgents` (APP-002), the uninstall unloads the agent with `launchctl bootout` in the `gui/<uid>` domain, through the same execution path as STA-005 Remove. An agent that is not loaded is trashed directly. If unloading a loaded agent fails, its plist is skipped and reported (SAF-011). Restoring puts the plist back; the agent is re-enabled only if the user confirms (HIS-005). | Must | Integration test on a fixture agent in a test domain: the agent is unloaded before its plist is trashed. |

### 9.3 Startup Items (STA)

**Purpose.** Show what starts automatically and let the user manage what they own (J-3).

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| STA-001 | List launchd property lists in `~/Library/LaunchAgents` (this user), `/Library/LaunchAgents` (all users) and `/Library/LaunchDaemons` (system). For each: label, program and arguments, run conditions (`RunAtLoad`, `KeepAlive`, intervals), owning app (resolved from the program path or label), scope. | Must | Fixture plists → expected rows. |
| STA-002 | Show status for each job. User agents: loaded and enabled state in the `gui/<uid>` domain (`launchctl print`, `launchctl print-disabled`). The system domain is queried read-only; anyone may read it, but changes need root [S47]. | Must | Unit test with recorded `launchctl` output. |
| STA-003 | List helpers bundled inside installed apps (`Contents/Library/LaunchAgents`, `LaunchDaemons`, `LoginItems`) as "Managed by macOS Login Items & Extensions" (read-only). `SMAppService` manages only an app's own helpers [S16]. | Must | Fixture app bundle → listed read-only. |
| STA-004 | "Open at Login" apps cannot be listed through a supported API. Show an explanation and an "Open Login Items settings" button that calls `SMAppService.openSystemSettingsLoginItems()` [S48][S17]. The static check allows this one call in the app target, because it only opens a pane; every other use of `SMAppService` stays an error outside `ShuckExecution` (D-134). | Must | UI test: the button is present; manual check that it opens the right pane. |
| STA-005 | For user agents in `~/Library/LaunchAgents` only: **Disable** (`launchctl bootout` + `launchctl disable`; the disabled state persists across reboots [S47]), **Enable** (`enable` + `bootstrap`), **Remove** (`bootout`, then move the plist to the Trash; restorable). Itemized review (Your data tier). | Must | Integration test on a fixture agent in a test domain; manual check on the owner's Mac. |
| STA-006 | Items in `/Library/*` and the system domain are read-only, marked "Needs admin", with "Show in Finder" (D-08). | Must | UI test. |
| STA-007 | Flag jobs whose program path does not exist ("program missing"). These are likely leftovers from removed apps. | Must | Fixture test. |
| STA-008 | Apple's own jobs in `/System/Library` are not listed. They are protected by System Integrity Protection. | Must | Unit test. |
| STA-009 | Plain-language explanations of Login Item, LaunchAgent, LaunchDaemon and background item. | Should | Review. |

### 9.4 History & Restore (HIS)

**Purpose.** Let the user put things back (J-5).

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| HIS-001 | The history log follows section 8.5. Each record is flushed with a barrier (`F_BARRIERFSYNC`) after it is written, so the drive writes it before what follows, and the whole log is flushed to permanent storage (`F_FULLFSYNC`) when a run ends (D-104). | Must | Kill-during-run test: log intent records match the disk state. Built in M2 (D-133): a test stops a run between an intent and its result record and checks History and Restore. |
| HIS-002 | The History view lists runs (date, area, item count, size, method, status). Each run expands to its items. A Tool item shows its command and a Launchctl item its job label, never a file path (D-106). | Must | UI test. |
| HIS-003 | **Restore** moves a trashed item from its trashed path back to its original path, recreating missing parent folders. If the original path is taken, ask: keep both (add " (restored)") or skip. Never overwrite. | Must | Fixture tests: normal restore, occupied path, missing parent. |
| HIS-004 | If an item's trashed path no longer exists, mark it "Not restorable (Trash emptied)". Permanent deletions and tool runs are shown as non-restorable. | Must | Fixture test. |
| HIS-005 | Restoring a startup item puts its plist back. It is re-enabled only if the user confirms. | Must | Fixture test. |
| HIS-006 | Shuck MUST NOT rely on Finder's "Put Back", which is unreliable when an app trashes several items in a row [S21]. Items Shuck trashes probably get no "Put Back" entry in Finder at all, so the UI says "Restore in Shuck". Unverified on macOS 27: to verify. | Must | Design review; check on macOS 27 whether Finder offers "Put Back" for an item Shuck trashed. |
| HIS-007 | Export a run report as Markdown or JSON. | Could | — |
| HIS-008 | History is kept until the user clears it: there is no size cap and no expiry. Settings has "Clear History…" (SET-007), which says that Restore is lost for the cleared runs and asks for confirmation. A tool's output tail stays at 2 KiB (D-115). Built in M5, with Settings (D-135). | Should | Unit test: clearing empties the log and keeps its permissions; UI test of the confirmation text. |

### 9.5 Overview (OVR)

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| OVR-001 | Show startup volume capacity, available space (`volumeAvailableCapacityForImportantUsageKey` [S46]) and a reclaimable estimate per File Cleanup sub-tool, counting each file once (FCL-007). Applications and Startup Items show no reclaimable figure (D-25): the Applications card shows the number of apps and their total size; the Startup Items card shows the number of items and how many have a missing program (STA-007). | Must | UI test with fixtures, including no reclaimable figure on the Applications and Startup Items cards. |
| OVR-002 | "Scan all" runs every tool's and sub-tool's scan concurrently, with per-sub-tool progress and cancel. | Must | Integration test. |
| OVR-003 | There is no bulk "clean all". Overview cards navigate to their tools and sub-tools, where review happens. | Must | UI test. |
| OVR-004 | After a run, show the estimated vs. measured change in free space with an explanation of any gap (SAF-013). | Should | Manual check. |

### 9.6 Onboarding & Permissions (ONB)

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| ONB-001 | The first-launch screen explains what Shuck does, the safety model in three bullets, and why Full Disk Access is needed. Since macOS 14, reading another app's container triggers a "data from other apps" prompt; since macOS 15 this also covers group containers [S24]. Buttons: "Open Privacy & Security settings" and "Continue with limited access". | Must | UI test. |
| ONB-002 | No public API reports Full Disk Access status [S49]. Infer it from permission errors when opening representative protected locations (actually open them; don't just check access). Never read the system privacy database (`TCC.db`) [S49]. Tools and sub-tools with skipped locations show a "Limited access" banner listing them. | Must | Fixture test with unreadable folders. |
| ONB-003 | Shuck never asks for admin rights in the MVP (D-08). | Must | Static check: no authorization APIs. |
| ONB-004 | When the app becomes active again, re-check access. If access changed, offer to relaunch. | Must | Manual check. |
| ONB-005 | Inline help popovers explain macOS concepts: Library, containers, LaunchAgents, DerivedData, and so on. | Should | Review. |

### 9.7 Settings (SET)

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| SET-001 | Exclusions list: add with a folder picker or drag and drop, remove. Applies to every tool and sub-tool. Built in M2, as the engine and a minimal list in Settings, so no release with permanent Delete ships without it (D-135). | Must | Fixture test: excluded paths never appear. |
| SET-002 | Thresholds: Large Files minimum size (500 MB); Old Files period (12 months) and minimum size (50 MB); Developer Junk staleness (30 days); log age (7 days). | Must | Unit test: defaults and persistence. |
| SET-003 | Developer project folders (for DEV-R06). The default suggestion is whichever of `~/Developer`, `~/Projects`, `~/Code`, `~/src` and `~/repos` exist, used until the user changes the list. A folder must be inside the home folder. Built in M2 as a minimal list with DEV-R06 (D-154). | Must | Unit test. |
| SET-004 | Settings are stored in `UserDefaults` under the domain `me.nutabi.shuck` (debug builds: `me.nutabi.shuck.debug`, D-70). | Must | Unit test. |
| SET-005 | About window: version, build, copyright, GPL notices, source link, trademark attribution (section 6). | Must | UI test. |
| SET-006 | "Reset to defaults". | Should | Unit test. |
| SET-007 | "Clear History…" (HIS-008). | Should | UI test. |

## 10. Non-functional requirements (NFR)

| ID | Requirement | Priority | Acceptance check |
|---|---|---|---|
| NFR-PERF-001 | The main thread is never blocked for more than 250 ms; interactions respond within 100 ms. Apple: delays under 100 ms are "rarely noticeable", and its tools report hangs above 250 ms [S57]. | Must | Instruments "Hangs" trace during a full scan shows no hang over 250 ms. |
| NFR-PERF-002 | Measure a home-folder scan baseline in M1. Target: under 2 minutes for about 1 million files on the owner's Mac. | Should | Recorded baseline in `docs/progress.md`. |
| NFR-PERF-003 | Peak memory during "Scan all" stays under 1 GB. | Should | Instruments measurement. |
| NFR-REL-001 | The history log is crash-safe (HIS-001). | Must | See HIS-001. |
| NFR-SEC-001 | No network APIs in the MVP. A CI static check fails on `URLSession`, the Network framework, `NSURLConnection` or socket APIs. | Must | CI check. |
| NFR-SEC-002 | No third-party packages. CI fails if the project resolves any package dependency other than Shuck's own local `ShuckKit` package (D-29). | Must | CI check. |
| NFR-SEC-003 | Hardened Runtime on; minimal entitlements; release builds without `get-task-allow` [S8]. | Must | `codesign -d --entitlements` check in the release workflow. |
| NFR-SEC-004 | Subprocesses follow DEV-004: no shell, absolute paths, argument arrays, explicit environment. | Must | Static check: no `/bin/sh -c`, `system()` or `popen`. |
| NFR-SEC-005 | Shuck's data folder is 0700 and its files are 0600. | Must | Unit test. |
| NFR-SEC-006 | `Logger` messages mark paths and file names as private [S68]. | Must | Code review checklist. |
| NFR-A11Y-001 | Every control has a VoiceOver label. Full keyboard navigation. Respects Increase Contrast, Reduce Motion and Reduce Transparency. No information conveyed by color alone [S58]. | Must | Accessibility Inspector audit in M5. |
| NFR-L10N-001 | English UI. All user-facing strings live in String Catalogs so localization (L-12) needs no code changes. | Must | Static check: no hard-coded UI strings and no stale String Catalog keys. Built in M5, with the localization and compatibility pass (D-133). |
| NFR-COMP-001 | App: macOS 27 or later, arm64. Engine package deployment target: macOS 26 (D-06). | Must | Build settings check in CI. In M5 the engine's macOS 26 build becomes a required check (D-133). |
| NFR-OBS-001 | Diagnostics use `Logger` with subsystem `me.nutabi.shuck` and one category per tool and sub-tool [S68]. | Must | Code review. |
| NFR-QA-001 | Engine line coverage of at least 80%. Every SAF requirement has at least one test that references its ID. | Must | CI coverage report; grep for SAF IDs in tests. Built in M2 (D-133): a static check that every Must SAF requirement built so far is named in a test. |
| NFR-QA-002 | UI tests launch the app with a debug-only fixture-root argument, so they never see real user data. | Must | The release build ignores the argument (unit test). |
| NFR-QA-003 | Each tool's and sub-tool's main path has a named step in a UI workflow test (a user's path through several tools), or a workflow of its own (D-75). | Must | CI. |

## 11. Architecture

### 11.1 Components

```text
┌────────────────────────────────────────────────────────────────┐
│ Shuck.app  (SwiftUI; AppKit where SwiftUI falls short)         │
│   Sidebar: Overview · File Cleanup · Applications ·            │
│            Startup Items · History                             │
│   Settings window (⌘,), opened from the app menu               │
│   Views → view models (@Observable, @MainActor)                │
└────────────────────────────────┬───────────────────────────────┘
                                 │ async calls, AsyncSequence progress
┌────────────────────────────────▼───────────────────────────────┐
│ ShuckKit  (Swift package, no UI, macOS 26 API floor)           │
│   Tools      registry of tools and their sub-tools             │
│              File Cleanup → Large Files, Old Files,            │
│                             Developer Junk, Caches & Logs      │
│              Applications, Startup Items                       │
│   Scanning   enumerate files, metadata, allocated sizes        │
│   Rules      Developer Junk / Caches & Logs rules (data)       │
│   Planning   scan results → Plan                               │
│   Safety     PathGuard, ProtectedLocations, RunningApps        │
│   Execution  module ShuckExecution (D-28): Trash, Delete,      │
│              ToolRunner, LaunchctlRunner, Restore's moves      │
│   History    JSONL writer/reader, restore planning             │
└────────────────────────────────────────────────────────────────┘
```

| Component | Responsibility | Notes |
|---|---|---|
| App target | Views, navigation, view models | Thin. No file mutation (SAF-017). The sidebar and the File Cleanup landing page are built from the tools registry. |
| Tools registry | Declares tools and their sub-tools. Each sub-tool is an independent unit (FCL-003). | Adding a sub-tool touches nothing else. |
| Scanning | Enumerate files, read resource values and metadata | Background tasks; cancellable; streams results. |
| Rules | Developer Junk and Caches & Logs rule definitions | Data, validated at load. |
| Planning | Turns selections into a `Plan` | The plan is what the review screen shows. |
| Safety | Path guard, protected locations, running-app check | Mandatory for every operation. |
| Execution | The only code allowed to mutate files or launchd state | Re-validates items (SAF-008). Its own module, `ShuckExecution`, which depends on `ShuckKit`; nothing in `ShuckKit` can call it (D-28). Restore's file moves run here. |
| History | Log and restore planning | Section 8.5. |
| Test support | Fixture-root harness, file factory (sizes, dates, extended attributes), fake tools | Used by engine and UI tests. |

**Concurrency.** Swift 6 language mode with strict concurrency checking. Scans run in task groups off the main actor; UI state is `@MainActor`.

### 11.2 Repository layout

```text
shuck/
├── AGENTS.md                  instructions for AI coding agents (D-16)
├── README.md
├── LICENSE                    full GPL-3.0 text
├── CHANGELOG.md               changes users see, per release; each release's notes (D-95)
├── docs/
│   ├── PRD.md                 this document
│   ├── decisions.md           decisions made after the planning phase (D-30 onwards)
│   ├── m1-review.md           tech-debt review at the end of M1
│   ├── progress.md            milestone and task checklist
│   ├── releasing.md           how to cut a release, secrets, local fallback
│   ├── repository-setup.md    GitHub settings the owner applies by hand
│   └── third-party.md         attribution for any reused rule data or code; created on first reuse
├── Shuck.xcworkspace          the project and the engine package, so every test runs (D-111)
├── Shuck.xcodeproj
├── Shuck.xctestplan           the scheme's tests: engine, app unit and UI tests
├── Shuck/                     app target
├── ShuckTests/                app unit tests
├── ShuckUITests/              UI tests (fixture root only)
├── Packages/ShuckKit/         engine package (D-28)
│   ├── Sources/ShuckKit/              Tools, Scanning, Rules, Planning, Safety, History
│   ├── Sources/ShuckExecution/        the only code that mutates user files or launchd state
│   ├── Sources/ShuckKitTestSupport/   fixture-root harness and file factory
│   └── Tests/
├── scripts/                   lint, test, static checks, code-change check, build-dmg, notarize, release notes
└── .github/                   CI, CodeQL and release workflows, pull request template
```

## 12. Engineering workflow

| ID | Requirement | Priority |
|---|---|---|
| ENG-001 | `main` is protected: pull request required, CI must pass, no force-push, squash merge [S65]. | Must |
| ENG-002 | One task = one pull request, or one stack of pull requests, with the task ID in the title (for example `[M1-T02] PathGuard`). Target about 200 changed lines of production code per pull request. A task that needs more is split into a stack of pull requests, each small and reviewable on its own (for example engine first, then UI); the split is planned at the start, and each pull request says what the next adds (D-62). An agent never has two open pull requests outside one stack (D-200). Google's guidance: about 100 lines is "usually a reasonable size", 1,000 "usually too large" [S29]. | Must |
| ENG-003 | The pull request template has these sections: Summary · Requirement IDs · **How to review this** (risky areas, files to read first) · **SwiftUI concepts used** (learning notes with Apple documentation links) · Test evidence · Checklist (tests added, no new dependencies, no network APIs, docs updated). There is no Screenshots section (D-65). | Must |
| ENG-004 | **Definition of done** for a task: builds; all tests pass locally and in CI; new behavior has tests (deletion paths use fixture tests); `swift-format` clean; static checks pass; `docs/progress.md` updated; `CHANGELOG.md` has a line for each change users can notice (D-95); pull request template complete. | Must |
| ENG-005 | **CI** (`ci.yml`) runs on every pull request, on the `xcode-27` runner (macOS 27, Apple Silicon) [S25], which is free for public repositories [S26]. A `Code changes` job on Linux runs the static checks, their self-test and the changelog check for every change, and decides whether a change touches code (D-66, D-98). `Lint, build and test` runs only for code changes: `swift-format` lint, one build from `Shuck.xcworkspace`, and `Shuck.xctestplan` (engine tests with the coverage gate, app unit tests, UI tests) (D-111). A push to `main` only builds, to warm the compilation cache (D-111). | Must |
| ENG-006 | **Static checks** run the same script locally and in CI: no network APIs; no third-party package dependencies; no shell execution; no file-mutation APIs outside the Execution module; no authorization or privilege APIs; no `SMAppService` outside the Execution module except `openSystemSettingsLoginItems()` (D-134). | Must |
| ENG-007 | **Release** (`release.yml`) runs on a tag `vX.Y.Z` pushed to `main`. Steps: Release archive → sign with Developer ID (certificate imported into a temporary keychain [S62]) → notarize the app with `notarytool` using an App Store Connect API key [S63] → staple → build the DMG with `hdiutil` → sign, notarize and staple the DMG → compute SHA-256 → `gh release create` with the DMG and checksum [S61], which publishes the release. **The owner approves the `release` environment before the job reads any secret** (D-174, superseding D-17's draft step). | Must |
| ENG-008 | Signing and notarization secrets are GitHub encrypted secrets, used only by the tag-triggered release workflow. They are never available to pull request workflows. | Must |
| ENG-009 | Versions follow Semantic Versioning [S60]. Each milestone ends with a pre-release tag (section 13). | Must |
| ENG-010 | `AGENTS.md` is the only agent-instruction file. Do not add `CLAUDE.md`: Claude Code reads `AGENTS.md` only when no `CLAUDE.md` exists [S28]. `AGENTS.md` is an open format read by many coding agents [S27]. | Must |
| ENG-011 | Decisions after the planning phase go in `docs/decisions.md` with ID, date, decision, rationale and rejected alternatives. | Must |
| ENG-012 | Local scripts mirror CI and release (lint, test, static checks, build-dmg, notarize), so the owner can release without CI if needed. | Should |

**`AGENTS.md` must contain**

1. Project summary with a link to this PRD.
2. Build, test, lint and static-check commands.
3. Repository layout.
4. Coding conventions: Swift 6 strict concurrency; no force unwraps in the engine; typed errors; `Logger` privacy.
5. Safety rules:
   - every mutation goes through the Execution layer;
   - the path guard is mandatory;
   - tests stay inside the fixture root;
   - never touch the real home folder.
6. Dependency policy (D-03) and the reuse policy (section 5).
7. Pull request rules (ENG-002, ENG-003) and the definition of done (ENG-004).
8. How to pick the next task (`docs/progress.md`, in roadmap order) and how to record progress.
9. The rule: do not add `CLAUDE.md` (ENG-010).
10. How to add a sub-tool or a cleanup rule: registry entry, ownership map (FCL-005), fixture tests.

## 13. Roadmap

Milestones run in order and have no dates (D-15). Each one ends with a tagged pre-release built by the release workflow.

| Milestone | Goal | Exit criteria | Tag |
|---|---|---|---|
| **M0 Foundations** | Repository, project skeleton, CI/CD proven end to end | CI green on a pull request; a tag produces a notarized draft release of the empty app shell | `v0.0.1` |
| **M1 Safety core + File Cleanup (Large Files, Old Files) + Restore** | First complete vertical slice inside the File Cleanup tool: sub-tool registry, scan → review → Trash → restore | Owner finds, trashes and restores files with both sub-tools; all Trash-path SAF requirements tested | `v0.1.0` |
| **M2 File Cleanup: rebuildable sub-tools** | Developer Junk (Must rules) and Caches & Logs sub-tools; permanent delete and tool commands; user exclusions (SET-001, D-135) | Owner reclaims space with a summary confirmation; every tool run logged | `v0.2.0` |
| **M3 Applications** | Uninstaller with confidence levels, running-app handling, LaunchAgent unloading (APP-011; first use of the launchctl runner), restore | Owner uninstalls an app plus leftovers and restores it | `v0.3.0` |
| **M4 Startup Items** | launchd inventory, status, manage user agents, Login Items link | Owner disables and removes a user agent and restores it | `v0.4.0` |
| **M5 Overview, onboarding, settings, polish** | Overview, Full Disk Access onboarding, Settings (exclusions came in M2), Clear History, About and legal notices, accessibility pass, localization and compatibility checks (D-133), DEV Should rules, README screenshots | All Must requirements met; accessibility audit passed | `v0.5.0` |
| **M6 Release and real use** | Release candidate, then 4 weeks of real use (fixes only), trademark search for "Shuck" | MVP exit criteria (section 2.4) | `v1.0.0` |

### 13.1 M0 tasks (one pull request each)

| Task | Deliverable |
|---|---|
| M0-T01 | `LICENSE` (GPL-3.0 text), README skeleton (tagline, status, trademark notice), `.gitignore`, `docs/` with this PRD |
| M0-T02 | `AGENTS.md` per section 12 |
| M0-T03 | Xcode project: app target "Shuck", bundle ID `me.nutabi.shuck`, macOS 27, arm64, Hardened Runtime on, no sandbox; window with sidebar placeholders |
| M0-T04 | `ShuckKit` package skeleton (macOS 26 floor) with a Swift Testing test target and a test-support target |
| M0-T05 | `swift-format` configuration and lint script |
| M0-T06 | `ci.yml` on `xcode-27`: lint, build, test. Document the branch-protection settings for the owner to apply. |
| M0-T07 | Static-check script (ENG-006), wired into CI |
| M0-T08 | `release.yml` producing a signed, notarized draft release of the app shell; document the required secrets; local fallback script |
| M0-T09 | Pull request template (ENG-003), `docs/progress.md`, `docs/decisions.md` |

### 13.2 M1 tasks

| Task | Deliverable | Requirements |
|---|---|---|
| M1-T01 | Fixture-root test harness and file factory | SAF-016 |
| M1-T02 | Path guard and protected locations, with the full test matrix | SAF-007, 8.4 |
| M1-T03 | History log writer and reader (JSONL, intent and result records, flush) | SAF-005, HIS-001 |
| M1-T04 | Trash executor with re-validation and per-item outcomes | SAF-004, SAF-008, SAF-011 |
| M1-T05 | Restore (conflicts, missing parents, Trash emptied) | HIS-003, HIS-004 |
| M1-T06 | Sub-tool interface, registry and ownership map; File Cleanup landing page | FCL-001 to FCL-005 |
| M1-T07 | Personal-files scanner (scope, packages, iCloud placeholders, tool-owned stores, streaming, cancel) with shared item state | FCL-006, FCL-008 to FCL-011, SAF-014 |
| M1-T08 | Shared results UI for personal files: sort, Quick Look, Show in Finder | FCL-012 |
| M1-T09 | Large Files sub-tool | LRG-001 to LRG-003 |
| M1-T10 | "Last opened" metadata with fallback | OLD-002 |
| M1-T11 | Old Files sub-tool | OLD-001, OLD-003 |
| M1-T12 | Itemized review sheet, confirmation, summary | SAF-002, LRG-004, OLD-004 |
| M1-T13 | De-duplicated totals across sub-tools | FCL-007 |
| M1-T14 | History view and Restore action | HIS-002 |
| M1-T15 | UI smoke tests with the fixture root | NFR-QA-002, 003 |
| M1-T16 | Performance baseline recorded | NFR-PERF-002 |

M2 to M6 are broken into tasks when each milestone starts. The breakdown is recorded in `docs/progress.md`.

## 14. Risks

| ID | Risk | Impact | Mitigation |
|---|---|---|---|
| R-01 | No supported API lists other apps' login and background items. The Background Task Management data is undocumented, and dumping it needs `sudo` [S17][S16]. | Startup Items view is incomplete | Show what launchd plists reveal; link to System Settings for the rest (STA-004); document the limits in the UI. |
| R-02 | macOS privacy protections change between releases (app containers in macOS 14, group containers in macOS 15) [S24]. | Scans silently miss data | Treat permission errors as signals (ONB-002); re-test on each new macOS beta. |
| R-03 | No API reports Full Disk Access status [S49]. | Confusing onboarding | Error-driven detection and clear banners (ONB-002). |
| R-04 | AI-written code that deletes files | Data loss | Engine-only mutation (SAF-017), path guard, fixture tests, review guidance in every pull request, two review tiers. |
| R-05 | Leftover matching produces false positives | Wrong files trashed | Confidence levels; only exact matches selected; Trash and restore (APP-003). |
| R-06 | Freed space differs from the estimate (Trash, local Time Machine snapshots, APFS clones, purgeable space) | Users don't trust the numbers | Show estimated vs. measured and explain (SAF-013). |
| R-07 | Tool command behavior changes (npm, pip, brew, docker) | Rule failures | Recorded-output tests; never parse tool output to choose deletion targets; surface exit codes. |
| R-08 | Cleaning caches of running apps causes misbehavior | App glitches | Skip running apps' caches (CAC-003). |
| R-09 | Copyright on AI-generated code may be limited. US Copyright Office (Jan 2025): prompts alone don't make you the author of the output; human selection, arrangement and edits can be protected [S41]. | GPL is weaker over AI-written parts | Accepted (D-20). Document the owner's human contributions in pull requests. |
| R-10 | "Shuck" has only been web-searched, not trademark-cleared | Rename after release | Trademark search in M6, before v1.0. |
| R-11 | Scope creep with no deadline | MVP never ships | Exit criteria (section 2.4); backlog (7.2); changes through `docs/decisions.md`. |
| R-12 | CI runner labels or images change (`xcode-27` uses a new label scheme) [S25] | Broken CI | Pin the label; local fallback scripts (ENG-012). Mitigated: `ci.yml` pins `xcode-27` and UI tests passed on it (D-31); the local scripts exist. |
| R-13 | Leaked signing secrets | Malicious builds signed with the owner's identity | Tag-only release workflow (ENG-008); App Store Connect API key with the narrowest role that allows notarization; rotate on suspicion. |
| R-14 | Testing on a single macOS version and a single Mac | Bugs on other setups | Fixture tests plus a clean CI runner; a virtual machine for macOS 26 later (L-02). |
| R-15 | Sub-tools or tools overlap: the same file in Large Files and Old Files, a cache claimed by two sub-tools, or an app container's caches listed by both Caches & Logs and Applications | Double counting or double cleaning | Ownership map (FCL-005), shared personal-files state (FCL-006), de-duplicated totals (FCL-007), reclaimable totals for File Cleanup only (OVR-001), re-validation before acting (SAF-008). |
| R-16 | macOS's App Management permission (`kTCCServiceSystemPolicyAppBundles`, macOS 13+) gates changing other apps' bundles, and other apps' containers prompt separately [S78]. App Store and package-installed apps are often root-owned. | An uninstall fails or is blocked for many apps | Check removability before offering an uninstall (APP-005); show the reason; the owner measures how many of their own apps are removable before M3 is broken down (OQ-08); a usage string for the permission (M5). |
| R-17 | Reviewer fatigue: pull request stacks grow, and the owner reviews every change (G-5). | A defect in Safety or Execution is merged unseen | Small pull requests (D-62); changes to Safety and Execution in pull requests of their own; every pull request says where to look (ENG-003); periodic reviews of `main` like the one of 2026-11-10. |
| R-18 | Old Files relies on Spotlight metadata (`kMDItemLastUsedDate`), which may be missing or stale. | A file in use looks old | Use the latest of the last-used, modification and added dates (OLD-002, D-130); nothing is selected by default (OLD-004). |

## 15. Open questions

Defaults are already in place; the owner can change them at any time.

| ID | Question | Current default |
|---|---|---|
| OQ-01 | Large Files threshold; Old Files period and minimum size | 500 MB; 12 months (presets 3, 6, 12, 24) and 50 MB. Validate during M1 use. |
| OQ-02 | Suggested developer project folders | Existing folders among `~/Developer`, `~/Projects`, `~/Code`, `~/src`, `~/repos` |
| OQ-03 | Log age default | 7 days |
| OQ-04 | Docker tier | Resolved (D-24): Your data, never selected by default. |
| OQ-05 | Progress tracking | Resolved: `docs/progress.md` is the task list; GitHub issues hold review findings (GitHub Issues for tasks possible later). |
| OQ-06 | iCloud Drive and other synced files | iCloud Drive's own folders (`~/Library/Mobile Documents`, `~/Library/CloudStorage`): fully protected, not scanned. A downloaded file that a sync service keeps elsewhere in the home folder, such as Desktop and Documents under iCloud, is scanned, marked "Synced" and warned about at review (D-129). |
| OQ-07 | Leftovers in Application Support and Group Containers can be the only copy of a user's data (notes, vaults). APP-003 preselects High-confidence items, which can include them. | Decided (D-192): leftovers in Application Support, Containers and Group Containers are never preselected. |
| OQ-08 | How many of the owner's own apps can Shuck remove (R-16)? | Open for the owner: measure before M3 is broken down. |

## Appendix A — Decision log (planning phase, 2026-11-01)

| ID | Decision | Rationale | Rejected alternatives | Sources |
|---|---|---|---|---|
| D-01 | Goal: the owner's daily-driver tool and a portfolio piece | The owner wants the features they need, with the independence their own app gives them | Open-source community product; commercial product (crowded market) | [S1][S2] |
| D-02 | Free if released; no monetization | Matches D-01 | Paid or freemium | — |
| D-03 | Build, don't buy: Apple frameworks only; any third-party package needs a recorded decision | Independence and learning; smaller supply-chain risk | Use libraries such as Sparkle | [S31] |
| D-04 | Public source repository plus Developer ID-signed, notarized releases; not sandboxed; Hardened Runtime from day one; no Mac App Store | The App Store sandbox and no-root rule conflict with core features. Since macOS 15, unnotarized apps are harder to open. The owner has a paid membership. | Source only; unnotarized downloads; Mac App Store | [S7][S8][S9][S10][S11] |
| D-05 | macOS 27+, Apple Silicon only; owner's Mac is the main test device; macOS 26 after the MVP | Smallest test matrix; the owner runs macOS 27; macOS 27 has no Intel support | macOS 26+, 15+, 14+ | [S12][S13][S14][S15] |
| D-06 | Engine uses only macOS 26 APIs | Makes L-02 a build-settings change | No API floor | — |
| D-07 | MVP areas: Large & Old Files, Applications, Startup Items (limited), Developer Junk. Later: leftovers from deleted apps, disk map, duplicates, unused apps, scheduled scans and menu bar, Homebrew manager. Structure revised by D-23. | The owner's named needs; developer junk is often the biggest win for engineers | Larger MVP | [S16][S17] |
| D-08 | No admin rights in the MVP; the privileged helper is the first post-MVP item | Prove the safety core first; a root helper is the riskiest component | Helper in the MVP; AppleScript prompt per action (Apple DTS: only for small-audience tools) | [S18][S19] |
| D-09 | Deletion model "B": Trash for personal data; permanent delete for rebuildable data | Frees space where data can be rebuilt; recoverable where it can't | Trash only; app-managed holding folder | [S1] |
| D-10 | Safety defaults: review before acting; selection rules; Shuck's own restore log; protected locations; tool-owned data cleaned through the tool; never act on running apps | Finder's "Put Back" is unreliable for batch trashing | Relying on "Put Back" | [S21] |
| D-11 | Two review tiers (summary confirmation for rebuildable data, itemized list for personal data), backed by hard path guards in code | The owner's amendment: auto-generated data doesn't need itemized review. Guards cover path bugs such as the Steam `rm -rf` incident. | Itemized review for everything; no confirmation at all | [S22][S23] |
| D-12 | User-level caches and logs are in the MVP | Cheap once the rebuildable tier exists; gains may be temporary because macOS clears these automatically | Developer caches only | [S5] |
| D-13 | Window app only; engine as a separate Swift package; sidebar navigation; Full Disk Access onboarding | Review lists need a window. A UI-free engine allows headless tests and a later command-line tool. | Command-line tool; menu bar item | [S24][S2] |
| D-14 | Swift 6, SwiftUI first, Xcode 27, Swift Testing and XCUITest, `swift-format`, JSONL history, GitHub Actions on `xcode-27` | Native, zero dependencies, free CI for public repos | Third-party tooling | [S25][S26] |
| D-15 | AI agents implement, the owner reviews; no time-based deadline; milestone roadmap; MVP exit criteria in section 2.4 | Owner's Swift: some, SwiftUI: none. Work happens in sessions when time allows. | Date-based plan | — |
| D-16 | `AGENTS.md` only (no `CLAUDE.md`) | Claude Code reads `AGENTS.md` natively; open format read by many agents | `AGENTS.md` plus `CLAUDE.md` | [S27][S28] |
| D-17 | Small pull requests; protected `main`; CI required; tag-triggered release creates a draft that the owner publishes | Each change is reviewable; the owner keeps control of releases | Fully automatic publishing | [S29][S61] |
| D-18 | Offline; no telemetry; no in-app updates in the MVP ("Check for Updates" later) | Privacy, simplicity; the owner builds from source | Manual or automatic update check; self-updater | [S30][S31] |
| D-19 | Notarized DMG, not `.pkg` | Simpler; no relocation trap; no installer certificate or admin password | `.pkg` installer | [S32][S33] |
| D-20 | GPL-3.0-or-later | The owner prefers copyleft. Drawbacks reviewed: App Store conflict (moot), corporate reluctance, relicensing needs contributors' agreement, AI-code copyright limits. Upside: can reuse Mole and DevCleaner (GPL-3.0). | MIT; Apache-2.0; source-available | [S37][S38][S39][S40][S41][S69] |
| D-21 | Name "Shuck"; bundle ID `me.nutabi.shuck` (owner controls `nutabi.me`) | "Mac Assistant" likely conflicts with Apple's trademark guideline and is hard to find. Bundle ID chosen before the first commit because macOS uses it to apply preferences and validate the signature. | Mac Assistant, Winnow, Whittle, Pare, Pith | [S34][S36] |
| D-22 | `docs/PRD.md` in Markdown only; delivered as a file; the owner initialises the repository | Readable by both humans and AI agents; GitHub renders Markdown | PDF rendering (dropped by the owner); hosted page; Claude-created repository | — |
| D-23 | File Cleanup is one tool made of independent sub-tools: Large Files, Old Files, Developer Junk, Caches & Logs. Applications and Startup Items stay separate tools. | One home for file-based cleaners. New file sub-tools (disk map, duplicates) fit in without growing the sidebar. Independent sub-tools map to small, separately testable pull requests. Conditions: tiers stay per sub-tool or rule; each location has one owner; Large Files and Old Files share state and are counted once. | A separate top-level area per cleaner (v1.0); one combined "Large & Old Files" view | — |
| D-24 | The tier decides the review style and default selection; each rule or action declares its method (Trash, Delete, Tool, Launchctl). "Your data" never uses Delete, and an irreversible "Your data" action says so and is logged as non-restorable. A Tool action is reviewed as one item: command, effects, the tool's size estimate. | v1.1 required Trash for all "Your data", which Docker prune (DEV-R10) and startup-item Disable (STA-005) already broke. One invariant covers both, and future tool-owned data such as L-04. Shuck cannot list what a tool command will remove without trusting its output (R-07). | Named exceptions in SAF-004; moving Docker to Rebuildable; listing stopped containers in the review | [S51] |
| D-25 | Overview reports reclaimable space for File Cleanup sub-tools only; Applications and Startup Items show counts. Ownership (FCL-005) is scoped to File Cleanup; overlaps with other tools are allowed, never summed, and handled at run time by SAF-008. | An app's container holds caches that Caches & Logs also lists, and an uninstall must still remove the whole container. Space held by apps in use is not "reclaimable" (P-7). | A reclaimable figure for Applications with de-duplication across all tools | — |
| D-26 | An uninstall unloads a matching user LaunchAgent (`launchctl bootout`) before trashing its plist, through the same execution path as STA-005 Remove. | Trashing a loaded agent's plist leaves the job loaded until logout. | Trash only; leaving it as an open question | [S47] |
| D-27 | Settings opens in its own window from the app menu (⌘,), through a SwiftUI `Settings` scene. The sidebar ends with History. | Standard macOS behavior that users expect; keeps the sidebar to tools and their results. | A Settings row at the end of the sidebar (v1.2) | — |
| D-28 | The ShuckKit package has three library targets: `ShuckKit` (Tools, Scanning, Rules, Planning, Safety, History), `ShuckExecution` (depends on `ShuckKit`; the only code that mutates user files or launchd state, including Restore's moves) and `ShuckKitTestSupport`. | The compiler, not only review, keeps mutation in one place: `ShuckKit` cannot call `ShuckExecution`. The SAF-017 static check becomes a per-folder rule. | One module with a folder per layer; one module per layer | — |
| D-29 | The dependency ban (D-03, NFR-SEC-002) covers third-party packages only. Shuck's own local `ShuckKit` package is linked into the app. | The engine is Shuck's own code; the ban exists to avoid outside code. | Treating the local package as a dependency to avoid | — |

## Appendix B — Glossary

| Term | Meaning |
|---|---|
| Allocated size | Space a file actually uses on disk, which can differ from its logical size. |
| APFS | Apple File System. Supports clones and snapshots, so deleting a file doesn't always free space immediately. |
| App container | A sandboxed app's private folder in `~/Library/Containers`. Group containers (`~/Library/Group Containers`) hold data shared by related apps. |
| Background Task Management (BTM) | The macOS subsystem behind Login Items & Extensions settings. Undocumented. |
| Bundle ID | Reverse-DNS app identifier, for example `me.nutabi.shuck`. |
| DerivedData | Xcode's build output and indexes. Rebuildable. |
| Developer ID | Apple certificate for distributing Mac apps outside the App Store. |
| DMG | Disk image used to distribute Mac apps. |
| Full Disk Access (FDA) | Privacy permission that lets an app read protected locations. |
| Hardened Runtime | Code-signing runtime protections; required for notarization. |
| JSONL | JSON Lines: one JSON object per line. |
| launchd | macOS service manager. A **LaunchAgent** runs in a user session; a **LaunchDaemon** runs system-wide as root. |
| Login Item | An app that opens when the user logs in. |
| Notarization | Apple's automated malware check for Developer ID software; the resulting ticket is "stapled" to the app or DMG. |
| SIP | System Integrity Protection. Protects system locations even from root. |
| SMAppService | Apple API (macOS 13+) for registering an app's own login items, agents and daemons. |
| Sub-tool | An independent unit inside a tool, with its own scan, results, review and action (for example Large Files inside File Cleanup). |
| TCC | Transparency, Consent and Control: the macOS privacy permission system. |
| Tool | A top-level feature in Shuck's sidebar: File Cleanup, Applications, Startup Items. |
| XPC | macOS inter-process communication, used between an app and its helper. |

## Appendix C — References

S1 to S70 were accessed on 2026-11-01. S71 to S78 come from the review of 2026-11-10; the review's wording is kept, and the pages have not been re-read for this document.

| ID | Source | URL |
|---|---|---|
| S1 | Mole (GitHub) | https://github.com/tw93/Mole |
| S2 | Pearcleaner (GitHub) | https://github.com/alienator88/Pearcleaner |
| S3 | DevCleaner for Xcode (GitHub) | https://github.com/vashpan/xcode-dev-cleaner |
| S4 | AppCleaner | https://freemacsoft.net/appcleaner/ |
| S5 | Apple: Optimize storage space on your Mac | https://support.apple.com/guide/mac-help/sysp4ee93ca4 |
| S6 | Apple: Open items automatically when you log in | https://support.apple.com/guide/mac-help/mh15189/mac |
| S7 | Apple: App Review Guidelines (2.4.5) | https://developer.apple.com/app-store/review/guidelines/ |
| S8 | Apple: Notarizing macOS software before distribution | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution |
| S9 | Apple: Choosing a membership | https://developer.apple.com/support/compare-memberships |
| S10 | 9to5Mac: macOS Sequoia makes it harder to run unnotarized apps | https://9to5mac.com/2024/08/06/macos-sequoia-makes-it-harder-to-run-apps-that-dont-follow-apples-security-rules/ |
| S11 | Homebrew/brew#20755 (Gatekeeper cutoff) | https://github.com/Homebrew/brew/issues/20755 |
| S12 | MacRumors: macOS 27 Golden Gate release date | https://www.macrumors.com/2026/09/10/macos-27-golden-gate-release-date/ |
| S13 | Six Colors: Tahoe is the last release to support Intel | https://sixcolors.com/post/2025/06/macos-tahoe-is-the-last-release-to-support-intel/ |
| S14 | TelemetryDeck: macOS version share | https://telemetrydeck.com/survey/apple/macOS/versions/ |
| S15 | Apple: Running macOS in a virtual machine on Apple silicon | https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon |
| S16 | Apple: SMAppService | https://developer.apple.com/documentation/servicemanagement/smappservice |
| S17 | Eclectic Light: Manage login and background items | https://eclecticlight.co/2025/12/03/manage-login-and-background-items/ |
| S18 | Apple DTS: BSD privilege escalation on macOS | https://developer.apple.com/forums/thread/708765 |
| S19 | Bryson Tyrrell: macOS apps with embedded daemons | https://dev.to/brysontyrrell/macos-apps-with-embedded-daemons-333a |
| S20 | Homebrew FAQ | https://docs.brew.sh/FAQ |
| S21 | Apple Developer Forums: trashItem, recycle, but no Put Back | https://developer.apple.com/forums/thread/773997 |
| S22 | Apple: File System Programming Guide (Library directories) | https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html |
| S23 | ValveSoftware/steam-for-linux#3671 | https://github.com/valvesoftware/steam-for-linux/issues/3671 |
| S24 | Eclectic Light: What are all those Containers? | https://eclecticlight.co/2024/08/05/what-are-all-those-containers/ |
| S25 | GitHub Changelog: Xcode 27 runner image generally available | https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available |
| S26 | GitHub Docs: GitHub Actions billing | https://docs.github.com/en/billing/concepts/product-billing/github-actions |
| S27 | AGENTS.md | https://agents.md/ |
| S28 | Claude Code docs: memory and AGENTS.md | https://code.claude.com/docs/en/memory |
| S29 | Google Engineering Practices: Small CLs | https://google.github.io/eng-practices/review/developer/small-cls.html |
| S30 | GitHub Docs: REST API rate limits | https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api |
| S31 | Sparkle | https://sparkle-project.org/ |
| S32 | Apple Developer Forums: keeping Installer from relocating packages | https://developer.apple.com/forums/thread/743964 |
| S33 | Scripting OS X: Relocatable package installers | https://scriptingosx.com/2017/05/relocatable-package-installers-and-quickpkg-update/ |
| S34 | Apple: Guidelines for Using Apple Trademarks and Copyrights | https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html |
| S35 | Apple: Trademark list (attribution notice) | https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html |
| S36 | Apple: CFBundleIdentifier | https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier |
| S37 | GNU General Public License v3.0 | https://www.gnu.org/licenses/gpl-3.0.html |
| S38 | Engadget: The GPL, the App Store, and you | https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html |
| S39 | Google Open Source: license categories | https://opensource.google/documentation/reference/thirdparty/licenses |
| S40 | Open Source Guides: The legal side of open source | https://opensource.guide/legal/ |
| S41 | US Copyright Office: AI Report Part 2 (copyrightability) | https://www.copyright.gov/newsnet/2025/1060.html |
| S42 | Apple: FileManager.trashItem(at:resultingItemURL:) | https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:) |
| S43 | Apple: kMDItemLastUsedDate | https://developer.apple.com/documentation/coreservices/kmditemlastuseddate |
| S44 | Apple: URLResourceKey.totalFileAllocatedSizeKey | https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey |
| S45 | Apple: URLResourceKey.ubiquitousItemDownloadingStatusKey | https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemdownloadingstatuskey |
| S46 | Apple: URLResourceKey.volumeAvailableCapacityForImportantUsageKey | https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey |
| S47 | launchctl(1) man page | https://keith.github.io/xcode-man-pages/launchctl.1.html |
| S48 | Apple: SMAppService.openSystemSettingsLoginItems() | https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems() |
| S49 | Apple Developer Forums: Reliable test for Full Disk Access? | https://developer.apple.com/forums/thread/114452 |
| S50 | Apple: Building your app to include debugging information | https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information |
| S51 | Docker: docker system prune | https://docs.docker.com/reference/cli/docker/system/prune/ |
| S52 | pip: pip cache | https://pip.pypa.io/en/stable/cli/pip_cache/ |
| S53 | npm: npm cache | https://docs.npmjs.com/cli/commands/npm-cache |
| S54 | Homebrew: manpage (`brew cleanup`) | https://docs.brew.sh/Manpage |
| S55 | CocoaPods: command-line reference | https://guides.cocoapods.org/terminal/commands.html |
| S56 | Go: cmd/go (`go clean -modcache`) | https://pkg.go.dev/cmd/go |
| S57 | Apple: Understanding hangs in your app | https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app |
| S58 | Apple: Human Interface Guidelines, Accessibility | https://developer.apple.com/design/human-interface-guidelines/accessibility |
| S59 | JSON Lines | https://jsonlines.org/ |
| S60 | Semantic Versioning | https://semver.org/ |
| S61 | GitHub CLI: gh release create | https://cli.github.com/manual/gh_release_create |
| S62 | GitHub Docs: Signing Xcode applications | https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications |
| S63 | Apple: Customizing the notarization workflow | https://developer.apple.com/documentation/security/customizing-the-notarization-workflow |
| S64 | RFC 2119: Key words for use in RFCs | https://www.rfc-editor.org/rfc/rfc2119 |
| S65 | GitHub Docs: About protected branches | https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches |
| S66 | Apple: NSXPCConnection.setCodeSigningRequirement(_:) | https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:) |
| S67 | Apple: Hardened Runtime | https://developer.apple.com/documentation/security/hardened-runtime |
| S68 | Apple: Logger | https://developer.apple.com/documentation/os/logger |
| S69 | The Next Web: Apple officially pulls VLC from the App Store | https://thenextweb.com/news/apple-officially-pulls-vlc-from-the-app-store |
| S70 | Fig manual: `swift package purge-cache` (third-party reference) | https://fig.io/manual/swift/package/purge-cache |
| S71 | npm: config | https://docs.npmjs.com/cli/v10/using-npm/config |
| S72 | Docker: docker builder prune | https://docs.docker.com/reference/cli/docker/builder/prune/ |
| S73 | Apple Developer Forums: deleting simulator runtimes | https://developer.apple.com/forums/thread/842603 |
| S74 | Mole issue 1689 (deleting `~/Library/Logs/DiagnosticReports` stopped crash reports) | https://github.com/tw93/Mole/issues/1689 |
| S75 | Mole issue 1854 (cleaning caches of a running app) | https://github.com/tw93/Mole/issues/1854 |
| S76 | Mole issue 823 (Claude Code memory folders deleted as caches) | https://github.com/tw93/Mole/issues/823 |
| S77 | DevCleaner for Xcode issue 48 (CoreSimulator caches) | https://github.com/vashpan/xcode-dev-cleaner/issues/48 |
| S78 | Apple Developer Forums: App Management permission and other apps' containers | https://developer.apple.com/forums/thread/678819 |
