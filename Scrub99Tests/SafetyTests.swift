import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

@main
struct SafetyTests {
    static func main() async throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Scrub99SafetyTests-\(UUID().uuidString)", isDirectory: true)
        let home = testRoot.appendingPathComponent("Home", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support/Scrub99", isDirectory: true)
        let quarantine = appSupport.appendingPathComponent("Quarantine", isDirectory: true)

        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        let policy = CleanupSafetyPolicy(homeDirectory: home, quarantineRoot: quarantine)

        let cache = home.appendingPathComponent("Library/Caches/com.example.scrub99-test", isDirectory: true)
        try writeFixture("original", in: cache, fileManager: fileManager)
        let eligible = item(path: cache, category: .cache, safety: .safeToReplace, association: .confirmed)
        try expect(policy.assess(eligible).isEligible, "A confirmed cache root should be eligible for quarantine.")
        try expect(policy.isRecommendedForGuidedCleanup(eligible), "A confirmed low-risk cache root should enter the guided cleanup queue.")

        let documents = home.appendingPathComponent("Documents/Important", isDirectory: true)
        try writeFixture("document", in: documents, fileManager: fileManager)
        let mislabeledDocument = item(path: documents, category: .cache, safety: .safeToReplace, association: .confirmed)
        try expect(!policy.assess(mislabeledDocument).isEligible, "Documents must remain blocked even if an upstream classifier mislabels them.")
        try expect(policy.assess(mislabeledDocument).requiresProtectedConfirmation, "A child of Documents must require the protected-data confirmation.")
        do {
            _ = try policy.preflight([mislabeledDocument])
            throw TestFailure.assertion("Standard preflight must reject protected user data.")
        } catch is CleanupSafetyError {
            // Expected.
        }
        let explicitlyApprovedDocuments = try policy.preflight([mislabeledDocument], allowReviewOnly: true)
        try expect(explicitlyApprovedDocuments.count == 1, "Protected data may pass only the explicit-review preflight.")

        let linkTarget = home.appendingPathComponent("Library/Caches/real-target", isDirectory: true)
        try writeFixture("target", in: linkTarget, fileManager: fileManager)
        let link = home.appendingPathComponent("Library/Caches/symlink-target", isDirectory: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: linkTarget)
        let symlinkItem = FoundItem(
            path: link, size: 1, isSymlink: true, resolvedPath: linkTarget,
            category: .cache, safetyLevel: .safeToReplace, association: .confirmed
        )
        try expect(!policy.assess(symlinkItem).isEligible, "Symbolic links must never be cleanup targets.")

        let uncertain = item(path: cache, category: .cache, safety: .safeToReplace, association: .possible)
        try expect(!policy.assess(uncertain).isEligible, "Possible ownership is insufficient cleanup authority.")

        let child = cache.appendingPathComponent("child", isDirectory: true)
        try writeFixture("child", in: child, fileManager: fileManager)
        let childItem = item(path: child, category: .cache, safety: .safeToReplace, association: .confirmed)
        do {
            _ = try policy.preflight([eligible, childItem])
            throw TestFailure.assertion("Overlapping cleanup targets must be rejected.")
        } catch is CleanupSafetyError {
            // Expected.
        }

        let engine = CleanupEngine(
            homeDirectory: home,
            applicationSupportURL: appSupport,
            fileManager: fileManager
        )
        let cleanup = try await engine.cleanup(items: [eligible])
        try expect(cleanup.successCount == 1, "Eligible cache quarantine should report one successful move.")
        try expect(!fileManager.fileExists(atPath: cache.path), "The original cache path should be absent after quarantine.")
        guard let quarantinePath = cleanup.movedItems.first?.quarantinePath else {
            throw TestFailure.assertion("A successful quarantine move must expose its recorded destination.")
        }
        try expect(fileManager.fileExists(atPath: quarantinePath.path), "The quarantined item must exist at its recorded destination.")
        try expect(engine.hasQuarantineItems, "The engine should report restorable quarantine content.")

        try writeFixture("new-data", in: cache, fileManager: fileManager)
        let collisionRestore = try await engine.undoLastCleanup()
        try expect(collisionRestore.totalRestored == 0, "Restore must refuse to overwrite a newly created original path.")
        let marker = cache.appendingPathComponent("fixture.txt")
        let markerText = try String(contentsOf: marker, encoding: .utf8)
        try expect(markerText == "new-data", "Restore collision handling must leave the new destination content unchanged.")
        try expect(fileManager.fileExists(atPath: quarantinePath.path), "A refused restore must leave quarantine content intact.")

        try fileManager.removeItem(at: cache)
        let restored = try await engine.undoLastCleanup()
        try expect(restored.totalRestored == 1, "Restore should succeed after the collision is removed.")
        let restoredText = try String(contentsOf: marker, encoding: .utf8)
        try expect(restoredText == "original", "Restore must recover the original quarantined content.")
        try expect(!engine.hasQuarantineItems, "A completed restore should leave no restorable quarantine items.")

        do {
            _ = try await engine.cleanup(items: [eligible], useTrash: true)
            throw TestFailure.assertion("Direct Trash cleanup must be disabled in this safety release.")
        } catch let error as CleanupError {
            guard case .trashError = error else { throw error }
        }

        let secondCache = home.appendingPathComponent("Library/Caches/com.example.second", isDirectory: true)
        try writeFixture("second", in: secondCache, fileManager: fileManager)
        let secondItem = item(path: secondCache, category: .cache, safety: .safeToReplace, association: .veryLikely)
        _ = try await engine.cleanup(items: [secondItem])
        let quarantineEntries = engine.quarantineEntries()
        guard let secondEntry = quarantineEntries.first(where: { $0.originalPath == secondCache.path }) else {
            throw TestFailure.assertion("Quarantine management must expose the exact original and quarantine paths.")
        }
        try expect(secondEntry.quarantinePath.contains("Scrub99/Quarantine"), "Quarantine entries must expose their durable destination.")
        try engine.restore(secondEntry)
        try expect(fileManager.fileExists(atPath: secondCache.path), "An individual quarantine entry must be restorable.")

        let permanentCache = home.appendingPathComponent("Library/Caches/com.example.permanent", isDirectory: true)
        try writeFixture("permanent", in: permanentCache, fileManager: fileManager)
        let permanentItem = item(path: permanentCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        _ = try await engine.cleanup(items: [permanentItem])
        guard let permanentEntry = engine.quarantineEntries().first(where: { $0.originalPath == permanentCache.path }) else {
            throw TestFailure.assertion("A quarantined item must be available for permanent deletion review.")
        }
        let permanentResult = try engine.permanentlyDelete([permanentEntry])
        try expect(permanentResult.deleted.count == 1, "Permanent deletion must remove only the explicitly confirmed quarantine entry.")
        try expect(!fileManager.fileExists(atPath: permanentEntry.quarantinePath), "Permanently deleted quarantine content must be absent.")

        let transactionCount = try fileManager.contentsOfDirectory(
            at: quarantine,
            includingPropertiesForKeys: nil
        ).count
        try expect(transactionCount == 3, "Cleanup history must be append-only; later cleanup actions cannot overwrite earlier manifests.")

        let claudeWorkspace = home.appendingPathComponent("Claude", isDirectory: true)
        let virastar = claudeWorkspace.appendingPathComponent("Virastar", isDirectory: true)
        let bedehMa = claudeWorkspace.appendingPathComponent("Bedeh Ma", isDirectory: true)
        try writeFixture("large-project-fixture", in: virastar, fileManager: fileManager)
        try writeFixture("second-project-fixture", in: bedehMa, fileManager: fileManager)
        let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
        let claudeExecutable = localBin.appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: claudeExecutable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudeExecutable.path)

        let claudeRule = ApplicationRule(
            name: "Claude",
            executableName: "claude",
            knownPaths: [KnownPath(
                relativePath: "Claude",
                category: .projectData,
                description: "Protected Claude workspaces.",
                inventoryDepth: 1
            )],
            description: "Scanner fixture"
        )
        let scanner = Scanner(
            applications: [claudeRule],
            fileManager: fileManager,
            homeDirectory: home
        )
        let phantomSupport = home.appendingPathComponent("Library/Application Support/Qrookie", isDirectory: true)
        try writeFixture("orphaned app residue", in: phantomSupport, fileManager: fileManager)
        let inventory = try await scanner.scan { _ in }
        let inventoryPaths = Set(inventory.foundItems.map(\.path))
        let workspaceItems = inventory.foundItems.filter { $0.path == virastar || $0.path == bedehMa }
        try expect(workspaceItems.count == 2, "An inventory-depth workspace must report each immediate child separately.")
        try expect(inventoryPaths.isSuperset(of: Set([virastar, bedehMa])), "Workspace inventory must preserve the exact child paths.")
        try expect(inventory.summary.totalSize > 0, "Workspace inventory must measure child content instead of reporting zero bytes.")
        try expect(workspaceItems.allSatisfy { $0.category == .projectData && $0.safetyLevel == .userDataType }, "Workspace children must remain classified as protected user data.")
        try expect(workspaceItems.allSatisfy { !policy.assess($0).isEligible }, "Protected workspace children must never become cleanup targets.")
        try expect(workspaceItems.allSatisfy { $0.primaryApplication?.isInstalled == true }, "An executable in ~/.local/bin must count as an installed command-line application.")
        try expect(inventoryPaths.contains(phantomSupport), "The scanner must identify residue for an application namespace with no installed app.")
        if let phantom = inventory.foundItems.first(where: { $0.path == phantomSupport }) {
            try expect(phantom.primaryApplication?.isInstalled == false, "Phantom application residue must be marked as uninstalled.")
            try expect(phantom.tags.contains(.old) && phantom.tags.contains(.unused), "Phantom application residue must be visibly labeled for review.")
        }
        let mislabeledClaudeProject = item(path: virastar, category: .cache, safety: .safeToReplace, association: .confirmed)
        try expect(!policy.assess(mislabeledClaudeProject).isEligible, "A top-level Claude workspace must stay protected even if mislabeled as cache data.")

        let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try writeFixture("npm-cache", in: npmCache, fileManager: fileManager)
        let desktopLock = home.appendingPathComponent("Desktop/~$ Book.docx")
        try fileManager.createDirectory(at: desktopLock.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("word lock".utf8).write(to: desktopLock)
        let housekeepingInventory = try await scanner.scan { _ in }
        let housekeepingItems = housekeepingInventory.foundItems
        try expect(housekeepingItems.contains { $0.path == npmCache && $0.category == .cache }, "The scan must identify known disposable npm cache paths.")
        guard let wordLock = housekeepingItems.first(where: { $0.path == desktopLock }) else {
            throw TestFailure.assertion("The scan must identify Desktop Word lock files for review.")
        }
        try expect(!policy.assess(wordLock).isEligible, "A Word lock file on Desktop must remain protected from automatic cleanup.")

        let explicitProject = home.appendingPathComponent("Documents/Explicit Project", isDirectory: true)
        try writeFixture("protected-project", in: explicitProject, fileManager: fileManager)
        let explicitProjectItem = item(path: explicitProject, category: .projectData, safety: .userDataType, association: .confirmed)
        let explicitCleanup = try await engine.cleanup(items: [explicitProjectItem], allowReviewOnly: true)
        try expect(explicitCleanup.successCount == 1, "Typed-confirmation mode must move an explicitly selected project into quarantine.")
        try expect(!fileManager.fileExists(atPath: explicitProject.path), "An explicitly quarantined project must leave its original path.")
        let explicitRestore = try await engine.undoLastCleanup()
        try expect(explicitRestore.totalRestored == 1, "Undo must restore the most recent explicitly quarantined project.")
        try expect(fileManager.fileExists(atPath: explicitProject.path), "Undo must return the protected project to its exact original path.")

        try expect(explicitProjectItem.readerGuide.risk == .high, "Project data must receive a high-risk reader explanation.")
        try expect(!policy.isRecommendedForGuidedCleanup(explicitProjectItem), "Protected project data must never enter the unnecessary-stuff queue.")
        let nodeModulesItem = item(
            path: home.appendingPathComponent("Claude/Test/node_modules", isDirectory: true),
            category: .projectData,
            safety: .userDataType,
            association: .confirmed
        )
        try expect(nodeModulesItem.readerGuide.whatItIs.contains("JavaScript packages"), "A node_modules path must receive the specific dependency explanation instead of only a generic project warning.")

        let smallSortItem = FoundItem(
            path: home.appendingPathComponent("Small"), size: 10,
            category: .cache, safetyLevel: .safeToReplace, association: .confirmed,
            primaryApplication: ApplicationRef(name: "Small App")
        )
        let largeSortItem = FoundItem(
            path: home.appendingPathComponent("Large"), size: 100,
            category: .downloadedModels, safetyLevel: .reviewFirst, association: .confirmed,
            primaryApplication: ApplicationRef(name: "Large App")
        )
        let sameSizeLaterPath = FoundItem(
            path: home.appendingPathComponent("Zulu"), size: 100,
            category: .logs, safetyLevel: .safeToReplace, association: .confirmed,
            primaryApplication: ApplicationRef(name: "Large App")
        )
        let sortFixtures = [smallSortItem, sameSizeLaterPath, largeSortItem]
        try expect(ResultsSorter.items(sortFixtures, by: .size, ascending: false).first?.path.lastPathComponent == "Large", "Descending size sort must put the largest item first and break equal-size ties by path.")
        try expect(ResultsSorter.items(sortFixtures, by: .size, ascending: true).first?.path.lastPathComponent == "Small", "Ascending size sort must put the smallest item first.")
        let sortGroups = Dictionary(grouping: sortFixtures) { $0.primaryApplication?.name ?? "Unclassified" }
        try expect(ResultsSorter.groupNames(sortGroups, by: .size, ascending: false).first == "Large App", "Descending size sort must order application groups by aggregate measured size.")
        try expect(ResultsSorter.items(sortFixtures, by: .item, ascending: true).map(\.path.lastPathComponent) == ["Large", "Small", "Zulu"], "Item sort must use stable natural name ordering.")

        print("Scrub99 safety, scanner, explanation, sorting, and quarantine tests passed: 40 assertions")
    }

    private static func item(
        path: URL,
        category: ItemCategory,
        safety: SafetyLevel,
        association: Association
    ) -> FoundItem {
        FoundItem(
            path: path,
            size: 8,
            category: category,
            safetyLevel: safety,
            association: association
        )
    }

    private static func writeFixture(_ text: String, in directory: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent("fixture.txt"), options: .atomic)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure.assertion(message) }
    }
}
