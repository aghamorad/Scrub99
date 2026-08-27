import Foundation

/// A deterministic ceiling on cleanup. Advisory systems may make a result more
/// conservative, but they cannot make a blocked path eligible.
struct CleanupSafetyPolicy {
    enum Decision: String, Codable {
        case eligibleForQuarantine
        case reviewOnly
        case blocked
    }

    struct Assessment: Equatable {
        let decision: Decision
        let reason: String

        var isEligible: Bool { decision == .eligibleForQuarantine }
        var canBeSelected: Bool { decision != .blocked }
        var requiresProtectedConfirmation: Bool { decision == .reviewOnly }
    }

    let homeDirectory: URL
    let quarantineRoot: URL

    init(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()), quarantineRoot: URL? = nil) {
        let home = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.homeDirectory = home
        self.quarantineRoot = (quarantineRoot ?? home
            .appendingPathComponent("Library/Application Support/Scrub99/Quarantine", isDirectory: true))
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    func assess(_ item: FoundItem, fileManager: FileManager = .default) -> Assessment {
        guard item.path.isFileURL else {
            return Assessment(decision: .blocked, reason: "Only local file paths can be quarantined.")
        }

        let source = item.path.standardizedFileURL.resolvingSymlinksInPath()
        guard source != homeDirectory, isDescendant(source, of: homeDirectory) else {
            return Assessment(decision: .blocked, reason: "The path is outside the current user's home folder or is the home folder itself.")
        }
        guard !isDescendant(source, of: quarantineRoot), source != quarantineRoot else {
            return Assessment(decision: .blocked, reason: "Scrub99 cannot quarantine its own quarantine records.")
        }
        guard fileManager.fileExists(atPath: source.path) else {
            return Assessment(decision: .blocked, reason: "The item no longer exists at the scanned path.")
        }

        let isSymbolicLink = (try? item.path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        guard !item.isSymlink, !isSymbolicLink, source == item.path.standardizedFileURL else {
            return Assessment(decision: .blocked, reason: "Symbolic links and paths traversing symbolic links are never cleanup targets.")
        }

        guard !isNeverQuarantinablePath(source) else {
            return Assessment(decision: .blocked, reason: "Credential, cloud, communications, and photo-library paths cannot be quarantined by Scrub99.")
        }

        if isGuardedRoot(source) {
            return Assessment(decision: .blocked, reason: "Scrub99 will not move an entire standard user or workspace root.")
        }

        if isInsideGuardedUserPath(source) {
            return Assessment(
                decision: .reviewOnly,
                reason: "This is protected user data. It can enter reversible quarantine only after the additional typed confirmation."
            )
        }

        guard item.category == .cache || item.category == .logs else {
            return Assessment(
                decision: .reviewOnly,
                reason: "This is not disposable cache or log data. It can enter reversible quarantine only after the additional typed confirmation."
            )
        }
        guard item.safetyLevel == .safeToReplace || item.safetyLevel == .usuallySafe else {
            return Assessment(decision: .blocked, reason: "The scan did not establish a safe-to-recreate classification.")
        }
        guard item.association == .confirmed || item.association == .veryLikely else {
            return Assessment(decision: .blocked, reason: "The owning application was not identified with sufficient confidence.")
        }
        guard isInsideAllowedDisposableRoot(source, category: item.category) else {
            return Assessment(decision: .blocked, reason: "The path is not inside an approved cache or log root.")
        }

        return Assessment(decision: .eligibleForQuarantine, reason: "Eligible for explicit, reversible quarantine.")
    }

    func isRecommendedForGuidedCleanup(
        _ item: FoundItem,
        fileManager: FileManager = .default
    ) -> Bool {
        let assessment = assess(item, fileManager: fileManager)
        return assessment.isEligible &&
            (item.category == .cache || item.category == .logs) &&
            item.readerGuide.risk == .low
    }

    func preflight(
        _ items: [FoundItem],
        allowReviewOnly: Bool = false,
        fileManager: FileManager = .default
    ) throws -> [FoundItem] {
        guard !items.isEmpty else { return [] }

        var seen: Set<String> = []
        let ordered = items.sorted { $0.path.pathComponents.count < $1.path.pathComponents.count }

        for item in ordered {
            let source = item.path.standardizedFileURL.resolvingSymlinksInPath()
            let key = source.path
            guard seen.insert(key).inserted else {
                throw CleanupSafetyError.duplicatePath(source)
            }

            let assessment = assess(item, fileManager: fileManager)
            let approved = assessment.isEligible || (allowReviewOnly && assessment.decision == .reviewOnly)
            guard approved else {
                throw CleanupSafetyError.blockedPath(source, assessment.reason)
            }
        }

        for (index, parent) in ordered.enumerated() {
            let parentURL = parent.path.standardizedFileURL.resolvingSymlinksInPath()
            for child in ordered.dropFirst(index + 1) {
                let childURL = child.path.standardizedFileURL.resolvingSymlinksInPath()
                if isDescendant(childURL, of: parentURL) {
                    throw CleanupSafetyError.overlappingPaths(parentURL, childURL)
                }
            }
        }

        return ordered
    }

    private func isInsideAllowedDisposableRoot(_ source: URL, category: ItemCategory) -> Bool {
        let relativeRoots: [String]
        switch category {
        case .cache:
            relativeRoots = ["Library/Caches", ".cache"]
        case .logs:
            relativeRoots = ["Library/Logs"]
        default:
            return false
        }

        return relativeRoots.contains { relativePath in
            let root = homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            return source != root && isDescendant(source, of: root)
        }
    }

    private var guardedRelativePaths: [String] {
        [
            "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
            "Claude", "Goose", "Projects", "Developer", "Code"
        ]
    }

    private func isGuardedRoot(_ source: URL) -> Bool {
        guardedRelativePaths.contains { relativePath in
            source == homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        }
    }

    private func isInsideGuardedUserPath(_ source: URL) -> Bool {
        guardedRelativePaths.contains { relativePath in
            let root = homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            return isDescendant(source, of: root)
        }
    }

    private func isNeverQuarantinablePath(_ source: URL) -> Bool {
        let protectedRelativePaths = [
            ".ssh", ".gnupg", ".aws", ".kube",
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Safari",
            "Library/Mobile Documents", "Library/CloudStorage", "Library/Photos"
        ]

        return protectedRelativePaths.contains { relativePath in
            let root = homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            return source == root || isDescendant(source, of: root)
        }
    }

    private func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let parentComponents = parent.standardizedFileURL.pathComponents
        guard candidateComponents.count > parentComponents.count else { return false }
        return Array(candidateComponents.prefix(parentComponents.count)) == parentComponents
    }
}

enum CleanupSafetyError: LocalizedError {
    case blockedPath(URL, String)
    case duplicatePath(URL)
    case overlappingPaths(URL, URL)

    var errorDescription: String? {
        switch self {
        case .blockedPath(let url, let reason):
            return "Blocked cleanup target \(url.path): \(reason)"
        case .duplicatePath(let url):
            return "The cleanup request contains the same path more than once: \(url.path)"
        case .overlappingPaths(let parent, let child):
            return "The cleanup request contains overlapping paths: \(parent.path) and \(child.path)"
        }
    }
}
