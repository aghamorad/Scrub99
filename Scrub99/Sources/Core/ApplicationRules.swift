// Scrub99 — Application Rules
// Extensible rule definitions for discovering application-related files

import Foundation

// MARK: - Rule Definitions

/// A rule that maps an application to known file paths and metadata.
struct ApplicationRule: Codable {
    let name: String
    let bundleIdentifier: String?
    let executableName: String?

    // Known storage locations (with ~ expansion)
    let knownPaths: [KnownPath]

    // File patterns to match (glob-like)
    let filePatterns: [FilePattern]

    // Keywords found in filenames or paths
    let keywords: [String]

    // Confidence boosters (what evidence makes us more confident?)
    let confidenceBoosters: [ConfidenceBooster]

    // Whether this app is likely installed via Mac App Store, Homebrew, or direct download
    let installMethod: InstallMethod?

    // URLs for documentation
    let documentationURL: String?
    let homepageURL: String?

    // Additional metadata
    let category: AppCategory
    let description: String

    init(
        name: String,
        bundleIdentifier: String? = nil,
        executableName: String? = nil,
        knownPaths: [KnownPath] = [],
        filePatterns: [FilePattern] = [],
        keywords: [String] = [],
        confidenceBoosters: [ConfidenceBooster] = [],
        installMethod: InstallMethod? = nil,
        documentationURL: String? = nil,
        homepageURL: String? = nil,
        category: AppCategory = .ai,
        description: String = ""
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.knownPaths = knownPaths
        self.filePatterns = filePatterns
        self.keywords = keywords
        self.confidenceBoosters = confidenceBoosters
        self.installMethod = installMethod
        self.documentationURL = documentationURL
        self.homepageURL = homepageURL
        self.category = category
        self.description = description
    }
}

/// A path pattern relative to a known location.
struct KnownPath: Codable {
    let relativePath: String
    let category: ItemCategory
    let description: String
    /// When set to 1, report each immediate child as its own inventory item.
    /// This is intended for user workspaces where a single aggregate total is
    /// accurate but not useful enough to review.
    let inventoryDepth: Int?

    init(
        relativePath: String,
        category: ItemCategory,
        description: String,
        inventoryDepth: Int? = nil
    ) {
        self.relativePath = relativePath
        self.category = category
        self.description = description
        self.inventoryDepth = inventoryDepth
    }

    /// Expand a relative path to a full URL.
    func expand(to parent: URL) -> URL {
        parent.appendingPathComponent(relativePath)
    }
}

/// A file pattern to match during scanning.
struct FilePattern: Codable {
    let pattern: String      // glob pattern like "*.gguf"
    let directory: String?   // optional subdirectory to search
    let category: ItemCategory
    let description: String

    /// Check if a filename matches this pattern.
    func matches(_ filename: String) -> Bool {
        let glob = GlobMatcher(pattern: pattern)
        return glob.matches(filename)
    }
}

/// Evidence that boosts our confidence in a match.
enum ConfidenceBooster: String, Codable {
    case bundleIdMatch         // Path contains the bundle identifier
    case appNameMatch          // Path contains the app name
    case executableMatch       // Path contains the executable name
    case plistFile             // Contains a .plist with the bundle ID
    case appReceipt            // Found in /Application Support receipts
    case launchAgent           // Has a LaunchAgent
    case sharedFrameworks      // Shares frameworks with known apps
}

/// How the application was likely installed.
enum InstallMethod: String, Codable {
    case directDownload
    case homebrew
    case macAppStore
    case pip
    case gitClone
}

/// Application category for grouping.
enum AppCategory: String, Codable {
    case ai
    case productivity
    case development
    case creative
    case system
    case communication
    case other
}
