// Scrub99 — Core Data Models
// Foundation types for the application

import Foundation

// MARK: - Scan Result

struct ScanResults {
    let scannedPaths: [URL]
    var foundItems: [FoundItem]
    let summary: Summary
    let scanDuration: TimeInterval
    let scanNotes: [ScanNote]  // Top-level type from Scanner module

    struct Summary {
        let totalSize: Int64
        let itemCount: Int
        let appsFound: [String: Int64]
        let remnantsFound: Int
        let sharedResourcesFound: Int
    }

    struct ScanNote {
        let phase: String
        let message: String

        static func findingPhase(_ message: String) -> ScanNote {
            ScanNote(phase: "🔍", message: message)
        }

        static func cautionPhase(_ message: String) -> ScanNote {
            ScanNote(phase: "⚠️", message: message)
        }
    }
}

// MARK: - Found Item (individual file/dir)

struct FoundItem: Identifiable, Codable, Equatable {
    let id: UUID
    let path: URL
    let size: Int64
    let modified: Date?
    let lastAccessed: Date?
    let isSymlink: Bool
    let resolvedPath: URL?

    // Classification
    var category: ItemCategory
    var safetyLevel: SafetyLevel
    var association: Association

    // Application context
    let primaryApplication: ApplicationRef?
    let contributingApplications: [ApplicationRef]

    // Metadata
    let reason: String?
    let explanation: String?
    var tags: [Tag]

    /// True when the sweep measured this path but no rule in the database
    /// describes it. Such an item can be reported and inspected, but nothing
    /// states what it contains or whether it can be recreated, so it is never
    /// eligible for one-click quarantine.
    var isUndeclared: Bool

    // Selection state
    var isSelected: Bool
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        path: URL,
        size: Int64,
        modified: Date? = nil,
        lastAccessed: Date? = nil,
        isSymlink: Bool = false,
        resolvedPath: URL? = nil,
        category: ItemCategory,
        safetyLevel: SafetyLevel,
        association: Association,
        primaryApplication: ApplicationRef? = nil,
        contributingApplications: [ApplicationRef] = [],
        reason: String? = nil,
        explanation: String? = nil,
        tags: [Tag] = [],
        isUndeclared: Bool = false,
        isSelected: Bool = false,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.modified = modified
        self.lastAccessed = lastAccessed
        self.isSymlink = isSymlink
        self.resolvedPath = resolvedPath
        self.category = category
        self.safetyLevel = safetyLevel
        self.association = association
        self.primaryApplication = primaryApplication
        self.contributingApplications = contributingApplications
        self.reason = reason
        self.explanation = explanation
        self.tags = tags
        self.isUndeclared = isUndeclared
        self.isSelected = isSelected
        self.isExpanded = isExpanded
    }

    // Convenience: is this item part of a larger group?
    var isGroupItem: Bool {
        category == .shared
    }
}

// MARK: - Item Category

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case cache
    case logs
    case downloadedModels
    case applicationData
    case preferences
    case conversationData
    case credentials
    case projectData
    case pythonEnvironment
    case shared
    case unknown

    var displayName: String {
        switch self {
        case .cache: return "Cache"
        case .logs: return "Logs"
        case .downloadedModels: return "Downloaded Models"
        case .applicationData: return "Application Data"
        case .preferences: return "Preferences"
        case .conversationData: return "Conversation / History Data"
        case .credentials: return "Credentials / API Configuration"
        case .projectData: return "Project Data"
        case .pythonEnvironment: return "Python Environment"
        case .shared: return "Shared Resource"
        case .unknown: return "Unknown"
        }
    }

    var id: String { rawValue }

    var description: String {
        switch self {
        case .cache:
            return "Cache — Temporary data an application keeps for faster access. Can be safely recreated."
        case .logs:
            return "Logs — Diagnostic and historical logging data. Normally safe to remove."
        case .downloadedModels:
            return "Model File — The actual language model used by a local AI application. Safe to remove, but downloading again may take considerable time."
        case .applicationData:
            return "Application Support — Data the application expects to survive between launches. May contain harmless generated files or potentially important databases."
        case .preferences:
            return "Preferences — Application settings and configuration. Small, may be useful if you reinstall."
        case .conversationData:
            return "Conversation Data — User conversations, prompts, and history. Valuable data that may be lost."
        case .credentials:
            return "Credentials — API keys, authentication data, and credentials. Very important to preserve."
        case .projectData:
            return "Project Data — User-created work, documents, or source code. Never delete automatically."
        case .pythonEnvironment:
            return "Python Environment — An isolated Python installation with libraries. Used by some AI applications. If the app is removed, this may be unnecessary."
        case .shared:
            return "Shared Resource — Used by multiple applications. Not automatically selected."
        case .unknown:
            return "Unknown — Scrub 99 cannot confidently classify this data. Manual review recommended."
        }
    }

    var isAutoSelectable: Bool {
        switch self {
        case .cache, .logs: return true
        case .downloadedModels: return false  // expensive to redownload
        case .preferences: return false  // may be useful
        case .applicationData: return false
        case .conversationData: return false
        case .credentials: return false
        case .projectData: return false
        case .pythonEnvironment: return false
        case .shared: return false
        case .unknown: return false
        }
    }
}

// MARK: - Safety Level

enum SafetyLevel: String, Codable, CaseIterable, Identifiable {
    case safeToReplace = "Safe to Replace"
    case usuallySafe = "Usually Safe"
    case reviewFirst = "Review First"
    case userDataType = "User Data"
    case sharedResource = "Shared Resource"
    case doNotAutoSelect = "Do Not Auto-Select"
    case unknown = "Unknown"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .safeToReplace: return "⚪"
        case .usuallySafe: return "🟡"
        case .reviewFirst: return "🟠"
        case .userDataType: return "🔴"
        case .sharedResource: return "🔵"
        case .doNotAutoSelect: return "⛔"
        case .unknown: return "❓"
        }
    }

    var explanation: String {
        switch self {
        case .safeToReplace:
            return "This is temporary data that the application can recreate if needed. Removing it should not affect your documents, account, or settings."
        case .usuallySafe:
            return "This data is generally safe to remove, but the application may need to recreate it later."
        case .reviewFirst:
            return "This directory may contain application settings, history, or other persistent data. Removing it may reset the application."
        case .userDataType:
            return "This appears to be data you created or care about. Scrub 99 will never delete user data automatically."
        case .sharedResource:
            return "Multiple applications may rely on this directory. Removing it could affect more than one program."
        case .doNotAutoSelect:
            return "This is important data. Scrub 99 will not select it for cleanup without your explicit review."
        case .unknown:
            return "Scrub 99 cannot confidently classify this data. Please review it manually before deciding."
        }
    }
}

// MARK: - Association

enum Association: String, Codable, Identifiable {
    case confirmed = "Confirmed"
    case veryLikely = "Very Likely"
    case possible = "Possible"
    case shared = "Shared"
    case unknown = "Unknown"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .confirmed:
            return "The folder name, bundle identifier, and files inside all correspond to this application. Scrub 99 is confident in this association."
        case .veryLikely:
            return "The folder name, bundle identifier, and files inside correspond to this application, but Scrub 99 cannot prove that another program does not also use this directory."
        case .possible:
            return "Scrub 99 found evidence suggesting this may belong to the application, but the match is not certain. File types and directory names provide partial evidence."
        case .shared:
            return "Several programs may use this folder. Scrub 99 found evidence that multiple applications share this directory."
        case .unknown:
            return "Scrub 99 could not determine which application created this data, or found conflicting evidence."
        }
    }

    var color: String {
        switch self {
        case .confirmed: return "green"
        case .veryLikely: return "blue"
        case .possible: return "orange"
        case .shared: return "purple"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Application Reference

struct ApplicationRef: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let bundleIdentifier: String?
    let isInstalled: Bool
    let iconPath: URL?
    let version: String?
    let lastUsed: Date?

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String? = nil,
        isInstalled: Bool = true,
        iconPath: URL? = nil,
        version: String? = nil,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isInstalled = isInstalled
        self.iconPath = iconPath
        self.version = version
        self.lastUsed = lastUsed
    }
}

// MARK: - Tag

enum Tag: String, Codable, CaseIterable {
    case model = "Model"
    case weights = "Model Weights"
    case gguf = "GGUF"
    case safetensors = "Safetensors"
    case checkpoints = "Checkpoints"
    case python = "Python"
    case venv = "Virtual Environment"
    case pipCache = "pip Cache"
    case uvCache = "uv Cache"
    case ollamaModel = "Ollama Model"
    case huggingFace = "Hugging Face"
    case launcher = "Launcher"
    case helper = "Helper Process"
    case launchAgent = "LaunchAgent"
    case loginItem = "Login Item"
    case symlink = "Symlink"
    case container = "Sandbox Container"
    case largeFile = "Large File"
    case duplicate = "Possible Duplicate"
    case old = "Old"
    case unused = "Unused"

    var description: String {
        switch self {
        case .model: return "Model file"
        case .weights: return "Model weights"
        case .gguf: return "GGUF format model"
        case .safetensors: return "Safetensors format model"
        case .checkpoints: return "Training or inference checkpoint"
        case .python: return "Python-related"
        case .venv: return "Virtual environment"
        case .pipCache: return "pip package cache"
        case .uvCache: return "uv package cache"
        case .ollamaModel: return "Ollama model"
        case .huggingFace: return "Hugging Face cache"
        case .launcher: return "Application launcher"
        case .helper: return "Helper process"
        case .launchAgent: return "LaunchAgent"
        case .loginItem: return "Login item"
        case .symlink: return "Symbolic link"
        case .container: return "Sandbox container"
        case .largeFile: return "Large file"
        case .duplicate: return "Possible duplicate"
        case .old: return "Old file"
        case .unused: return "Appears unused"
        }
    }
}

// MARK: - Size Formatting

extension Int64 {
    var humanReadable: String {
        let bytes = Double(self)
        if bytes < 1024 {
            return "\(Int(bytes)) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
        }
    }

    /// The same size, except that nothing at all is not reported as "0 B".
    ///
    /// Zero is what the scanner leaves behind when it could not read a size, and
    /// printing "0 B" for a cache it failed to measure states something false.
    /// Saying so plainly is the point: an unmeasured item cannot be judged by
    /// its size, and the reader deserves to know which items those are.
    var sizeDescription: String {
        self == 0 ? "Not measured" : humanReadable
    }
}

// MARK: - When was this last used?

extension FoundItem {
    /// Past this age an item reads as a leftover rather than something in use.
    static let staleAfterDays = 180

    /// The best answer available to "when was this last used?".
    ///
    /// macOS keeps a separate access date, and it is the honest signal: it moves
    /// when something reads the file. But it is recorded lazily and sometimes not
    /// at all, so this falls back to the change date. `lastUsedIsRecorded` says
    /// which of the two the reader is being shown.
    var lastUsedDate: Date? { lastAccessed ?? modified }

    /// False when the date below came from the change date rather than a real
    /// access date, so the wording can say so instead of overstating it.
    var lastUsedIsRecorded: Bool { lastAccessed != nil }

    /// Whole days between the last use and today, nil when no date exists at all.
    var lastUsedDays: Int? {
        guard let date = lastUsedDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day
    }

    /// How long ago that was, in the words a person would actually use.
    var lastUsedDescription: String {
        guard let days = lastUsedDays else { return "never recorded" }
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 14 { return "last week" }
        if days < 31 { return "\(days / 7) weeks ago" }
        if days < 61 { return "last month" }
        if days < 365 { return "\(days / 30) months ago" }
        if days < 730 { return "over a year ago" }
        return "\(days / 365) years ago"
    }

    /// Whether this has sat untouched long enough to look abandoned.
    var lastUsedIsStale: Bool {
        guard let days = lastUsedDays else { return false }
        return days > Self.staleAfterDays
    }
}

// MARK: - Reader-facing explanation

struct FindingReaderGuide: Equatable {
    enum Risk: String {
        case low = "Low risk"
        case medium = "Medium risk"
        case high = "High risk"
        case unknown = "Unknown risk"
    }

    let whatItIs: String
    let whyItExists: String
    let necessity: String
    let risk: Risk
    let riskExplanation: String
}

extension FoundItem {
    var readerGuide: FindingReaderGuide {
        let name = path.lastPathComponent.lowercased()
        let components = path.pathComponents.map { $0.lowercased() }

        if name == ".git" {
            return FindingReaderGuide(
                whatItIs: "The Git repository database containing commit history, branches, tags, and repository configuration.",
                whyItExists: "Git creates it when a folder is initialized or cloned as a repository.",
                necessity: "Normally necessary. Keep it if you need version history, branches, or the ability to commit and synchronize normally.",
                risk: .high,
                riskExplanation: "Quarantining it leaves the visible files but removes their Git history and repository identity from the original folder."
            )
        }

        if name == "node_modules" {
            return FindingReaderGuide(
                whatItIs: "Downloaded JavaScript packages used to build or run this project.",
                whyItExists: "npm, pnpm, Yarn, or another package manager created it from the project's dependency declarations.",
                necessity: "Usually regenerable if package.json and the correct lockfile are intact. It is still necessary while developing or running the project locally.",
                risk: .medium,
                riskExplanation: "The project may stop building until dependencies are reinstalled. Reproduction can fail if the lockfile is missing, registries are unavailable, or local packages were modified."
            )
        }

        if name == ".venv" || name == "venv" || category == .pythonEnvironment {
            return FindingReaderGuide(
                whatItIs: "A project-specific Python installation and its downloaded libraries.",
                whyItExists: "Python tooling created it to isolate this project's dependencies from the rest of the Mac.",
                necessity: "Usually regenerable only when a reliable requirements or lock file exists. It is necessary to run the current environment without rebuilding it.",
                risk: .medium,
                riskExplanation: "Python commands for the project will fail until the environment is rebuilt, and an unrecorded dependency version may be difficult to reproduce."
            )
        }

        if [".next", "dist", "build", "deriveddata"].contains(name) {
            return FindingReaderGuide(
                whatItIs: "Generated build output produced from source files.",
                whyItExists: "A compiler, framework, or IDE created it to run, preview, test, or package the project.",
                necessity: "Usually regenerable from intact source code and dependencies. It may still be needed for an immediate deployment or offline build.",
                risk: .low,
                riskExplanation: "The next build may be slower or fail if the original toolchain and dependencies are no longer available. Source files should be unaffected."
            )
        }

        if name == "out" {
            return FindingReaderGuide(
                whatItIs: "An output directory. It commonly contains generated builds, exports, reports, or model results.",
                whyItExists: "A project script or application wrote completed output here.",
                necessity: "Uncertain. Some `out` folders are reproducible build products; others contain the only exported copy of valuable work.",
                risk: .high,
                riskExplanation: "Do not assume this is a cache. Inspect its contents or confirm another copy exists before quarantining it."
            )
        }

        if components.contains(".claude") && name == "projects" {
            return FindingReaderGuide(
                whatItIs: "Claude Code's per-project session records and local working context, not the project source folders themselves.",
                whyItExists: "Claude Code stores session continuity and project-associated history here.",
                necessity: "Not required for the source code to exist, but necessary if you want those local Claude sessions and their continuity.",
                risk: .high,
                riskExplanation: "Quarantining it can make prior Claude Code sessions and local project context unavailable until restored."
            )
        }

        switch category {
        case .cache:
            return FindingReaderGuide(
                whatItIs: "Temporary copies kept to make an application faster.",
                whyItExists: "The associated application stores downloaded, decoded, or computed data here so it does not have to recreate it each time.",
                necessity: "Usually unnecessary for long-term preservation and normally regenerable.",
                risk: .low,
                riskExplanation: "The application may start more slowly, redownload data, or rebuild indexes. A misclassified cache could still contain local-only state, so verify the exact path."
            )
        case .logs:
            return FindingReaderGuide(
                whatItIs: "Diagnostic records describing what an application has done or what errors occurred.",
                whyItExists: "Applications write logs for troubleshooting, auditing, and crash investigation.",
                necessity: "Usually unnecessary for normal operation, but useful while diagnosing a current problem.",
                risk: .low,
                riskExplanation: "The application should continue working, but historical evidence useful for troubleshooting will be unavailable until restored."
            )
        case .downloadedModels:
            return FindingReaderGuide(
                whatItIs: "Downloaded AI model weights or related model assets.",
                whyItExists: "A local AI tool downloaded it so inference can run without fetching the model again.",
                necessity: "Necessary only if you still use this model locally. It is often replaceable by another download.",
                risk: .medium,
                riskExplanation: "The model will stop working locally until restored or downloaded again. Redownloading may be slow, costly, or impossible if the original version disappeared."
            )
        case .applicationData:
            return FindingReaderGuide(
                whatItIs: "Persistent data maintained by the associated application. It may include databases, indexes, sessions, extensions, or configuration.",
                whyItExists: "The application uses it to preserve state between launches.",
                necessity: "Potentially necessary. Its importance depends on whether the application is still used and whether the data exists elsewhere.",
                risk: .high,
                riskExplanation: "Quarantining it may reset the application, hide history, disable extensions, or require setup again. Inspect the exact folder before proceeding."
            )
        case .preferences:
            return FindingReaderGuide(
                whatItIs: "A preferences file containing application settings.",
                whyItExists: "macOS or the application created it when settings were changed.",
                necessity: "Not usually required for the application to launch, but necessary to preserve the current configuration.",
                risk: .medium,
                riskExplanation: "The application may return to defaults and lose customized behavior until the file is restored."
            )
        case .conversationData:
            return FindingReaderGuide(
                whatItIs: "Locally stored conversations, prompts, responses, or session history.",
                whyItExists: "The application keeps it for history, search, continuity, or offline access.",
                necessity: "Necessary if the local history matters or is not synchronized elsewhere.",
                risk: .high,
                riskExplanation: "Conversation history may disappear from the application. A remote account is not proof that every local record is synchronized."
            )
        case .credentials:
            return FindingReaderGuide(
                whatItIs: "Authentication or secret configuration such as tokens, keys, or account credentials.",
                whyItExists: "The application uses it to authenticate without asking you to sign in for every operation.",
                necessity: "Usually necessary for authenticated features.",
                risk: .high,
                riskExplanation: "Removing it can sign you out or make services inaccessible. Scrub 99 blocks known credential locations from quarantine."
            )
        case .projectData:
            return FindingReaderGuide(
                whatItIs: "A user-created project or workspace that may contain source code, documents, datasets, local environments, and generated output.",
                whyItExists: "You or a development tool created it as a working location, rather than as disposable application housekeeping.",
                necessity: "Assume it is necessary unless you know the project is abandoned or have independently verified another complete copy.",
                risk: .high,
                riskExplanation: "Quarantining it removes the entire project from its original path. Editors, Git tools, scripts, and automation using that path will stop finding it until restored."
            )
        case .pythonEnvironment:
            return FindingReaderGuide(
                whatItIs: "An isolated Python environment and its installed packages.",
                whyItExists: "Python tooling created it to reproduce a particular application's dependency set.",
                necessity: "Conditionally necessary and only reliably regenerable from complete dependency records.",
                risk: .medium,
                riskExplanation: "The related tool may stop running until the environment is rebuilt. Exact versions may be difficult to reproduce."
            )
        case .shared:
            return FindingReaderGuide(
                whatItIs: "Data potentially used by more than one application or project.",
                whyItExists: "Shared caches and package stores avoid downloading or storing the same material repeatedly.",
                necessity: "Uncertain. It may be unused, or several active tools may depend on it.",
                risk: .high,
                riskExplanation: "Quarantining it can affect multiple applications and may trigger large downloads or rebuilds. Confirm consumers before proceeding."
            )
        case .unknown:
            return FindingReaderGuide(
                whatItIs: "A path Scrub 99 could inventory but could not classify reliably.",
                whyItExists: "The available rule and filesystem evidence do not establish its purpose.",
                necessity: "Unknown. Treat it as necessary until you identify its owner and contents.",
                risk: .unknown,
                riskExplanation: "The consequences cannot be predicted from the current evidence. Inspect it manually and keep an independent backup."
            )
        }
    }
}

// MARK: - Path display

extension URL {
    /// `/Users/Morad/Library/Logs` becomes `~/Library/Logs`. A path outside the
    /// home directory is returned unchanged.
    ///
    /// Every row in the list lives under the same home directory, so that prefix
    /// says nothing about any one of them — and it is the part that gets dropped
    /// first when a long path is cut short to fit. Removing it is what lets the
    /// part that actually differs between two rows survive.
    var homeAbbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let full = path
        guard full == home || full.hasPrefix(home + "/") else { return full }
        return "~" + full.dropFirst(home.count)
    }
}
