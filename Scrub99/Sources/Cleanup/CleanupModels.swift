import Foundation

struct CleanupResult {
    let date: Date
    let movedItems: [MovedItem]
    let totalSize: Int64
    let successCount: Int
    let failureCount: Int
    let usedTrash: Bool

    var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = [
            "Cleanup on \(formatter.string(from: date))",
            "Total: \(totalSize.humanReadable) from \(successCount) items",
            "Method: \(usedTrash ? "macOS Trash" : "Scrub99 Quarantine")"
        ]
        if failureCount > 0 {
            lines.append("Failed: \(failureCount) items could not be moved")
        }
        return lines.joined(separator: "\n")
    }
}

struct RestoreResult {
    let restoredItems: [RestoredItem]
    let totalRestored: Int
    let totalSize: Int64
}

struct QuarantineEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let originalPath: String
    let quarantinePath: String
    let size: Int64
    let category: String
    let appName: String?
    let manifestURL: URL

    var existsInQuarantine: Bool {
        FileManager.default.fileExists(atPath: quarantinePath)
    }
}

struct PermanentDeletionResult {
    let deleted: [QuarantineEntry]
    let failed: [(QuarantineEntry, String)]
}

/// One cleanup run, rebuilt from the record Scrub 99 writes next to the items it
/// moved. That record is the only account of a cleanup that outlives the app
/// being quit, so history is read from it rather than from anything held in
/// memory — a run from a previous version still shows up, and the app cannot
/// remember one thing and have the folder say another.
struct CleanupTransaction: Identifiable {
    /// The four things that can actually have happened to one item. There is no
    /// fifth case, and each one has a different answer to "so where is my file".
    enum ItemState: String, CaseIterable {
        case waiting
        case putBack
        case deletedForever
        case gone
        case neverMoved
    }

    struct Item: Identifiable {
        let id: UUID
        let originalPath: String
        let size: Int64
        let category: String
        let appName: String?
        let state: ItemState

        var name: String { (originalPath as NSString).lastPathComponent }
    }

    let id: UUID
    let date: Date
    let items: [Item]
    /// Carried rather than looked up again when something is put back: a folder
    /// adopted from an older version keeps its old name, so the record's own
    /// location is the only thing that is always right.
    let manifestURL: URL

    var waitingItems: [Item] { items.filter { $0.state == .waiting } }
    var waitingCount: Int { waitingItems.count }
    var waitingSize: Int64 { waitingItems.reduce(0) { $0 + $1.size } }
    var putBackCount: Int { items.filter { $0.state == .putBack }.count }
    var deletedCount: Int { items.filter { $0.state == .deletedForever }.count }
    var goneCount: Int { items.filter { $0.state == .gone }.count }
    var neverMovedCount: Int { items.filter { $0.state == .neverMoved }.count }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    /// Only items still sitting in Quarantine can be put back; the rest have
    /// already gone one way or the other, and offering the button would be a lie.
    var canBePutBack: Bool { !waitingItems.isEmpty }
}

enum MovedItem {
    case quarantine(FoundItem, URL)
    case trash(FoundItem)
    case failed(FoundItem, String)

    var item: FoundItem {
        switch self {
        case .quarantine(let item, _), .trash(let item), .failed(let item, _): return item
        }
    }

    var success: Bool {
        switch self {
        case .quarantine, .trash: return true
        case .failed: return false
        }
    }

    var failed: Bool { !success }
    var size: Int64 { item.size }

    var quarantinePath: URL? {
        guard case .quarantine(_, let path) = self else { return nil }
        return path
    }
}

enum RestoredItem {
    case success(MovedItemRecord)
    case failed(MovedItemRecord, String)

    var success: Bool {
        guard case .success = self else { return false }
        return true
    }

    var item: MovedItemRecord {
        switch self {
        case .success(let record), .failed(let record, _): return record
        }
    }

    var size: Int64 { item.size }
}

struct CleanupRecord: Codable {
    let id: UUID
    let date: Date
    let itemCount: Int
    let totalSize: Int64
    let items: [MovedItemRecord]
    let usedTrash: Bool
}

struct MovedItemRecord: Codable {
    let id: UUID
    let originalPath: String?
    let quarantinePath: String?
    let size: Int64
    let category: String
    let appName: String?

    init(
        id: UUID = UUID(),
        originalPath: String?,
        quarantinePath: String?,
        size: Int64,
        category: String,
        appName: String?
    ) {
        self.id = id
        self.originalPath = originalPath
        self.quarantinePath = quarantinePath
        self.size = size
        self.category = category
        self.appName = appName
    }

    init(item: MovedItem) {
        id = UUID()
        originalPath = item.item.path.path
        quarantinePath = item.quarantinePath?.path
        size = item.size
        category = item.item.category.displayName
        appName = item.item.primaryApplication?.name
    }
}

enum CleanupError: LocalizedError {
    case applicationsRunning([ApplicationRef])
    case trashError(String)
    case restoreError(String)

    var errorDescription: String? {
        switch self {
        case .applicationsRunning(let apps):
            return "The following applications are running and must be quit first: \(apps.map(\.name).joined(separator: ", "))"
        case .trashError(let message):
            return "Trash error: \(message)"
        case .restoreError(let message):
            return "Restore error: \(message)"
        }
    }
}
