// Scrub99 — AppState

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var scanState: ScanState = .idle
    @Published var scanProgress: ScanProgress = .idle  // Changed from .none to .idle
    @Published var scanResults: ScanResults?
    @Published var showCleanupConfirmation = false
    @Published var cleanupHistory: [CleanupRecord] = []
    @Published var currentTheme: Theme
    @Published var lastErrorMessage: String?
    @Published var inspectedItemID: UUID?
    /// Set at the end of `init`, after any quarantine left in the old hidden
    /// folder has been walked out into the visible one. A property initializer
    /// here would run before that move and report the wrong answer.
    @Published var hasQuarantineItems = false
    @Published var showQuarantineManagement = false
    @Published var showGuidedCleanup = false
    /// The rehearsal sheet: what a cleanup would do, said before anything does it.
    @Published var showCleanupPreview = false
    @Published var guidedCleanupItems: [FoundItem] = []
    /// When on, the scan also measures folders no rule describes. It is the
    /// difference between "nothing else to clean" and "4 GB in places I have no
    /// rule for", so it defaults to on and the cost is disclosed before the scan.
    @Published var deepSweep: Bool
    /// The paths the reader has asked Scrub 99 to stop offering, loaded once at
    /// launch. Published so the lists, counts, and veredicts that depend on it
    /// redraw the moment it changes.
    @Published private(set) var protectionEntries: [ProtectionList.Entry] = []
    @Published var showProtectionList = false

    let protectionList: ProtectionList
    /// Rebuilt only when the list changes, and only ever read. Caching it here
    /// keeps a per-row assessment from re-deriving the whole list on every redraw.
    private var cleanupSafetyPolicy = CleanupSafetyPolicy()
    private var scanTask: Task<Void, Never>?
    private var scanWorkerTask: Task<ScanResults, Error>?

    init() {
        let storedTheme = UserDefaults.standard.string(forKey: "scrub99.theme")
        currentTheme = Theme(rawValue: storedTheme ?? "") ?? .classic9

        let storedSweep = UserDefaults.standard.object(forKey: "scrub99.deepSweep") as? Bool
        deepSweep = storedSweep ?? true

        protectionList = ProtectionList()
        protectionEntries = protectionList.entries
        cleanupSafetyPolicy = CleanupSafetyPolicy(protectedPaths: protectionEntries.map(\.path))

        // Anything quarantined by an older build sits in a hidden folder. Move
        // it somewhere visible before anything reads the quarantine folder, so
        // the first screen the user sees already reflects the real contents.
        let engine = CleanupEngine()
        engine.adoptLegacyQuarantineIfNeeded()
        hasQuarantineItems = engine.hasQuarantineItems
    }

    // MARK: - Leaving things alone

    /// Whether this path is one the reader has taken off the table, either itself
    /// or by protecting a folder above it. Answered by the same policy that makes
    /// the cleanup decision, so the button and the refusal cannot disagree.
    func isProtected(_ path: String) -> Bool {
        cleanupSafetyPolicy.isProtected(ProtectionList.normalize(URL(fileURLWithPath: path)))
    }

    /// Puts an item on the left-alone list and takes it out of the current
    /// selection, so a ticked row cannot be protected and cleaned in the same
    /// breath.
    func protect(_ item: FoundItem) {
        guard protectionList.protect(path: item.path.path, kind: item.findingKind.rawValue) else { return }
        applyProtectionChange()
        guard var results = scanResults,
              let index = results.foundItems.firstIndex(where: { $0.id == item.id }) else { return }
        results.foundItems[index].isSelected = false
        scanResults = results
    }

    /// Takes one entry off the list. Keyed on the entry's own stored path rather
    /// than a live scan result, so a path that nothing was found at this time can
    /// still be released.
    func releaseProtection(path: String) {
        guard protectionList.release(path: path) else { return }
        applyProtectionChange()
    }

    func releaseAllProtection() {
        guard !protectionList.isEmpty else { return }
        protectionList.releaseAll()
        applyProtectionChange()
    }

    /// The one place the list and the policy are brought back into step. Every
    /// mutation goes through here, so there is no path that changes one and
    /// leaves the other describing the previous answer.
    private func applyProtectionChange() {
        protectionEntries = protectionList.entries
        cleanupSafetyPolicy = CleanupSafetyPolicy(protectedPaths: protectionEntries.map(\.path))
    }

    func setTheme(_ theme: Theme) {
        guard currentTheme != theme else { return }
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "scrub99.theme")
    }

    func setDeepSweep(_ enabled: Bool) {
        guard deepSweep != enabled else { return }
        deepSweep = enabled
        UserDefaults.standard.set(enabled, forKey: "scrub99.deepSweep")
    }

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
        // A scan is the moment the disk is read again, so anything the policy
        // worked out about what lives where has to be worked out again too.
        cleanupSafetyPolicy.invalidateWorkingCopyMemo()
        scanResults = nil
        scanProgress = .phase("Preparing scan...")
        scanState = .scanning

        if RuleEngine.shared.applications.isEmpty {
            RuleEngine.shared.loadRules()
        }
        let applications = RuleEngine.shared.applications
        let sweep = deepSweep

        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = Scanner(applications: applications, deepSweep: sweep)
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

    func transactionHistory() -> [CleanupTransaction] {
        CleanupEngine().transactionHistory()
    }

    /// Puts back one recorded batch. It deliberately does not start a scan: the
    /// history screen sits over the main window, and a scan firing behind it
    /// would be more disruptive than the staleness it fixes. The items that come
    /// back simply reappear on the next scan.
    func restoreTransaction(_ transaction: CleanupTransaction) async {
        do {
            lastErrorMessage = nil
            _ = try await CleanupEngine().restoreTransaction(transaction)
            refreshQuarantineAvailability()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
    enum Theme: String, CaseIterable, Identifiable {
        case classic9 = "Mac OS 9"
        case liquidGlass = "Liquid Glass"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .classic9: return "Mac OS 9 / Platinum"
            case .liquidGlass: return "Liquid Glass"
            }
        }

        var shortName: String {
            switch self {
            case .classic9: return "Classic 9"
            case .liquidGlass: return "Glass"
            }
        }
    }
}
