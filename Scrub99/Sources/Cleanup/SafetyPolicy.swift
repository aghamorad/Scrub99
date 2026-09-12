import Foundation

/// A memo for the working-copy search, which is the only part of an assessment
/// that reads the disk more than once. A results row asks for its own assessment
/// on every redraw, so the walk has to be paid for once per path rather than once
/// per frame. Locked because the guided-cleanup queue is built off the main
/// thread.
private final class WorkingCopyMemo {
    private let lock = NSLock()
    private var refusals: [String: String?] = [:]

    func refusal(for path: String, compute: () -> String?) -> String? {
        lock.lock()
        if let known = refusals[path] {
            lock.unlock()
            return known
        }
        lock.unlock()

        let computed = compute()

        lock.lock()
        refusals[path] = computed
        lock.unlock()
        return computed
    }

    func removeAll() {
        lock.lock()
        refusals.removeAll()
        lock.unlock()
    }
}

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

    /// Paths the reader has told Scrub 99 to stop offering, already standardised.
    /// A value here rather than the list object itself, so the policy stays a pure
    /// function of its inputs and can be tested with a literal array. It is only
    /// ever consulted to refuse something, never to allow it.
    let protectedPaths: [URL]

    /// What the working-copy search found, kept because nothing else in an
    /// assessment looks inside a folder. Reference type on purpose: `assess` is
    /// non-mutating, and this is a cache rather than state.
    private let workingCopyMemo = WorkingCopyMemo()

    init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        quarantineRoot: URL? = nil,
        protectedPaths: [String] = []
    ) {
        let home = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.homeDirectory = home
        // The location is defined once, in CleanupEngine, so the policy that
        // guards quarantine and the engine that writes to it can never disagree
        // about where it is.
        self.quarantineRoot = (quarantineRoot ?? CleanupEngine.quarantineURL(homeDirectory: home))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        self.protectedPaths = protectedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath()
        }
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

        // The reader's own decision, stated first and reported as theirs. A path
        // they took off the table is refused for that reason even when Scrub 99
        // would have reached the same answer for one of its own.
        if let owner = protectingAncestor(of: source) {
            return Assessment(decision: .blocked, reason: protectionReason(owner: owner, source: source))
        }

        guard !isNeverQuarantinablePath(source) else {
            return Assessment(decision: .blocked, reason: "Credential, cloud, communications, and photo-library paths cannot be quarantined by Scrub99.")
        }

        if isGuardedRoot(source) {
            return Assessment(decision: .blocked, reason: "Scrub99 will not move an entire standard user or workspace root.")
        }

        // Checked here rather than earlier because it is the one question that
        // costs a directory listing, and later because nothing should be offered
        // until it has been answered. A folder that names itself a cache can still
        // be somebody's working copy, and removing it would take uncommitted work
        // with it — the size on screen says nothing about that.
        if let refusal = workingCopyRefusal(source, fileManager: fileManager) {
            return Assessment(decision: .blocked, reason: refusal)
        }

        if isInsideGuardedUserPath(source) {
            return Assessment(
                decision: .reviewOnly,
                reason: "This is protected user data. It can enter reversible quarantine only after the additional typed confirmation."
            )
        }

        // A swept path has no rule behind it. Even when its name and enclosing
        // folder look disposable, nothing in the database states what it is, so
        // Scrub99 reports it without ever offering it as a one-click decision.
        if item.isUndeclared {
            return Assessment(
                decision: .reviewOnly,
                reason: "No rule in Scrub99's database describes this path; it was found by sweeping the folders where undeclared data collects. It can enter reversible quarantine only after the additional typed confirmation."
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

        if relativeRoots.contains(where: { relativePath in
            let root = homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            return source != root && isDescendant(source, of: root)
        }) { return true }

        guard category == .cache else { return false }
        let exactCachePaths = [
            ".npm/_cacache", ".npm/_npx", ".bun/install/cache",
            ".cache/clang", ".cache/language_tool_python", ".cache/opencode",
            ".cache/yt-dlp", ".matplotlib", ".idlerc", ".zcompdump",
            ".wget-hsts", ".DS_Store"
        ]
        return exactCachePaths.contains { relativePath in
            let root = homeDirectory.appendingPathComponent(relativePath).standardizedFileURL
            return source == root || isDescendant(source, of: root)
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

    /// The protected path that covers this one, or nil. When a path is covered by
    /// more than one entry the nearest is returned, so the reason names the folder
    /// the reader is most likely thinking of rather than a broad one far above it.
    func protectingAncestor(of source: URL) -> URL? {
        protectedPaths
            .filter { $0 == source || isDescendant(source, of: $0) }
            .max { $0.pathComponents.count < $1.pathComponents.count }
    }

    func isProtected(_ source: URL) -> Bool {
        protectingAncestor(of: source) != nil
    }

    /// Says the decision was the reader's, names the entry responsible when the
    /// refusal came from a folder rather than the path itself, and says how to
    /// undo it — a refusal with no stated way out is just a locked door.
    private func protectionReason(owner: URL, source: URL) -> String {
        let ownerName = owner.lastPathComponent
        if owner == source {
            return "You asked Scrub 99 to leave this alone. It will keep leaving it alone, on this and every later scan, until you take it off the left-alone list."
        }
        return "You asked Scrub 99 to leave “\(ownerName)” alone, and this is inside it. Protecting a folder protects everything in it, until you take that folder off the left-alone list."
    }

    private func isNeverQuarantinablePath(_ source: URL) -> Bool {
        let protectedRelativePaths = [
            ".ssh", ".gnupg", ".aws", ".kube",
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Safari",
            "Library/Mobile Documents", "Library/CloudStorage", "Library/Photos",
            // Scrub 99's own records are not user data and must never be offered
            // as a cleanup target: the manifests in here are the only record of
            // where quarantined items came from.
            "Library/Application Support/Scrub99"
        ]

        return protectedRelativePaths.contains { relativePath in
            let root = homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            return source == root || isDescendant(source, of: root)
        }
    }

    /// How far into a folder Scrub 99 will look before giving up. Deep enough to
    /// find a project directory sitting inside a cache root, shallow enough that
    /// the answer still arrives while the row is being drawn.
    private static let workingCopySearchDepth = 3
    /// A ceiling on directory entries examined, so one enormous or looping tree
    /// cannot stall a scan. Reaching it means "not proved safe", and the caller
    /// treats that as ordinary eligibility rather than as a refusal — the search
    /// only ever adds refusals, never removes them.
    private static let workingCopySearchBudget = 1_500

    /// Names that mean a folder is not disposable whatever else is true of it.
    /// `.git` covers a repository, and also the `.git` *file* a worktree or
    /// submodule uses, which is why the check is by name and not by kind.
    private static let workingCopyNames: Set<String> = [
        ".git",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        ".netrc", "_netrc", ".htpasswd",
        "credentials", "credentials.json",
        "application_default_credentials.json", "service-account.json",
        ".npmrc", ".pypirc"
    ]

    /// Extensions that mean the same thing. Checked because a deployment key is
    /// usually named after the service it belongs to, not after itself.
    private static let workingCopyExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "ppk", "keystore", "jks", "mobileprovision"
    ]

    /// Mole's purge guard, restated for Scrub 99 in the terms it uses elsewhere:
    /// nothing here is about size or naming, only about what could be lost.
    private func workingCopyRefusal(_ source: URL, fileManager: FileManager) -> String? {
        workingCopyMemo.refusal(for: source.path) {
            if let marker = workingCopyMarker(named: source.lastPathComponent) {
                return "Scrub 99 will not quarantine \(marker). Git repositories, deployment keys, and credential files are refused by name, because a folder that holds one may be the only copy of it."
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            var budget = Self.workingCopySearchBudget
            guard let hit = firstWorkingCopyMarker(
                inside: source,
                root: source,
                depth: 0,
                budget: &budget,
                fileManager: fileManager
            ) else {
                return nil
            }

            return "Scrub 99 will not quarantine this folder: it contains \(hit.marker) at \(hit.relativePath) inside it. A folder can be a working copy whatever its name suggests, and the size of a folder says nothing about whether it is the only copy of something."
        }
    }

    /// The description to use for a path component, or nil when the name means
    /// nothing special. Returns prose rather than a flag so the refusal and the
    /// marker cannot drift apart.
    private func workingCopyMarker(named name: String) -> String? {
        if name == ".git" {
            return "a Git repository"
        }
        if Self.workingCopyNames.contains(name) {
            return "a credential file named “\(name)”"
        }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if !ext.isEmpty, Self.workingCopyExtensions.contains(ext) {
            return "a key file named “\(name)”"
        }
        return nil
    }

    /// Breadth-first-ish, shallowest-first by virtue of depth ordering, and it
    /// stops at the first match so the reason names the shallowest thing that
    /// explains the refusal. Children are walked in name order so the same folder
    /// gives the same explanation on every launch.
    private func firstWorkingCopyMarker(
        inside directory: URL,
        root: URL,
        depth: Int,
        budget: inout Int,
        fileManager: FileManager
    ) -> (marker: String, relativePath: String)? {
        guard depth < Self.workingCopySearchDepth, budget > 0 else { return nil }
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return nil
        }

        let rootComponents = root.pathComponents
        var subdirectories: [URL] = []

        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            budget -= 1
            guard budget > 0 else { return nil }

            let relativePath = child.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
            if let marker = workingCopyMarker(named: child.lastPathComponent) {
                return (marker, relativePath.isEmpty ? child.lastPathComponent : relativePath)
            }

            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            subdirectories.append(child)
        }

        for subdirectory in subdirectories {
            if let hit = firstWorkingCopyMarker(
                inside: subdirectory,
                root: root,
                depth: depth + 1,
                budget: &budget,
                fileManager: fileManager
            ) {
                return hit
            }
        }
        return nil
    }

    /// A scan is the moment the disk is re-read, so it is also the moment what
    /// the last one found out about the disk stops being true.
    func invalidateWorkingCopyMemo() {
        workingCopyMemo.removeAll()
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
