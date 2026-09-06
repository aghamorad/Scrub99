import AppKit
import Foundation

/// The only mutating component used by the app. Every request is fully
/// preflighted before the first move, and every destination is recorded before
/// data leaves its original path.
final class CleanupEngine {
    let quarantineURL: URL

    private let fileManager: FileManager
    private let safetyPolicy: CleanupSafetyPolicy
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let appSupport = applicationSupportURL ?? homeDirectory
            .appendingPathComponent("Library/Application Support/Scrub99", isDirectory: true)
        self.quarantineURL = appSupport.appendingPathComponent("Quarantine", isDirectory: true)
        self.fileManager = fileManager
        self.safetyPolicy = CleanupSafetyPolicy(
            homeDirectory: homeDirectory,
            quarantineRoot: self.quarantineURL
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func assessment(for item: FoundItem) -> CleanupSafetyPolicy.Assessment {
        safetyPolicy.assess(item, fileManager: fileManager)
    }

    func cleanup(
        items: [FoundItem],
        useTrash: Bool = false,
        allowReviewOnly: Bool = false
    ) async throws -> CleanupResult {
        guard !useTrash else {
            throw CleanupError.trashError("Direct Trash cleanup is disabled in this safety release. Use reversible quarantine.")
        }
        guard !items.isEmpty else {
            return CleanupResult(
                date: Date(), movedItems: [], totalSize: 0,
                successCount: 0, failureCount: 0, usedTrash: false
            )
        }

        let approvedItems = try safetyPolicy.preflight(
            items,
            allowReviewOnly: allowReviewOnly,
            fileManager: fileManager
        )
        let runningApps = try await checkRunningApps(approvedItems)
        guard runningApps.isEmpty else {
            throw CleanupError.applicationsRunning(runningApps)
        }

        let recordID = UUID()
        let date = Date()
        let transactionURL = quarantineURL.appendingPathComponent(recordID.uuidString, isDirectory: true)
        let itemsURL = transactionURL.appendingPathComponent("Items", isDirectory: true)
        let manifestURL = transactionURL.appendingPathComponent("manifest.json", isDirectory: false)

        var manifest = DurableManifest(
            version: 3,
            id: recordID,
            date: date,
            createdAtUnixNanoseconds: Int64(date.timeIntervalSince1970 * 1_000_000_000),
            items: approvedItems.map { item in
                let destination = itemsURL
                    .appendingPathComponent(item.id.uuidString, isDirectory: true)
                    .appendingPathComponent(item.path.lastPathComponent, isDirectory: false)
                return DurableItem(
                    id: item.id,
                    originalPath: item.path.path,
                    quarantinePath: destination.path,
                    size: item.size,
                    category: item.category.displayName,
                    appName: item.primaryApplication?.name,
                    state: .planned,
                    errorMessage: nil
                )
            }
        )

        try fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        try save(manifest, to: manifestURL)

        var movedItems: [MovedItem] = []
        for index in manifest.items.indices {
            try Task.checkCancellation()
            let item = approvedItems[index]
            let destination = URL(fileURLWithPath: manifest.items[index].quarantinePath)

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw CleanupError.restoreError("Quarantine destination already exists: \(destination.path)")
                }
                try fileManager.moveItem(at: item.path, to: destination)
                manifest.items[index].state = .moved
                manifest.items[index].errorMessage = nil
                movedItems.append(.quarantine(item, destination))
            } catch {
                manifest.items[index].state = .failed
                manifest.items[index].errorMessage = error.localizedDescription
                movedItems.append(.failed(item, error.localizedDescription))
            }

            try save(manifest, to: manifestURL)
        }

        return CleanupResult(
            date: date,
            movedItems: movedItems,
            totalSize: movedItems.filter(\.success).reduce(0) { $0 + $1.size },
            successCount: movedItems.filter(\.success).count,
            failureCount: movedItems.filter(\.failed).count,
            usedTrash: false
        )
    }

    func undoLastCleanup() async throws -> RestoreResult {
        let (manifestURL, loadedManifest) = try loadLatestRestorableManifest()
        var manifest = loadedManifest
        var restoredItems: [RestoredItem] = []

        for index in manifest.items.indices {
            try Task.checkCancellation()
            guard manifest.items[index].state == .moved || manifest.items[index].state == .planned else {
                continue
            }

            let record = manifest.items[index]
            let source = URL(fileURLWithPath: record.quarantinePath)
            let destination = URL(fileURLWithPath: record.originalPath)
            let publicRecord = record.publicRecord

            guard fileManager.fileExists(atPath: source.path) else {
                manifest.items[index].errorMessage = "The quarantined item is missing."
                restoredItems.append(.failed(publicRecord, "The quarantined item is missing."))
                try save(manifest, to: manifestURL)
                continue
            }
            guard !fileManager.fileExists(atPath: destination.path) else {
                let message = "Restore refused because the original path now exists. Nothing was overwritten."
                manifest.items[index].errorMessage = message
                restoredItems.append(.failed(publicRecord, message))
                try save(manifest, to: manifestURL)
                continue
            }

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: source, to: destination)
                manifest.items[index].state = .restored
                manifest.items[index].errorMessage = nil
                restoredItems.append(.success(publicRecord))
            } catch {
                manifest.items[index].errorMessage = error.localizedDescription
                restoredItems.append(.failed(publicRecord, error.localizedDescription))
            }
            try save(manifest, to: manifestURL)
        }

        return RestoreResult(
            restoredItems: restoredItems,
            totalRestored: restoredItems.filter(\.success).count,
            totalSize: restoredItems.filter(\.success).reduce(0) { $0 + $1.size }
        )
    }

    func restoreItem(_ itemRecord: MovedItemRecord) async throws {
        guard let originalPath = itemRecord.originalPath,
              let quarantinePath = itemRecord.quarantinePath else {
            throw CleanupError.restoreError("Missing path information")
        }
        let source = URL(fileURLWithPath: quarantinePath)
        let destination = URL(fileURLWithPath: originalPath)
        guard fileManager.fileExists(atPath: source.path) else {
            throw CleanupError.restoreError("Item no longer exists in quarantine")
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw CleanupError.restoreError("Restore refused because the original path exists. Nothing was overwritten.")
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: source, to: destination)
    }

    func quarantineEntries() -> [QuarantineEntry] {
        guard let manifests = try? manifestURLs() else { return [] }
        return manifests.flatMap { manifestURL in
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(DurableManifest.self, from: data) else {
                return [QuarantineEntry]()
            }
            return manifest.items.compactMap { item in
                guard item.state == .moved,
                      fileManager.fileExists(atPath: item.quarantinePath) else { return nil }
                return QuarantineEntry(
                    id: item.id,
                    date: manifest.date,
                    originalPath: item.originalPath,
                    quarantinePath: item.quarantinePath,
                    size: item.size,
                    category: item.category,
                    appName: item.appName,
                    manifestURL: manifestURL
                )
            }
        }
        .sorted {
            if $0.date == $1.date { return $0.originalPath < $1.originalPath }
            return $0.date > $1.date
        }
    }

    func restore(_ entry: QuarantineEntry) throws {
        guard let loaded = loadManifest(containing: entry) else {
            throw CleanupError.restoreError("The quarantine record could not be found.")
        }
        let manifestURL = loaded.0
        var manifest = loaded.1
        guard
              let index = manifest.items.firstIndex(where: { $0.id == entry.id }) else {
            throw CleanupError.restoreError("The quarantine record could not be found.")
        }
        let source = URL(fileURLWithPath: manifest.items[index].quarantinePath)
        let destination = URL(fileURLWithPath: manifest.items[index].originalPath)
        guard fileManager.fileExists(atPath: source.path) else {
            throw CleanupError.restoreError("The quarantined item is missing.")
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw CleanupError.restoreError("Restore refused because the original path exists. Nothing was overwritten.")
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: source, to: destination)
        manifest.items[index].state = .restored
        manifest.items[index].errorMessage = nil
        try save(manifest, to: manifestURL)
    }

    func permanentlyDelete(_ entries: [QuarantineEntry]) throws -> PermanentDeletionResult {
        var deleted: [QuarantineEntry] = []
        var failed: [(QuarantineEntry, String)] = []
        for entry in entries {
            do {
                guard let loaded = loadManifest(containing: entry) else {
                    throw CleanupError.restoreError("The quarantine record could not be found.")
                }
                let manifestURL = loaded.0
                var manifest = loaded.1
                guard
                      let index = manifest.items.firstIndex(where: { $0.id == entry.id }) else {
                    throw CleanupError.restoreError("The quarantine record could not be found.")
                }
                let source = URL(fileURLWithPath: manifest.items[index].quarantinePath).standardizedFileURL
                let rootComponents = quarantineURL.standardizedFileURL.pathComponents
                guard source != quarantineURL.standardizedFileURL,
                      source.pathComponents.starts(with: rootComponents),
                      fileManager.fileExists(atPath: source.path) else {
                    throw CleanupError.restoreError("The quarantined item is missing or outside Scrub99 Quarantine.")
                }
                try fileManager.removeItem(at: source)
                manifest.items[index].state = .purged
                manifest.items[index].errorMessage = nil
                try save(manifest, to: manifestURL)
                deleted.append(entry)
            } catch {
                failed.append((entry, error.localizedDescription))
            }
        }
        return PermanentDeletionResult(deleted: deleted, failed: failed)
    }

    func revealQuarantine() {
        NSWorkspace.shared.activateFileViewerSelecting([quarantineURL])
    }

    private func loadManifest(containing entry: QuarantineEntry) -> (URL, DurableManifest)? {
        guard let data = try? Data(contentsOf: entry.manifestURL),
              let manifest = try? decoder.decode(DurableManifest.self, from: data) else { return nil }
        return (entry.manifestURL, manifest)
    }

    internal func checkRunningApps(_ items: [FoundItem]) async throws -> [ApplicationRef] {
        let running = NSWorkspace.shared.runningApplications
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        var matches: Set<ApplicationRef> = []

        for app in items.compactMap(\.primaryApplication) {
            if let bundleIdentifier = app.bundleIdentifier, runningIDs.contains(bundleIdentifier) {
                matches.insert(app)
            } else if running.contains(where: {
                $0.localizedName?.localizedCaseInsensitiveContains(app.name) == true
            }) {
                matches.insert(app)
            }
        }
        return matches.sorted { $0.name < $1.name }
    }

    var hasQuarantineItems: Bool {
        (try? allManifests().contains { manifest in
            manifest.items.contains { item in
                item.state == .moved &&
                fileManager.fileExists(atPath: item.quarantinePath)
            }
        }) == true
    }

    var quarantineTotalSize: Int64 {
        (try? allManifests().flatMap(\.items).filter { item in
            item.state == .moved &&
            fileManager.fileExists(atPath: item.quarantinePath)
        }.reduce(0) { $0 + $1.size }) ?? 0
    }

    private func save(_ manifest: DurableManifest, to url: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    private func loadLatestRestorableManifest() throws -> (URL, DurableManifest) {
        let candidates = try manifestURLs().compactMap { url -> (URL, DurableManifest)? in
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(DurableManifest.self, from: data),
                  manifest.items.contains(where: { item in
                      (item.state == .moved || item.state == .planned) &&
                      fileManager.fileExists(atPath: item.quarantinePath)
                  }) else { return nil }
            return (url, manifest)
        }
        guard let latest = candidates.max(by: {
            let leftOrder = $0.1.createdAtUnixNanoseconds
                ?? Int64($0.1.date.timeIntervalSince1970 * 1_000_000_000)
            let rightOrder = $1.1.createdAtUnixNanoseconds
                ?? Int64($1.1.date.timeIntervalSince1970 * 1_000_000_000)
            if leftOrder == rightOrder { return $0.0.path < $1.0.path }
            return leftOrder < rightOrder
        }) else {
            throw CleanupError.restoreError("No restorable quarantine manifest found")
        }
        return latest
    }

    private func allManifests() throws -> [DurableManifest] {
        try manifestURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DurableManifest.self, from: data)
        }
    }

    private func manifestURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: quarantineURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: quarantineURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map { $0.appendingPathComponent("manifest.json", isDirectory: false) }
    }
}

private struct DurableManifest: Codable {
    let version: Int
    let id: UUID
    let date: Date
    let createdAtUnixNanoseconds: Int64?
    var items: [DurableItem]
}

private struct DurableItem: Codable {
    enum State: String, Codable {
        case planned
        case moved
        case failed
        case restored
        case purged
    }

    let id: UUID
    let originalPath: String
    let quarantinePath: String
    let size: Int64
    let category: String
    let appName: String?
    var state: State
    var errorMessage: String?

    var publicRecord: MovedItemRecord {
        MovedItemRecord(
            id: id,
            originalPath: originalPath,
            quarantinePath: quarantinePath,
            size: size,
            category: category,
            appName: appName
        )
    }
}
