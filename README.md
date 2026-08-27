# Scrub 99

**Find leftovers from apps you no longer use.**

A native macOS utility with a Mac OS 9-inspired interface that discovers, classifies, and safely removes leftover application data — with a special focus on the messy AI/ML ecosystem (Claude, Ollama, HuggingFace, LM Studio, Goose, etc.).

The app uses an original retro utility icon: a platinum storage drawer, blue inspection lens, broom, and caution badge, supplied as a multi-resolution macOS ICNS resource.

## Current implementation status

Scrub99 is an early safety milestone, not a finished cleaner. The current app performs a local, rule-backed audit of known application locations. Nothing is selected automatically. Only cache and log roots with a confirmed or very-likely application association can be moved, and only to Scrub99's reversible quarantine after explicit selection and confirmation. Direct Trash cleanup is disabled.

The AI advisory provider is not connected yet. The deterministic scanner, path-safety policy, quarantine transaction log, and restore tests are intentionally in place first. A future model may explain and rank findings, but it will not be allowed to broaden cleanup eligibility or initiate a move.

## Why Scrub 99?

AI applications are notorious for leaving massive amounts of data scattered across your Mac:

- **Downloaded models** — 5-40 GB each, often duplicated across tools
- **Model caches** — shared directories like `~/.cache/huggingface`
- **Python environments** — full Python installs with libraries
- **Application data** — databases, preferences, logs, caches
- **Orphaned remnants** — data left behind when you delete the app itself

Dragging an app to the Trash removes the `.app` bundle. It does **not** remove the 14 GB of models it downloaded.

Scrub 99 finds all of that.

## Features

### Discovery

- Audits exact `~/Library` and dot-directory roots declared in the bundled rule database
- Measures each matched root once, without recursively walking the entire home directory
- Detects installed vs. uninstalled applications
- Identifies shared resources (HuggingFace cache, pip cache, uv cache)
- Reports the measured size of known model and cache roots without inferring duplicate files from names

### Classification

Every discovered item is classified into categories:

| Category | Description | Auto-selects |
|---|---|---|
| **Cache** | Temporary data, safe to recreate | ❌ |
| **Logs** | Diagnostic/historical logging | ❌ |
| **Downloaded Models** | AI model weights (expensive to replace) | ❌ |
| **Application Data** | Database files, persistent data | ❌ |
| **Preferences** | Settings and configuration | ❌ |
| **Conversation / History** | User conversations, prompts | ❌ |
| **Credentials** | API keys, authentication data | ❌ |
| **Project Data** | User-created work | ❌ |
| **Python Environment** | Isolated Python + libraries | ❌ |
| **Shared Resource** | Used by multiple apps | ❌ |
| **Unknown** | Cannot classify with confidence | ❌ |

### Safety

- **Nothing is permanently deleted** — eligible items go only to Scrub99 Quarantine
- **Nothing is auto-selected** — the user must select every eligible cache or log
- **User data is never automatically removed** — conversations, credentials, projects are always unchecked
- **Undo is recorded before the first move** — append-only manifests retain every cleanup transaction
- **Running app detection** — refuses to clean live application data
- **Conservative defaults** — false negatives are preferred over false positives

### Architecture

```
Scrub99/Sources/
├── Scrub99App.swift       App entry point
├── AppDelegate.swift      macOS lifecycle and app menu
├── AppState.swift         Scan, inspection, and cleanup state
├── Core/             Data models & rule system
│   ├── Models.swift         All data types (FoundItem, Category, SafetyLevel, etc.)
│   ├── ApplicationRules.swift Rule definition format (JSON rules)
│   ├── RuleEngine.swift     Rule loading & matching
│   └── GlobMatcher.swift    Pattern matching
│
├── Scanner/
│   ├── BoundedScanner.swift Active rule-backed scanner
│   ├── ScanModels.swift     Progress and error types
│
├── Classifier/
│   └── Classifier.swift     Categorizes items by:
│                            - Category (cache, model, logs, etc.)
│                            - Safety level (safe, review, user data, etc.)
│                            - Association confidence (confirmed, likely, etc.)
│
├── Cleanup/
│   ├── SafetyPolicy.swift       Deterministic path and category gate
│   ├── SafeCleanupEngine.swift  Transactional quarantine and no-overwrite restore
│   ├── CleanupModels.swift      Cleanup and restore record types
│
└── UI/
    ├── ContentView.swift       Main navigation (Welcome → Scan → Results)
    ├── ResultsSorting.swift    Stable grouped column sorting
    ├── RetroStyles.swift       Mac OS 9 visual system
    ├── CleanupView.swift       Cleanup confirmation
    └── SettingsView.swift      Preferences
```

## Rule Database

Applications are defined in JSON files under `Resources/Rules/`:

- `claude.json` — Claude by Anthropic
- `ollama.json` — Ollama
- `goose.json` — Goose by Block
- `chatgpt.json` — ChatGPT by OpenAI
- `huggingface.json` — Hugging Face shared cache
- `lmstudio.json` — LM Studio
- `pipcache.json` — pip package cache
- `uv.json` — uv package cache

Each rule defines:
- Known paths (relative to standard locations)
- File patterns to match
- Keywords for heuristic matching
- Confidence boosters

Adding a new application is as simple as adding a JSON file.

## Building

**Scrub 99 requires Xcode to build.** The Xcode license must be accepted on the Mac before `xcodebuild` will run.

1. Open `Scrub99.xcodeproj` in Xcode
2. Select the `Scrub99` target
3. Choose your development team (or "Sign to Run Locally")
4. Press ⌘B to build

Or use the project-local workflow:

```bash
./script/typecheck.sh
./script/test_safety.sh
./script/build_and_run.sh --verify
```

To produce a local Apple-silicon app bundle and ZIP without invoking `xcodebuild`:

```bash
./script/package_release.sh /path/to/output-directory
```

The package is ad-hoc signed for local use. It is not Developer ID signed or notarized.

### Without Xcode

Command-line tools alone cannot build SwiftUI apps (SwiftUI macros require Xcode's build system). However, you can verify that all Swift source files parse correctly:

```bash
# Verify core modules compile
for f in Scrub99/Sources/Core/*.swift Scrub99/Sources/Scanner/*.swift \
         Scrub99/Sources/Classifier/*.swift Scrub99/Sources/Cleanup/*.swift; do
  swiftc -parse "$f"
done

# Verify UI files parse
for f in Scrub99/Sources/UI/*.swift Scrub99/Sources/Scrub99App.swift \
         Scrub99/Sources/AppDelegate.swift Scrub99/Sources/AppState.swift; do
  swiftc -parse "$f"
done
```

All files in this project parse cleanly with Swift 6.4.

## Distribution

Distribution signing and notarization have not been completed. Scanning and classification are local, and no AI provider or telemetry endpoint is connected in this milestone.

## Design Philosophy

The Mac OS 9 interface is a deliberate choice. That era's utilities — Norton Utilities, StuffIt, ResEdit — were honest about what they found and conservative about what they changed. Scrub 99 follows that tradition:

- **Explain what you find** — not "5 GB of junk" but "3 downloaded language models"
- **Explain what you do** — not "cleanup complete" but "removed Ollama model, freed 8.2 GB"
- **Never delete by default** — no result is pre-selected, including caches and logs
- **Always reversible** — eligible cleanup goes to recoverable quarantine, and restore refuses to overwrite an existing path

## Version

**Scrub 99 0.2.6** — Safety milestone with bounded scanning, protected workspace inventory, reversible quarantine, item explanations, full-row inspection, and sortable results

Supported AI applications: Claude, ChatGPT, Goose, Ollama, HuggingFace, LM Studio

Extensible via JSON rule files.
