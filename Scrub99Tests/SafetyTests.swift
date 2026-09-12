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
        // Taken from the engine rather than spelled out here, so the test fails
        // if quarantine ever drifts back into a folder the user cannot see.
        let quarantine = CleanupEngine.quarantineURL(homeDirectory: home)

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

        // The reader's own list. It is the one input that can only ever add
        // refusals, so the assertions below are about a path going from ordinary
        // to untouchable and back — never the other way round.
        let keptFolder = home.appendingPathComponent("Library/Caches/com.example.kept", isDirectory: true)
        try writeFixture("kept", in: keptFolder, fileManager: fileManager)
        let insideKeptFolder = keptFolder.appendingPathComponent("inside", isDirectory: true)
        try writeFixture("inside", in: insideKeptFolder, fileManager: fileManager)
        let keptFolderItem = item(path: keptFolder, category: .cache, safety: .safeToReplace, association: .confirmed)
        let insideKeptFolderItem = item(path: insideKeptFolder, category: .cache, safety: .safeToReplace, association: .confirmed)
        let otherSibling = home.appendingPathComponent("Library/Caches/com.example.other", isDirectory: true)
        try writeFixture("other", in: otherSibling, fileManager: fileManager)
        let otherSiblingItem = item(path: otherSibling, category: .cache, safety: .safeToReplace, association: .confirmed)

        // The baseline first, or every later assertion would pass for the wrong
        // reason.
        try expect(policy.assess(keptFolderItem).isEligible, "Without a left-alone list this cache root must be eligible, or the rest of this block proves nothing.")

        let protectingPolicy = CleanupSafetyPolicy(
            homeDirectory: home,
            quarantineRoot: quarantine,
            protectedPaths: [keptFolder.path]
        )
        let keptAssessment = protectingPolicy.assess(keptFolderItem)
        try expect(!keptAssessment.isEligible, "A path on the left-alone list must never be eligible for cleanup.")
        try expect(!keptAssessment.canBeSelected, "A path on the left-alone list must not be tickable at all.")
        try expect(keptAssessment.reason.contains("You asked"), "A refusal the reader caused must be attributed to them rather than to one of Scrub 99's own rules.")
        try expect(!protectingPolicy.isRecommendedForGuidedCleanup(keptFolderItem), "A protected path must not enter the guided cleanup queue.")
        do {
            _ = try protectingPolicy.preflight([keptFolderItem])
            throw TestFailure.assertion("Preflight must refuse a protected path.")
        } catch is CleanupSafetyError {
            // Expected.
        }

        // Protecting a folder protects what is inside it, and the reason names the
        // folder rather than the leaf, because the folder is what has to be undone.
        let insideKeptAssessment = protectingPolicy.assess(insideKeptFolderItem)
        try expect(!insideKeptAssessment.canBeSelected, "Protecting a folder must protect everything inside it.")
        try expect(insideKeptAssessment.reason.contains(keptFolder.lastPathComponent), "A refusal inherited from a folder must name that folder.")

        // The list has to be precise: protecting one folder cannot quiet its
        // neighbours, or the whole cache root would go silent.
        try expect(protectingPolicy.assess(otherSiblingItem).isEligible, "Protecting one folder must not make unrelated paths ineligible.")

        // The list on disk, which is what the app actually launches with.
        let listFile = testRoot.appendingPathComponent("Protection.json", isDirectory: false)
        let list = ProtectionList(fileURL: listFile, fileManager: fileManager)
        try expect(list.isEmpty, "A list file that does not exist yet must load as empty rather than as a failure.")
        try expect(list.protect(path: keptFolder.path, kind: "cache", on: Date(timeIntervalSince1970: 1_000)), "Protecting a new path must be recorded.")
        try expect(!list.protect(path: keptFolder.path, kind: "cache"), "Protecting the same path twice must change nothing.")
        try expect(!list.protect(path: insideKeptFolder.path, kind: "cache"), "Protecting a path a protected folder already covers must change nothing.")
        try expect(list.count == 1, "A repeated protection must not add a second entry.")
        try expect(list.isProtected(insideKeptFolder.path), "The list must report a path under a protected folder as protected.")
        try expect(!list.isProtected(otherSibling.path), "The list must not report unrelated paths as protected.")
        try expect(list.entries.first?.path == keptFolder.standardizedFileURL.resolvingSymlinksInPath().path, "A stored path must be standardised, so two spellings of one place cannot sit in the list as two entries.")

        let listContents = try String(contentsOf: listFile, encoding: .utf8)
        try expect(listContents.contains("\"path\""), "The left-alone list must be plain JSON the reader can open in any text editor.")

        let reopenedList = ProtectionList(fileURL: listFile, fileManager: fileManager)
        try expect(reopenedList.count == 1, "The list must survive being read by a fresh instance, since that is how every launch reads it.")
        try expect(reopenedList.isProtected(keptFolder.path), "The reopened list must still cover the path it was given.")

        // Releasing, and what it means: the path is not cleaned, it just stops
        // being special. A list rebuilt from the released file has to agree.
        try expect(reopenedList.release(path: keptFolder.path), "Releasing an entry must be recorded.")
        try expect(!reopenedList.release(path: keptFolder.path), "Releasing an entry that is not on the list must change nothing.")
        try expect(!reopenedList.isProtected(insideKeptFolder.path), "Releasing a folder must release the paths it covered.")
        let releasedList = ProtectionList(fileURL: listFile, fileManager: fileManager)
        try expect(releasedList.isEmpty, "A released entry must stay released across a relaunch.")
        let releasedPolicy = CleanupSafetyPolicy(
            homeDirectory: home,
            quarantineRoot: quarantine,
            protectedPaths: releasedList.entries.map(\.path)
        )
        try expect(releasedPolicy.assess(insideKeptFolderItem).isEligible, "Releasing an entry must make the path ordinary again rather than merely less protected.")

        let engine = CleanupEngine(
            homeDirectory: home,
            quarantineRoot: quarantine,
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
        try expect(
            secondEntry.quarantinePath.hasPrefix(quarantine.path),
            "Quarantine entries must expose their durable destination inside the visible quarantine folder."
        )
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

        // Only transaction folders count here. The quarantine root also holds a
        // plain-language READ ME file, which is not a cleanup record and must not
        // be mistaken for one.
        let transactionCount = try fileManager.contentsOfDirectory(
            at: quarantine,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.count
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

        // Classification regressions: storage category and finding origin are separate.
        let classifier = Classifier()
        let modelNamedSupport = FoundItem(
            path: home.appendingPathComponent("Library/Application Support/Modeler Pro", isDirectory: true),
            size: 1_024,
            category: .unknown, safetyLevel: .unknown, association: .unknown
        )
        let classifiedModelNamedSupport = classifier.classify(items: [modelNamedSupport])[0]
        try expect(classifiedModelNamedSupport.category == .applicationData, "An Application Support folder must be application data even when its product name contains 'Model'.")
        try expect(!classifiedModelNamedSupport.tags.contains(.model), "A product/folder name containing 'Model' must not be treated as model weights without strong model evidence.")

        let mixedCaseCache = FoundItem(
            path: home.appendingPathComponent("Library/Caches/com.example.MixedCase", isDirectory: true),
            size: 1_024,
            category: .unknown, safetyLevel: .unknown, association: .unknown
        )
        let classifiedCache = classifier.classify(items: [mixedCaseCache])[0]
        try expect(classifiedCache.category == .cache, "Library/Caches must classify as cache after lowercasing the path.")
        try expect(classifiedCache.safetyLevel == .safeToReplace, "A classified cache must receive safe-to-replace safety when no stronger risk is present.")

        let documentCandidate = FoundItem(
            path: home.appendingPathComponent("Documents/Classifier Safety", isDirectory: true),
            size: 1_024,
            category: .unknown, safetyLevel: .unknown, association: .unknown
        )
        let classifiedDocument = classifier.classify(items: [documentCandidate])[0]
        try expect(classifiedDocument.safetyLevel == .userDataType, "Documents must remain user data after path normalization.")

        let ggufCandidate = FoundItem(
            path: home.appendingPathComponent("Downloads/llama-3.gguf"),
            size: 1_024,
            category: .unknown, safetyLevel: .unknown, association: .unknown
        )
        let classifiedGGUF = classifier.classify(items: [ggufCandidate])[0]
        try expect(classifiedGGUF.category == .downloadedModels, "A GGUF file must remain a downloaded model.")

        let aiRule = ApplicationRule(name: "Claude", executableName: "claude", category: .ai, description: "AI fixture")
        let removedAI = FoundItem(
            path: home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true),
            size: 1_024,
            category: .applicationData, safetyLevel: .reviewFirst, association: .veryLikely,
            primaryApplication: ApplicationRef(name: "Claude", isInstalled: false)
        )
        try expect(Classifier.findingKind(for: removedAI, rules: [aiRule]) == .aiLeftover, "Known AI data with no installed owning app must be labeled AI Leftover.")

        let installedAI = FoundItem(
            path: home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true),
            size: 1_024,
            category: .applicationData, safetyLevel: .reviewFirst, association: .confirmed,
            primaryApplication: ApplicationRef(name: "Claude", isInstalled: true)
        )
        try expect(Classifier.findingKind(for: installedAI, rules: [aiRule]) == .aiAppData, "Known AI data for an installed app must be labeled AI App Data rather than leftover.")

        let ordinaryPhantom = FoundItem(
            path: phantomSupport,
            size: 1_024,
            category: .applicationData, safetyLevel: .reviewFirst, association: .veryLikely,
            primaryApplication: ApplicationRef(name: "Qrookie", isInstalled: false),
            reason: "Immediate child of an expanded inventory root in the Phantom Application Audit rule"
        )
        try expect(Classifier.findingKind(for: ordinaryPhantom, rules: [aiRule]) == .applicationLeftover, "An orphaned ordinary Application Support namespace must be labeled App Leftover, not AI Leftover.")

        let housekeepingKind = FoundItem(
            path: npmCache,
            size: 1_024,
            category: .cache, safetyLevel: .safeToReplace, association: .confirmed,
            primaryApplication: ApplicationRef(name: "macOS Housekeeping", isInstalled: true)
        )
        try expect(Classifier.findingKind(for: housekeepingKind, rules: [aiRule]) == .housekeeping, "Known housekeeping paths must remain separate from AI and app leftovers.")

        // "Last used" and "how big" are the two things a reader judges an item
        // by, so neither may overstate what is known: a missing date is not "no
        // days ago", and a size that was never read is not zero bytes.
        let phantomFromYearsAgo = FoundItem(
            path: home.appendingPathComponent("Library/Application Support/Qrookie", isDirectory: true),
            size: 0,
            modified: Date().addingTimeInterval(-400 * 24 * 60 * 60),
            category: .applicationData, safetyLevel: .reviewFirst, association: .veryLikely
        )
        try expect(phantomFromYearsAgo.lastUsedDays == 400, "Days since last use must be counted from the change date when macOS recorded no access date.")
        try expect(!phantomFromYearsAgo.lastUsedIsRecorded, "An item with no recorded access date must admit it rather than passing the change date off as one.")
        try expect(phantomFromYearsAgo.lastUsedDescription == "over a year ago", "Four hundred days must be described as over a year ago.")
        try expect(phantomFromYearsAgo.lastUsedIsStale, "An item untouched for over half a year must count as stale.")
        try expect(phantomFromYearsAgo.size.sizeDescription == "Not measured", "A size of zero must be reported as unmeasured rather than as an empty item.")

        let touchedRecently = FoundItem(
            path: home.appendingPathComponent("Library/Caches/com.example.recent", isDirectory: true),
            size: 2_048,
            lastAccessed: Date().addingTimeInterval(-3 * 24 * 60 * 60),
            category: .cache, safetyLevel: .safeToReplace, association: .confirmed
        )
        try expect(touchedRecently.lastUsedIsRecorded, "A recorded access date must be preferred over the change date.")
        try expect(touchedRecently.lastUsedDescription == "3 days ago", "An access date three days old must read as three days ago.")
        try expect(!touchedRecently.lastUsedIsStale, "Three days is not a stale item.")
        try expect(touchedRecently.size.sizeDescription == "2.0 KB", "A measured size must still print as a size.")

        // Builds before this one quarantined into a hidden folder under
        // Application Support. Anything still sitting there has to be walked out
        // into the visible folder on the next launch, and has to still restore
        // to its exact original path afterwards — a manifest left naming the old
        // location would strand it.
        let legacyRoot = CleanupEngine.legacyQuarantineURL(homeDirectory: home)
        let legacyEngine = CleanupEngine(
            homeDirectory: home,
            quarantineRoot: legacyRoot,
            fileManager: fileManager
        )
        let legacyCache = home.appendingPathComponent("Library/Caches/com.example.legacy", isDirectory: true)
        try writeFixture("legacy", in: legacyCache, fileManager: fileManager)
        let legacyItem = item(path: legacyCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        _ = try await legacyEngine.cleanup(items: [legacyItem])
        try expect(fileManager.fileExists(atPath: legacyRoot.path), "The legacy fixture must be quarantined in the hidden folder first.")

        let visibleEngine = CleanupEngine(homeDirectory: home, fileManager: fileManager)
        try expect(
            visibleEngine.quarantineURL == home.appendingPathComponent("Scrub99 Quarantine", isDirectory: true),
            "Quarantine must default to a visible folder at the top of the home directory."
        )
        let adopted = visibleEngine.adoptLegacyQuarantineIfNeeded()
        try expect(adopted == 1, "A transaction left in the hidden quarantine folder must be moved into the visible one.")
        guard let adoptedEntry = visibleEngine.quarantineEntries().first(where: { $0.originalPath == legacyCache.path }) else {
            throw TestFailure.assertion("A walked-out transaction must be readable from the visible quarantine folder.")
        }
        try expect(
            adoptedEntry.quarantinePath.hasPrefix(visibleEngine.quarantineURL.path),
            "The rewritten manifest must name the new visible location, not the old hidden one."
        )
        try visibleEngine.restore(adoptedEntry)
        try expect(fileManager.fileExists(atPath: legacyCache.path), "A walked-out item must still restore to its original path.")
        let legacyLeftovers = (try? fileManager.contentsOfDirectory(atPath: legacyRoot.path)) ?? []
        try expect(
            !fileManager.fileExists(atPath: legacyRoot.path) || legacyLeftovers.isEmpty,
            "Walking quarantine out must leave the old hidden folder empty rather than deleting it or its contents."
        )

        try expect(
            CleanupEngine.ownerName("claude", describes: "Claude"),
            "A running application must be recognised by its own name, whatever the case."
        )
        try expect(
            CleanupEngine.ownerName("Google Chrome", describes: "Google Chrome Helper (Renderer)"),
            "A helper process must be attributed to the application it belongs to."
        )
        try expect(
            !CleanupEngine.ownerName("log", describes: "loginwindow"),
            "A folder named 'log' must not be reported as the running 'loginwindow'."
        )
        try expect(
            !CleanupEngine.ownerName("NGL", describes: "Single Sign-On"),
            "A name must not be matched part-way into a longer, unrelated name."
        )
        try expect(
            !CleanupEngine.ownerName("Claude", describes: "Claudette"),
            "A prefix must end at a word boundary, or a coincidence of spelling reads as a running application."
        )
        try expect(
            !CleanupEngine.ownerName("Claude", describes: nil),
            "A process with no name must not be treated as the owner."
        )

        // And through the call the cleanup path itself makes, so the fix cannot
        // be undone by the caller. The owner is a phantom — the shape Scrub99
        // gives an undeclared folder — and is named after one.
        let phantomOwner = FoundItem(
            path: cache,
            size: 8,
            category: .cache,
            safetyLevel: .safeToReplace,
            association: .veryLikely,
            primaryApplication: ApplicationRef(name: "log", isInstalled: false)
        )
        let phantomRefusals = try await CleanupEngine(homeDirectory: home, fileManager: fileManager)
            .checkRunningApps([phantomOwner])
        try expect(
            phantomRefusals.isEmpty,
            "An item owned by an undeclared folder named 'log' must not be refused as if the folder were a running application."
        )

        // History is rebuilt from the records on disk rather than from anything
        // the app holds in memory, so it has to answer for runs it did not watch
        // and has to follow the folder when the folder changes behind it.
        let historyCache = home.appendingPathComponent("Library/Caches/com.example.scrub99-history", isDirectory: true)
        try writeFixture("history", in: historyCache, fileManager: fileManager)
        let historyItem = item(path: historyCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        let historyCleanup = try await engine.cleanup(items: [historyItem])
        try expect(historyCleanup.successCount == 1, "The history fixture must be quarantined.")

        func recordedBatch(for path: URL) -> CleanupTransaction? {
            engine.transactionHistory().first { transaction in
                transaction.items.contains { $0.originalPath == path.path }
            }
        }

        guard let waitingBatch = recordedBatch(for: historyCache) else {
            throw TestFailure.assertion("A completed cleanup must appear in the history.")
        }
        try expect(waitingBatch.waitingCount == 1, "An item still sitting in Quarantine must be recorded as waiting.")
        try expect(waitingBatch.canBePutBack, "A batch with something still waiting must offer to put it back.")
        try expect(waitingBatch.waitingSize == historyItem.size, "The waiting total must count only what is still in the folder.")

        // The same record read again after the item is gone from the folder by
        // hand: history follows the folder, not its own memory of the folder.
        guard let historyQuarantinePath = historyCleanup.movedItems.first?.quarantinePath else {
            throw TestFailure.assertion("The history fixture must record where it moved the item.")
        }
        try fileManager.removeItem(at: historyQuarantinePath)
        guard let emptiedBatch = recordedBatch(for: historyCache) else {
            throw TestFailure.assertion("A cleanup whose items were removed by hand must still appear in the history.")
        }
        try expect(emptiedBatch.waitingCount == 0, "An item the folder no longer holds must not be counted as waiting.")
        try expect(emptiedBatch.goneCount == 1, "An item deleted from the folder by hand must be reported as gone.")
        try expect(!emptiedBatch.canBePutBack, "Putting a batch back must not be offered when the folder no longer holds it.")
        try expect(emptiedBatch.items.count == 1, "Removing an item by hand must not erase it from the record of what happened.")

        // Putting something back is recorded as what happened, not removed from
        // the history: the batch it belonged to has to keep saying so.
        guard let putBackBatch = recordedBatch(for: explicitProject) else {
            throw TestFailure.assertion("A restored cleanup must remain in the history.")
        }
        try expect(putBackBatch.waitingCount == 0 && putBackBatch.putBackCount == 1, "A restored item must be reported as put back rather than waiting.")
        try expect(fileManager.fileExists(atPath: explicitProject.path), "The restored project must be back at its original path for this to mean anything.")

        let history = engine.transactionHistory()
        let recordedFolders = (try fileManager.contentsOfDirectory(
            at: quarantine,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.count
        try expect(history.count == recordedFolders, "The history must account for every recorded cleanup, no more and no fewer.")
        try expect(history.count >= 4, "Every cleanup run on disk must appear in the history.")
        try expect(
            history.map(\.date) == history.map(\.date).sorted(by: >),
            "The history must list the most recent cleanup first."
        )

        // Display paths are shortened to `~` so the part that tells two rows apart
        // survives truncation. The boundary matters: `~/…` must not swallow a
        // neighbouring user whose name merely starts with the same letters.
        let displayHome = FileManager.default.homeDirectoryForCurrentUser.path
        try expect(
            URL(fileURLWithPath: displayHome).homeAbbreviatedPath == "~",
            "The home directory itself must read as `~`."
        )
        try expect(
            URL(fileURLWithPath: displayHome + "/Library/Logs").homeAbbreviatedPath == "~/Library/Logs",
            "A path under the home directory must lose the home prefix and read from `~`."
        )
        try expect(
            URL(fileURLWithPath: "/Applications/Safari.app").homeAbbreviatedPath == "/Applications/Safari.app",
            "A path outside the home directory must be left exactly as it was."
        )
        try expect(
            URL(fileURLWithPath: displayHome + "2/Library/Logs").homeAbbreviatedPath != "~2/Library/Logs",
            "A sibling directory whose name extends the home directory's name must not be abbreviated."
        )

        // A folder can be a working copy whatever its name says. Every case below
        // is a cache root that would otherwise be eligible, so a refusal here is
        // the guard talking and nothing else.
        let workingCopyPolicy = CleanupSafetyPolicy(homeDirectory: home, quarantineRoot: quarantine)

        let plainCache = home.appendingPathComponent("Library/Caches/com.example.plain", isDirectory: true)
        try writeFixture("plain", in: plainCache, fileManager: fileManager)
        let plainItem = item(path: plainCache, category: .cache, safety: .safeToReplace, association: .confirmed)

        // The baseline first. Without it, every later refusal could be passing
        // because the folders are ineligible for some unrelated reason.
        try expect(workingCopyPolicy.assess(plainItem).isEligible, "An ordinary cache root with no repository or key inside it must stay eligible.")

        let repositoryCache = home.appendingPathComponent("Library/Caches/com.example.repository", isDirectory: true)
        try writeFixture("repository", in: repositoryCache, fileManager: fileManager)
        try fileManager.createDirectory(at: repositoryCache.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let repositoryAssessment = workingCopyPolicy.assess(
            item(path: repositoryCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        )
        try expect(repositoryAssessment.decision == .blocked, "A cache root holding a Git repository must not be offerable.")
        try expect(repositoryAssessment.reason.contains("Git repository"), "The refusal must say that a repository is what stopped it.")

        // Deeper than the folder itself, and named after the service rather than
        // after itself — the two reasons the search has to look inside and to know
        // extensions rather than only names.
        let keyCache = home.appendingPathComponent("Library/Caches/com.example.keys", isDirectory: true)
        try writeFixture("keys", in: keyCache, fileManager: fileManager)
        try Data("key".utf8).write(to: keyCache.appendingPathComponent("server.pem"), options: .atomic)
        let keyAssessment = workingCopyPolicy.assess(
            item(path: keyCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        )
        try expect(keyAssessment.decision == .blocked, "A cache root holding a deployment key must not be offerable.")
        try expect(keyAssessment.reason.contains("server.pem"), "The refusal must name the file that stopped it, not just the rule.")

        // Depth: a repository three levels down is still inside the folder that
        // would have been moved, and the reason must say where it was.
        let nestedCache = home.appendingPathComponent("Library/Caches/com.example.nested", isDirectory: true)
        try writeFixture("nested", in: nestedCache, fileManager: fileManager)
        let deepRepository = nestedCache.appendingPathComponent("project/sub/.git", isDirectory: true)
        try fileManager.createDirectory(at: deepRepository, withIntermediateDirectories: true)
        let nestedAssessment = workingCopyPolicy.assess(
            item(path: nestedCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        )
        try expect(nestedAssessment.decision == .blocked, "A repository nested inside a cache root must block the whole folder.")
        try expect(nestedAssessment.reason.contains("project/sub/.git"), "A nested refusal must say where inside the folder the repository is.")

        // The finding itself can be the sensitive file, not only the folder that
        // holds it.
        let looseKey = home.appendingPathComponent("Library/Caches/com.example.loose/id_rsa", isDirectory: false)
        try fileManager.createDirectory(at: looseKey.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("key".utf8).write(to: looseKey, options: .atomic)
        let looseAssessment = workingCopyPolicy.assess(
            item(path: looseKey, category: .cache, safety: .safeToReplace, association: .confirmed)
        )
        try expect(looseAssessment.decision == .blocked, "A key file offered as the finding itself must be refused by name.")

        // A git worktree records its repository in a `.git` *file*, so the check
        // cannot be "is this a directory named .git".
        let worktreeCache = home.appendingPathComponent("Library/Caches/com.example.worktree", isDirectory: true)
        try writeFixture("worktree", in: worktreeCache, fileManager: fileManager)
        try Data("gitdir: /elsewhere/.git/worktrees/x".utf8)
            .write(to: worktreeCache.appendingPathComponent(".git"), options: .atomic)
        try expect(
            workingCopyPolicy.assess(item(path: worktreeCache, category: .cache, safety: .safeToReplace, association: .confirmed)).decision == .blocked,
            "A worktree's .git file marks a working copy just as a .git directory does."
        )

        // Precision, which matters as much as the refusal: an extension in the key
        // list is not a filename in it, and ordinary cache contents are untouched.
        let extensionOnlyCache = home.appendingPathComponent("Library/Caches/com.example.extensionless", isDirectory: true)
        try writeFixture("extensionless", in: extensionOnlyCache, fileManager: fileManager)
        try Data("nothing".utf8).write(to: extensionOnlyCache.appendingPathComponent("key"), options: .atomic)
        try Data("nothing".utf8).write(to: extensionOnlyCache.appendingPathComponent("notes.md"), options: .atomic)
        try expect(
            workingCopyPolicy.assess(item(path: extensionOnlyCache, category: .cache, safety: .safeToReplace, association: .confirmed)).isEligible,
            "A file merely named after a keyword, with no key extension, must not refuse the folder."
        )

        // The memo, stated as a contract because it is a real consequence: the
        // answer is cached per path until a scan begins, so work created inside a
        // folder mid-session is seen on the next scan and not before.
        let laterRepository = home.appendingPathComponent("Library/Caches/com.example.later", isDirectory: true)
        try writeFixture("later", in: laterRepository, fileManager: fileManager)
        let laterItem = item(path: laterRepository, category: .cache, safety: .safeToReplace, association: .confirmed)
        try expect(workingCopyPolicy.assess(laterItem).isEligible, "A folder with nothing in it must be eligible before anything is created in it.")
        try fileManager.createDirectory(at: laterRepository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try expect(workingCopyPolicy.assess(laterItem).isEligible, "Within one scan the policy must answer from its memo rather than re-reading the disk on every redraw.")
        workingCopyPolicy.invalidateWorkingCopyMemo()
        try expect(workingCopyPolicy.assess(laterItem).decision == .blocked, "Starting a scan must let the policy notice a repository created since the last one.")

        // And the guard only ever adds refusals: a path Scrub 99 would already
        // have blocked is still blocked for its original reason.
        let credentialsCache = home.appendingPathComponent("Library/Caches/com.example.credentials", isDirectory: true)
        try writeFixture("credentials", in: credentialsCache, fileManager: fileManager)
        try Data("token".utf8).write(to: credentialsCache.appendingPathComponent(".npmrc"), options: .atomic)
        let credentialsAssessment = workingCopyPolicy.assess(
            item(path: credentialsCache, category: .cache, safety: .safeToReplace, association: .confirmed)
        )
        try expect(credentialsAssessment.decision == .blocked, "A folder holding a credential file must not be offerable.")

        print("Scrub99 safety, scanner, classification, explanation, last-used age, running-application, quarantine, quarantine-migration, cleanup-history, left-alone-list, working-copy-guard, and path-display tests passed: 128 assertions")
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
