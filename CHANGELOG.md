# Scrub99 0.4.0

This release is about being able to tell Scrub99 what to leave alone, and about it refusing the things it should refuse without being told.

- Adds the left-alone list. Press **Leave It Alone** on any finding and that path stops being offered, on this scan and every later one, until it is taken off again. The list is a plain JSON file at `~/Library/Application Support/Scrub99/Protection.json`, readable in any text editor. Protecting a folder protects everything inside it. The list can only ever make Scrub99 more careful: nothing on it can make an unproven path eligible.
- Adds a working-copy guard, taken from [Mole](https://github.com/tw93/mole)'s purge step. Before any folder is offered, Scrub99 looks three levels inside it for a Git repository — including the `.git` file a worktree uses — a deployment key named or extended like one, or a credential file. A match refuses the folder whatever its name suggests, and the refusal names the file and where inside the folder it was found. The answer is memoised per path and re-read when a scan begins.
- Adds help text to every control that needed it, and gives the primary **Scan My Mac** button an explanation for the first time. Because `ThemeButton` routes help to the accessibility hint as well, these were VoiceOver gaps too.
- Ships a universal binary for Apple silicon and Intel, with separate downloads for each architecture alongside it.
- Documents four rule files that had been shipping undocumented (`chrome.json`, `codex.json`, `gapcode.json`, `gemini.json`), and corrects the architecture listing, which named a source file that never existed.
- Fixes `script/package_release.sh`, which had gone stale: it did not list `ProtectionList.swift` and so could no longer build the app at all, and it was arm64-only.
- Fixes two panels that drew a large blank box around a short list. A `ScrollView` claims all the height it is offered, so a one-item quarantine review and a one-line hidden-detail note each left an empty block under their content. Both now grow to their content and stop at a cap.
- Fixes the count in the quarantine review, which read “1 path(s)”.
- Writes the app's name as **Scrub 99** everywhere in its own prose, matching the title bar and the Info.plist display name. Earlier builds called themselves Scrub99 in about two dozen sentences while the window above them said Scrub 99. The quarantine folder and the Application Support directory keep their existing names, so nothing already quarantined is orphaned.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized.

# Scrub99 0.3.0

This release adds a phantom application audit for residue left behind after an application is removed.

- Checks user Application Support, Preferences, HTTP storage, Saved Application State, Group Containers, Caches, Logs, and LaunchAgents.
- Compares candidate namespaces with installed application bundles and bundle identifiers.
- Excludes Apple-owned, Scrub99, and known shared/system namespaces.
- Labels likely remnants with their exact path, measured size, reason, and review warning.
- Keeps persistent data, preferences, web storage, and launch agents review-only.
- Keeps low-risk orphan caches and logs compatible with the existing reversible quarantine workflow.
- Repairs the Xcode project’s invalid configuration-list references.

The distributed build is ad-hoc signed for local Apple-silicon use on macOS 13 or later. It is not notarized.
