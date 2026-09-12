import Foundation

/// The paths the reader has told Scrub 99 to stop offering. It is the same idea
/// as Mole's whitelist, kept in a plain JSON file anyone can open and read rather
/// than in a preference only the app can see.
///
/// This list can only ever make Scrub 99 more careful. A protected path is
/// reported to `CleanupSafetyPolicy` as blocked, and blocked is the end of the
/// line — nothing here can make an unproven path eligible, or turn a refusal into
/// a cleanup.
final class ProtectionList {
    struct Entry: Codable, Identifiable, Equatable {
        /// The full path, already standardised and with symlinks resolved, so two
        /// spellings of the same place cannot sit in the list as two entries.
        let path: String
        /// What Scrub 99 called it when you protected it, kept so the list still
        /// says something useful about a path that is no longer there.
        let kind: String
        let added: Date

        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
        var displayPath: String { URL(fileURLWithPath: path).homeAbbreviatedPath }
        var stillExists: Bool { FileManager.default.fileExists(atPath: path) }
    }

    /// The file lives inside Scrub 99's own application-support folder, which the
    /// safety policy refuses to quarantine. The list that says what must be left
    /// alone is itself something Scrub 99 cannot touch.
    static func defaultFileURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Scrub99", isDirectory: true)
            .appendingPathComponent("Protection.json")
    }

    /// Mole's whitelist protects path patterns; this protects a path and, when
    /// that path is a folder, everything under it. Protecting a folder and then
    /// being offered its contents one by one would be the same conversation had
    /// over again, so the whole subtree is covered and the screen says so.
    private(set) var entries: [Entry] = []

    /// Set when an existing list could not be read. The file is then moved aside
    /// rather than overwritten, and the screen says where it went — a list of
    /// things to leave alone is exactly the thing not to quietly throw away.
    private(set) var loadFailureNote: String?

    /// Shared so the screen can show the reader exactly which file holds the list
    /// and let them open it. A list of what must not be touched is worth being
    /// able to read without the app.
    let fileURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL? = nil,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? ProtectionList.defaultFileURL(homeDirectory: homeDirectory)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    /// Whether a path is covered by the list, either directly or by a protected
    /// folder above it. Standardises and resolves first, so the answer does not
    /// depend on how the caller happened to spell the path.
    func isProtected(_ path: String) -> Bool {
        let candidate = Self.normalize(URL(fileURLWithPath: path))
        return entries.contains { entry in
            let protected = Self.normalize(URL(fileURLWithPath: entry.path))
            return candidate == protected || Self.isDescendant(candidate, of: protected)
        }
    }

    func isProtected(_ url: URL) -> Bool { isProtected(url.path) }

    /// Adds a path. Protecting somewhere already covered by the list, or already
    /// protected by a folder above it, changes nothing and returns false — so a
    /// second press cannot quietly restate a decision already made.
    @discardableResult
    func protect(path: String, kind: String, on date: Date = Date()) -> Bool {
        let normalized = Self.normalize(URL(fileURLWithPath: path)).path
        guard !isProtected(normalized) else { return false }
        entries.insert(Entry(path: normalized, kind: kind, added: date), at: 0)
        save()
        return true
    }

    /// Takes one entry off the list. Only the entry's own path is released; a
    /// folder protected in its own right stays protected when a deeper entry
    /// leaves, because the folder is still on the list.
    @discardableResult
    func release(path: String) -> Bool {
        let normalized = Self.normalize(URL(fileURLWithPath: path)).path
        guard let index = entries.firstIndex(where: { $0.path == normalized }) else { return false }
        entries.remove(at: index)
        save()
        return true
    }

    func releaseAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        save()
    }

    // MARK: - The file

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([Entry].self, from: data) else {
            let aside = fileURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            let moved = (try? fileManager.moveItem(at: fileURL, to: aside)) != nil
            loadFailureNote = moved
                ? "Scrub 99 could not read the left-alone list it found, so it set that file aside as \(aside.lastPathComponent) instead of overwriting it. Nothing on it was applied. You can open it in a text editor."
                : "Scrub 99 could not read the left-alone list it found, and could not set the file aside either. Nothing on it was applied."
            return
        }
        entries = decoded.sorted { $0.added > $1.added }
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Paths

    /// The same comparison the safety policy uses. Kept identical on purpose: if
    /// this list and the policy disagreed about whether two paths are the same
    /// place, the list would fail to stop exactly the cleanup it was made for.
    static func normalize(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let parentComponents = parent.standardizedFileURL.pathComponents
        guard candidateComponents.count > parentComponents.count else { return false }
        return Array(candidateComponents.prefix(parentComponents.count)) == parentComponents
    }
}
