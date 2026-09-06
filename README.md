# Scrub99

I made Scrub99 because I kept having the same slightly ridiculous problem on my Mac: tens of gigabytes would disappear into Claude projects, local AI models, Hugging Face caches, Python environments, logs, and application folders, and I could never quite tell what was genuinely needed, what could be recreated, and what would be a terrible idea to delete. One of my own Claude folders was tens of gigabytes. The usual storage tools could tell me that a folder was large, of course, but “large” is not the same thing as unnecessary.

Scrub99 is my attempt to make that whole business legible. It scans a defined set of places used by Claude, ChatGPT, Goose, Ollama, Hugging Face, LM Studio, pip, and uv, measures what is actually there, and then shows each result as something you can click and inspect. You can sort by size, category, item, or safety status. For each item, the app tries to answer the questions I wanted answered myself: what is this, why is it here, is it normally necessary, and what is the actual risk if I move it?

I also did not want to make one of those cleaners that announces that it has found “47 GB OF JUNK” in alarming red letters and then expects you to trust a single enormous Clean button. Scrub99 deliberately slows the process down. Nothing is selected automatically. Most personal data is inspection-only. When something genuinely low-risk is eligible for cleanup, you still review it one item at a time, read the explanation again, and decide whether to keep it or move it into Scrub99's reversible quarantine. The app does not permanently delete it.

The interface looks like an old Mac utility because I miss the peculiar honesty of those applications: they showed you files, paths, sizes, and consequences. They did not pretend the computer possessed mystical knowledge. The retro icon is original too, with a platinum storage drawer, blue inspection lens, broom, and caution badge.

[Download Scrub99 0.2.6](https://github.com/aghamorad/Scrub99/releases/tag/v0.2.6)

## What you actually do with it

1. Open Scrub99 and start a scan.
2. Sort the results, usually by size, and click any row that looks interesting.
3. Read the full path, measured size, what the item belongs to, why it exists, and the app's safety judgment.
4. Tick only the things you genuinely want to review for cleanup.
5. Use **Clean Up Unnecessary Stuff…** to go through eligible low-risk caches and logs individually. Scrub99 asks again before each move.
6. If you change your mind, use **Undo Last Quarantine**. Restore will refuse to overwrite anything already occupying the original path.

## What this version can and cannot claim

Scrub99 0.2.6 is an early safety milestone. It performs a local, rule-backed audit of known application locations; it does not claim to understand every file on your Mac, and it does not infer that two large model files are duplicates merely because their names look similar. Some folders may also be inaccessible because of macOS permissions.

There is no connected AI model in this release. That part comes later, if it can be added without handing an LLM the authority to quietly expand what counts as safe or move files by itself. The scanner, path-safety rules, quarantine records, explanations, and restore tests came first because, honestly, a cleanup app has to earn trust at the boring filesystem level before its “AI” opinions mean very much.

The downloadable build is for Apple-silicon Macs running macOS 13 or later. It is ad-hoc signed for local use and has not been Apple-notarized, so macOS may warn you when you first open it. The source is here for anyone who would prefer to inspect and build it themselves.

## What it looks for

AI and development applications can leave substantial material in several different places:

- **Downloaded models:** model weights that may take many gigabytes and may be expensive to download again
- **Model caches:** shared stores such as `~/.cache/huggingface`
- **Python environments:** Python installations and libraries created for particular tools or projects
- **Application data:** databases, preferences, histories, logs, and caches, which do not all carry the same risk
- **Orphaned remnants:** support data that can remain after the visible `.app` bundle is removed

Dragging an application to the Trash usually removes its `.app` bundle. It does not necessarily remove the models, caches, environments, or project data that application created elsewhere. Scrub99 audits the locations covered by its rule database and tells you what it can establish from local evidence; when it cannot establish enough, it says so and leaves the item alone.

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

- **Nothing is permanently deleted:** eligible items go only to Scrub99 Quarantine
- **Nothing is auto-selected:** the user must select every eligible cache or log
- **User data is never automatically removed:** conversations, credentials, projects are always unchecked
- **Undo is recorded before the first move:** append-only manifests retain every cleanup transaction
- **Running app detection:** refuses to clean live application data
- **Conservative defaults:** false negatives are preferred over false positives

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

- `claude.json`: Claude by Anthropic
- `ollama.json`: Ollama
- `goose.json`: Goose by Block
- `chatgpt.json`: ChatGPT by OpenAI
- `huggingface.json`: Hugging Face shared cache
- `lmstudio.json`: LM Studio
- `pipcache.json`: pip package cache
- `uv.json`: uv package cache

Each rule defines:
- Known paths (relative to standard locations)
- File patterns to match
- Keywords for heuristic matching
- Confidence boosters

Adding a new application is as simple as adding a JSON file.

## Building

**Scrub99 requires Xcode to build.** The Xcode license must be accepted on the Mac before `xcodebuild` will run.

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

The Mac OS 9 interface is a deliberate choice. Utilities such as Norton Utilities, StuffIt, and ResEdit were honest about what they found and conservative about what they changed. Scrub99 follows that tradition:

- **Explain what you find:** say "3 downloaded language models" instead of "5 GB of junk"
- **Explain what you do:** say "removed Ollama model, freed 8.2 GB" instead of "cleanup complete"
- **Never delete by default:** no result is pre-selected, including caches and logs
- **Always reversible:** eligible cleanup goes to recoverable quarantine, and restore refuses to overwrite an existing path

## Version

**Scrub99 0.3.0:** Safety milestone with bounded scanning, protected workspace inventory, reversible quarantine, visible quarantine management, item explanations, full-row inspection, sortable results, and reliable Dock reopening

Supported AI applications: Claude, ChatGPT, Goose, Ollama, HuggingFace, LM Studio

Extensible via JSON rule files.
