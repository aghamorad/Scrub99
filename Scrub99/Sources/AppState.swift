// Scrub99 — AppState

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var scanState: ScanState = .idle
    @Published var scanProgress: ScanProgress = .idle  // Changed from .none to .idle
    @Published var scanResults: ScanResults?
    @Published var selectedCategory: Category?
    @Published var showCleanupConfirmation = false
    @Published var cleanupHistory: [CleanupRecord] = []
    @Published var currentTheme: Theme = .classic9
    @Published var lastErrorMessage: String?
    @Published var inspectedItemID: UUID?
    @Published var hasQuarantineItems = CleanupEngine().hasQuarantineItems
    @Published var showQuarantineManagement = false
    @Published var showGuidedCleanup = false
    @Published var guidedCleanupItems: [FoundItem] = []

    private let cleanupSafetyPolicy = CleanupSafetyPolicy()
    private var scanTask: Task<Void, Never>?
    private var scanWorkerTask: Task<ScanResults, Error>?

    enum ScanState: String, Codable {
        case idle, scanning, complete, error
    }

    var activeCleanupItems: [FoundItem] {
        scanResults?.foundItems.filter { $0.isSelected } ?? []
    }

    var totalReclaimable: Int64 {
        activeCleanupItems.reduce(0) { $0 + $1.size }
    }

    var recommendedCleanupItems: [FoundItem] {
        (scanResults?.foundItems ?? [])
            .filter { cleanupSafetyPolicy.isRecommendedForGuidedCleanup($0) }
            .sorted { $0.size > $1.size }
    }

    var inspectedItem: FoundItem? {
        guard let inspectedItemID else { return nil }
        return scanResults?.foundItems.first { $0.id == inspectedItemID }
    }

    func updateScanState(_ state: ScanState) { scanState = state }
    func updateScanProgress(_ progress: ScanProgress) { scanProgress = progress }
    func saveCleanupHistory(_ record: CleanupRecord) { cleanupHistory.insert(record, at: 0) }

    func recordCleanupResult(_ result: CleanupResult) {
        guard result.successCount > 0 else { return }
        let record = CleanupRecord(
            id: UUID(),
            date: result.date,
            itemCount: result.successCount,
            totalSize: result.totalSize,
            items: result.movedItems.map { MovedItemRecord(item: $0) },
            usedTrash: result.usedTrash
        )
        saveCleanupHistory(record)
        removeSuccessfullyMovedItems(result.movedItems)
    }

    func startScan() {
        scanTask?.cancel()
        lastErrorMessage = nil
        scanResults = nil
        scanProgress = .phase("Preparing scan...")
        scanState = .scanning

        if RuleEngine.shared.applications.isEmpty {
            RuleEngine.shared.loadRules()
        }
        let applications = RuleEngine.shared.applications

        let worker = Task.detached(priority: .userInitiated) {
            let scanner = Scanner(applications: applications)
            return try await scanner.scan { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard self?.scanState == .scanning else { return }
                    self?.scanProgress = progress
                }
            }
        }
        scanWorkerTask = worker

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await worker.value

                try Task.checkCancellation()
                let classifier = Classifier()
                var classifiedResults = results
                classifiedResults.foundItems = classifier.classify(items: results.foundItems)
                self.scanResults = classifiedResults
                self.inspectedItemID = classifiedResults.foundItems.first?.id
                self.scanProgress = .complete(classifiedResults)
                self.scanState = .complete
            } catch is CancellationError {
                self.scanProgress = .idle
                self.scanState = .idle
            } catch {
                self.lastErrorMessage = error.localizedDescription
                self.scanState = .error
            }
            self.scanTask = nil
            self.scanWorkerTask = nil
        }
    }

    func cancelScan() {
        scanWorkerTask?.cancel()
        scanWorkerTask = nil
        scanTask?.cancel()
        scanTask = nil
        scanProgress = .idle
        scanState = .idle
    }

    func inspectItem(_ id: UUID) {
        inspectedItemID = id
    }

    func beginGuidedCleanup() {
        guidedCleanupItems = recommendedCleanupItems
        showGuidedCleanup = !guidedCleanupItems.isEmpty
    }

    func cleanupAssessment(for item: FoundItem) -> CleanupSafetyPolicy.Assessment {
        cleanupSafetyPolicy.assess(item)
    }

    func toggleSelection(for id: UUID) {
        guard var results = scanResults,
              let index = results.foundItems.firstIndex(where: { $0.id == id }) else { return }

        if results.foundItems[index].isSelected {
            results.foundItems[index].isSelected = false
        } else if cleanupAssessment(for: results.foundItems[index]).canBeSelected {
            results.foundItems[index].isSelected = true
        }
        scanResults = results
    }

    func removeSuccessfullyMovedItems(_ movedItems: [MovedItem]) {
        let movedIDs = Set(movedItems.filter(\.success).map { $0.item.id })
        guard !movedIDs.isEmpty, var results = scanResults else { return }
        results.foundItems.removeAll { movedIDs.contains($0.id) }
        scanResults = results
        if let inspectedItemID, movedIDs.contains(inspectedItemID) {
            self.inspectedItemID = results.foundItems.first?.id
        }
        refreshQuarantineAvailability()
    }

    func refreshQuarantineAvailability() {
        hasQuarantineItems = CleanupEngine().hasQuarantineItems
    }

    func quarantineEntries() -> [QuarantineEntry] {
        CleanupEngine().quarantineEntries()
    }

    func restoreQuarantineEntry(_ entry: QuarantineEntry) {
        do {
            try CleanupEngine().restore(entry)
            lastErrorMessage = nil
            refreshQuarantineAvailability()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func permanentlyDeleteQuarantineEntries(_ entries: [QuarantineEntry]) {
        do {
            let result = try CleanupEngine().permanentlyDelete(entries)
            lastErrorMessage = result.failed.isEmpty
                ? nil
                : result.failed.map { "\($0.0.originalPath): \($0.1)" }.joined(separator: "\n")
            refreshQuarantineAvailability()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func undoLastQuarantine() async {
        do {
            lastErrorMessage = nil
            _ = try await CleanupEngine().undoLastCleanup()
            refreshQuarantineAvailability()
            startScan()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

extension AppState {
    enum Theme: String, CaseIterable {
        case classic9 = "Mac OS 9", modern = "System"
        var displayName: String {
            switch self { case .classic9: return "Classic 9"; case .modern: return "System" }
        }
    }
}

enum Category: String, CaseIterable {
    case all = "All Items", cache = "Cache", logs = "Logs", downloadedModels = "Downloaded Models"
    case applicationData = "Application Data", preferences = "Preferences"
    case conversationData = "Conversation / History Data"
    case credentials = "Credentials / API Configuration", projectData = "Project Data"
    case pythonEnvironment = "Python Environment", shared = "Shared Resource", unknown = "Unknown"
}
