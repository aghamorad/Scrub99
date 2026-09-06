# Scrub99 implementation status

Date: 2026-08-24

## Why the previous implementation stalled

The checked-in Xcode project did not describe a buildable GUI target. Its Swift source phase was empty, its JSON rules were assigned to a sources phase, source references pointed to paths that did not exist, and `CleanupView.swift` and `SettingsView.swift` were not members of the target. The source itself had additional compile failures. A prebuilt arm64 bundle existed, but it was ad-hoc linker-signed and did not establish that the checked-in GUI source had ever built.

The scanner also behaved like a hang. It recursively enumerated the whole home directory to find top-level dot folders, recursively enumerated broad Library roots again, and applied its depth limit only after obtaining every descendant path. The installed-application list was passed into ordinary scanning but never used to associate results. Several rule paths expanded to the wrong location because `Library/` was missing.

The cleanup implementation was unsafe. A failed quarantine move was returned as success. Restore deleted an existing destination before moving the quarantined item back. Every cleanup overwrote the single previous manifest. Parent and child findings could both be selected, and no path boundary stopped an arbitrary `FoundItem` from targeting user data.

## Implemented safety milestone

- Initialized local Git metadata without removing or replacing any source or bundle.
- Preserved the original scanner as `LegacyScanner` and the original cleanup engine as `LegacyCleanupEngine`; both are excluded from the active app target.
- Repaired Xcode source/resource phases and file references.
- Added `BoundedScanner.swift`, which audits exact rule-backed roots, measures each root once, yields during large measurements, supports task cancellation, and never mutates files.
- Corrected Claude, Ollama, and LM Studio rule paths in both preserved rule copies.
- Disabled all automatic selection.
- Added `SafetyPolicy.swift`. Only existing, non-symlink cache or log roots under approved locations, with safe classifications and strong application associations, can pass preflight. Home, user-data, credential, cloud, quarantine, duplicate, and overlapping paths are blocked.
- Added `SafeCleanupEngine.swift`. It writes a transaction manifest before moving anything, uses unique destinations, disables direct Trash, records each result atomically, retains all manifests, and never overwrites during restore.
- Added explicit UI selection and a second confirmation sheet. Ineligible findings remain visible as advisory results.
- Moved filesystem enumeration off the SwiftUI main actor and added cancellation for both the UI task and detached scan worker. This fixes the workload-sensitive beachball seen when a rule-backed cache contains many entries.
- Added 33 executable assertions covering protected paths, explicit protected-data approval, symlinks, uncertain ownership, overlaps, Trash refusal, quarantine, collision refusal, exact restore, append-only history, expanded workspace inventory, exact child paths, size measurement, command-line application detection, reader-guide specificity, and strict guided-cleanup eligibility.
- Added `~/Claude`, `~/Documents/Claude`, `~/.claude`, and `~/.claude-vision` as explicit Claude inventory roots. Immediate children are reported separately and project workspaces are categorically blocked from cleanup.
- Added a searchable split results view. Every listed path can be selected to show its full path, measured size, category, association evidence, safety status, explanation, cleanup decision, and Reveal in Finder action.
- Made every non-blocked result independently tickable and untickable. Protected personal data requires a typed `QUARANTINE` confirmation, every move remains manifest-backed and reversible, and the results action bar exposes Undo Last Quarantine.
- Fixed same-second manifest ordering by recording nanosecond transaction time, so Undo Last cannot choose an older transaction when two quarantines occur within one second.
- Added a reader-facing audit explanation and an item-specific guide answering what each path is, why it exists, whether it is normally necessary, and the risk of quarantining it. The guide includes specialized judgments for common project artifacts and states when the evidence cannot establish regenerability.
- Added `Clean Up Unnecessary Stuff…` as a sequential review flow. Its queue is limited to rule-backed low-risk caches and logs that pass the standard safety policy. It pauses on every item, repeats the full explanation, and offers only Stop, Keep This Item, or Move This Item to Quarantine; there is no approve-all action.
- Added `script/build_and_run.sh`, `script/typecheck.sh`, `script/test_safety.sh`, and the Codex Run action.

## Verified

- All eight JSON rules parse as valid JSON.
- The GUI source type-checks directly with the Xcode Swift compiler and macOS SDK.
- `script/test_safety.sh` passes all 33 assertions using a unique temporary home directory.
- The original 48-file snapshot and SHA-256 inventory were preserved in the Codex task workspace before edits.
- An original retro icon is embedded as a validated multi-resolution ICNS resource.
- An Apple-silicon `Scrub99.app` version 0.2.4 was compiled directly and ad-hoc signed for local use. Its real scan found 36 reviewable items across 59 measured paths, including the 34.0 GB Claude workspace. The results screen was inspected under the Mac's active dark appearance after the app was given a deliberate high-contrast light theme; headers, sizes, status labels, and details now remain readable. A result was ticked and unticked to verify selection, and no cleanup or quarantine action was invoked. The safety, scanner, and explanation suite passes all 33 assertions.
- Version 0.2.5 makes every result row a full-width inspection target while retaining its checkbox as a separate selection control. A real scan exposed 36 accessible `Inspect` buttons. Clicking the 32.5 GB Virastar row opened its exact detail pane while leaving the selection at zero; its checkbox was then independently ticked and unticked. No cleanup or quarantine action was invoked.
- Version 0.2.6 makes Item, Category, Size, and Status/Safety clickable sort headers with visible direction indicators. Sorting reorders both application groups and their paths, uses deterministic path tie-breaking, and preserves inspection and checkbox identity. Live verification showed largest-first size order as Claude 34.0 GB, Ollama 6.8 GB, UV 6.0 GB, and Hugging Face 4.3 GB; reversing began with ChatGPT 16.0 KB. The suite now passes 37 assertions, including item and aggregate group sorting.
- Version 0.3.0 adds an inspectable Quarantine window with its exact storage path, original and quarantine paths, per-item Reveal and Restore actions, and explicitly confirmed permanent deletion from quarantine only. Quarantine manifests now record restored and permanently purged items without overwriting history. The app delegate restores and activates the main window when the Dock icon is clicked after the window is closed. The safety suite now passes 40 assertions.
- The distributable ZIP passed archive integrity checking, and its extracted app passed strict code-signature verification.

## External blocker

Xcode is installed at `/Applications/Xcode.app`, but its license has not been accepted. The normal `xcodebuild` workflow still exits before evaluating the project. A usable local app was nevertheless produced with Xcode's matching Swift compiler and SDK; future Xcode builds still require Morad to review and accept Apple's agreement.

## Next implementation sequence

1. Accept the Xcode license, run `./script/build_and_run.sh --verify`, and inspect the visible scan and confirmation flows.
2. Add fixture-driven scanner tests with a test-only rule engine and synthetic home directory.
3. Add model-file hashing as an explicit, on-demand read-only operation. Use size plus SHA-256 to establish real duplicates; never infer duplicates from filenames.
4. Add an opt-in advisory provider with a strict redaction contract. It may return `keep`, `review`, or `quarantine candidate` with evidence and uncertainty. Its output cannot change `CleanupSafetyPolicy`, select an item, or invoke `CleanupEngine`.
5. Add a local on-device model provider where supported, then an optional remote provider only after the UI shows exactly what metadata would leave the Mac.
6. Add signed release, notarization, privacy disclosure, and tests for Full Disk Access denial and partial scan results.
