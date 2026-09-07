import AppKit
import Foundation

/// Scans only roots explicitly described by the rule database. A scan produces
/// an inventory and never mutates the filesystem.
final class Scanner {
    private(set) var foundItems: [FoundItem] = []
    private(set) var scanNotes: [ScanResults.ScanNote] = []
    private(set) var scannedPaths: [URL] = []

    private let applications: [ApplicationRule]
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        applications: [ApplicationRule],
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) {
        self.applications = applications
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    func scan(progressHandler: @escaping (ScanProgress) -> Void) async throws -> ScanResults {
        foundItems = []
        scanNotes = []
        scannedPaths = []
        let startDate = Date()

        guard !applications.isEmpty else {
            throw ScanError.rulesUnavailable
        }

        progressHandler(.phase("Detecting installed applications..."))
        let installedApplicationNames = detectInstalledApplicationNames()
        let rootTargets = buildTargets(installedApplicationNames: installedApplicationNames)
        let targets = expandInventoryTargets(rootTargets)
        progressHandler(.phase("Auditing \(targets.count) known storage locations..."))

        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            scannedPaths.append(target.url)
            progressHandler(.pathProgress(
                path: target.url.abbreviatingWithTilde(homeDirectory: homeDirectory),
                current: index + 1,
                total: targets.count
            ))

            guard fileManager.fileExists(atPath: target.url.path) else { continue }
            if let item = try await inspect(target) {
                foundItems.append(item)
            }
        }

        foundItems.sort {
            if $0.primaryApplication?.name == $1.primaryApplication?.name {
                return $0.path.path < $1.path.path
            }
            return ($0.primaryApplication?.name ?? "") < ($1.primaryApplication?.name ?? "")
        }

        let summary = buildSummary()
        let duration = Date().timeIntervalSince(startDate)
        scanNotes.append(.init(
            phase: "Found",
            message: "\(foundItems.count) rule-backed locations totaling \(summary.totalSize.humanReadable)"
        ))

        let results = ScanResults(
            scannedPaths: scannedPaths,
            foundItems: foundItems,
            summary: summary,
            scanDuration: duration,
            scanNotes: scanNotes
        )
        progressHandler(.complete(results))
        return results
    }

    private struct ScanTarget {
        let url: URL
        let knownPath: KnownPath
        let rule: ApplicationRule
        let app: ApplicationRef
        let association: Association
        let isInventoryChild: Bool
    }

    private func buildTargets(installedApplicationNames: Set<String>) -> [ScanTarget] {
        var targets: [ScanTarget] = []
        var seenPaths: Set<String> = []

        for rule in applications.sorted(by: { $0.name < $1.name }) {
            let isInstalled = installedApplicationNames.contains(rule.name)
            let app = ApplicationRef(
                name: rule.name,
                bundleIdentifier: rule.bundleIdentifier,
                isInstalled: isInstalled
            )
            let association: Association = isInstalled ? .confirmed : .veryLikely

            for knownPath in rule.knownPaths {
                let url = knownPath.expand(to: homeDirectory).standardizedFileURL
                guard isInsideHome(url), seenPaths.insert(url.path).inserted else { continue }
                targets.append(ScanTarget(
                    url: url,
                    knownPath: knownPath,
                    rule: rule,
                    app: app,
                    association: association,
                    isInventoryChild: false
                ))
            }
        }

        targets.append(contentsOf: buildHousekeepingTargets(seenPaths: &seenPaths))
        targets.append(contentsOf: buildPhantomApplicationTargets(seenPaths: &seenPaths))

        return targets
    }

    // MARK: - Phantom application audit

    /// Enumerates the app-facing Library locations that commonly survive an
    /// uninstall. This is deliberately shallow: it reports the app namespace
    /// as one reviewable item and never guesses that its contents are junk.
    private func buildPhantomApplicationTargets(seenPaths: inout Set<String>) -> [ScanTarget] {
        let installed = installedApplicationEvidence()
        let housekeeping = ApplicationRule(
            name: "Phantom Application Audit",
            knownPaths: [],
            category: .system,
            description: "Application residue whose apparent owner is not installed."
        )
        var targets: [ScanTarget] = []

        let roots: [(String, ItemCategory, String)] = [
            ("Library/Application Support", .applicationData, "Persistent application data found under Application Support."),
            ("Library/HTTPStorages", .applicationData, "HTTP cookies and web storage left by an application. This may contain sign-in state and requires review."),
            ("Library/Saved Application State", .applicationData, "Saved window and application state left by an application."),
            ("Library/Preferences", .preferences, "Application preference left after the apparent owner was removed."),
            ("Library/Caches", .cache, "Regenerable cache left by an application."),
            ("Library/Logs", .logs, "Diagnostic logs left by an application."),
            ("Library/Group Containers", .applicationData, "Sandbox group container left by an application."),
            ("Library/LaunchAgents", .applicationData, "Per-user launch agent whose apparent owning application is not installed.")
        ]

        for (relativeRoot, category, description) in roots {
            let root = homeDirectory.appendingPathComponent(relativeRoot, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            for child in children {
                let normalized = child.standardizedFileURL
                guard seenPaths.insert(normalized.path).inserted,
                      shouldAuditAsPhantom(child, root: relativeRoot, installed: installed) else { continue }

                let label = phantomApplicationName(for: child.lastPathComponent)
                let app = ApplicationRef(
                    name: label,
                    bundleIdentifier: probableBundleIdentifier(for: child.lastPathComponent),
                    isInstalled: false
                )
                targets.append(ScanTarget(
                    url: normalized,
                    knownPath: KnownPath(relativePath: relativeRoot, category: category, description: description),
                    rule: housekeeping,
                    app: app,
                    association: .veryLikely,
                    isInventoryChild: true
                ))
            }
        }

        return targets
    }

    private struct InstalledApplicationEvidence {
        var names: Set<String> = []
        var identifiers: Set<String> = []
    }

    private func installedApplicationEvidence() -> InstalledApplicationEvidence {
        var evidence = InstalledApplicationEvidence()
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { continue }
                if let name = info["CFBundleDisplayName"] as? String { evidence.names.insert(normalize(name)) }
                if let name = info["CFBundleName"] as? String { evidence.names.insert(normalize(name)) }
                evidence.names.insert(normalize(url.deletingPathExtension().lastPathComponent))
                if let identifier = info["CFBundleIdentifier"] as? String { evidence.identifiers.insert(normalize(identifier)) }
            }
        }
        return evidence
    }

    private func shouldAuditAsPhantom(
        _ url: URL,
        root: String,
        installed: InstalledApplicationEvidence
    ) -> Bool {
        let rawName = url.lastPathComponent
        let normalizedName = normalize(rawName.replacingOccurrences(of: ".plist", with: ""))
        guard !rawName.isEmpty, rawName != ".DS_Store" else { return false }

        // These are OS-owned or intentionally shared namespaces, even when
        // they do not correspond to a visible third-party application.
        let protectedPrefixes = [
            "com.apple.", "com.openai.", "com.anthropic.", "com.google.",
            "com.microsoft.", "com.adobe.", "com.dropbox.", "com.raycast.",
            "com.macpaw.cleanmymac5", "com.logi.", "com.logitech.",
            "com.malwarebytes.", "com.tdesktop.", "net.whatsapp.",
            "org.mozilla.", "org.videolan.", "org.openemu.", "org.swift.",
            "io.dictionaries.", "io.sentry.", "familycircled", "contactsd",
            "identityservicesd", "privatecloudcomputed", "networkserviceproxy",
            "software update utilities", "proapps", "cef", "crashreporter"
        ]
        if protectedPrefixes.contains(where: { normalizedName.hasPrefix(normalize($0)) }) { return false }

        if let identifier = probableBundleIdentifier(for: rawName),
           installed.identifiers.contains(normalize(identifier)) { return false }

        // A generic support folder may be owned by an app whose bundle ID is
        // not in the folder name. A normalized app-name match is sufficient
        // to keep it out of the phantom list.
        if installed.names.contains(normalizedName) { return false }
        if installed.names.contains(where: { name in
            name.count >= 4 && (normalizedName.contains(name) || name.contains(normalizedName))
        }) { return false }

        // Cache and log roots contain many harmless empty namespaces. They are
        // still useful to show when they have actual content.
        if ["Library/Caches", "Library/Logs"].contains(root) {
            return directoryOrFileHasContent(url)
        }
        return true
    }

    private func directoryOrFileHasContent(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
        if values.isDirectory != true { return true }
        return (try? fileManager.contentsOfDirectory(atPath: url.path).isEmpty == false) ?? false
    }

    private func probableBundleIdentifier(for name: String) -> String? {
        let withoutExtension = name.replacingOccurrences(of: ".plist", with: "")
        let components = withoutExtension.split(separator: ".")
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty }),
              components.first?.count ?? 0 >= 2 else { return nil }
        return withoutExtension
    }

    private func phantomApplicationName(for name: String) -> String {
        let trimmed = name.replacingOccurrences(of: ".plist", with: "")
        if let identifier = probableBundleIdentifier(for: trimmed) {
            return identifier.split(separator: ".").last.map(String.init) ?? trimmed
        }
        return trimmed
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func buildHousekeepingTargets(seenPaths: inout Set<String>) -> [ScanTarget] {
        let rule = ApplicationRule(
            name: "macOS Housekeeping",
            knownPaths: [],
            category: .system,
            description: "Regenerable operating-system and developer-tool leftovers."
        )
        let app = ApplicationRef(name: rule.name, isInstalled: true)
        let candidates: [(String, ItemCategory, String)] = [
            (".npm/_cacache", .cache, "npm package download cache. Regenerable packages used by Node projects."),
            (".npm/_npx", .cache, "Temporary npx command cache. Regenerable packages used by one-off Node commands."),
            (".bun/install/cache", .cache, "Bun package cache. Regenerable packages used by Bun projects."),
            (".cache/clang", .cache, "Compiler module cache. Regenerable build data."),
            (".cache/language_tool_python", .cache, "LanguageTool runtime/cache data. Regenerable if the tool is used again."),
            (".cache/opencode", .cache, "OpenCode cache. Regenerable application data."),
            (".cache/yt-dlp", .cache, "yt-dlp signature cache. Regenerable download metadata."),
            (".matplotlib", .cache, "Matplotlib cache and configuration. Regenerable plotting data."),
            (".idlerc", .cache, "Python IDLE user cache/configuration. Regenerable convenience data."),
            (".zcompdump", .cache, "zsh completion cache. Regenerated by the shell."),
            (".wget-hsts", .cache, "wget HSTS cache. Regenerable connection metadata."),
            (".DS_Store", .cache, "Finder view metadata. Regenerable, but removing it resets this folder's view settings.")
        ]
        var targets: [ScanTarget] = []
        for (relativePath, category, description) in candidates {
            let url = homeDirectory.appendingPathComponent(relativePath).standardizedFileURL
            guard isInsideHome(url), fileManager.fileExists(atPath: url.path), seenPaths.insert(url.path).inserted else { continue }
            targets.append(ScanTarget(
                url: url,
                knownPath: KnownPath(relativePath: relativePath, category: category, description: description),
                rule: rule,
                app: app,
                association: .confirmed,
                isInventoryChild: false
            ))
        }

        let desktop = homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(at: desktop, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
            for child in children where child.lastPathComponent.hasPrefix("~$") && child.pathExtension.lowercased() == "docx" {
                let normalizedChild = child.standardizedFileURL
                guard seenPaths.insert(normalizedChild.path).inserted else { continue }
                targets.append(ScanTarget(
                    url: normalizedChild,
                    knownPath: KnownPath(
                        relativePath: normalizedChild.path.replacingOccurrences(of: homeDirectory.path + "/", with: ""),
                        category: .projectData,
                        description: "Microsoft Word lock file. Usually left while a document is open and may be orphaned after Word closes."
                    ),
                    rule: rule,
                    app: app,
                    association: .confirmed,
                    isInventoryChild: false
                ))
            }
        }
        return targets
    }

    private func expandInventoryTargets(_ rootTargets: [ScanTarget]) -> [ScanTarget] {
        rootTargets.flatMap { target in
            guard target.knownPath.inventoryDepth == 1,
                  fileManager.fileExists(atPath: target.url.path),
                  let values = try? target.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return [target]
            }

            do {
                let children = try fileManager.contentsOfDirectory(
                    at: target.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

                guard !children.isEmpty else { return [target] }
                return children.map { child in
                    ScanTarget(
                        url: child.standardizedFileURL,
                        knownPath: target.knownPath,
                        rule: target.rule,
                        app: target.app,
                        association: target.association,
                        isInventoryChild: true
                    )
                }
            } catch {
                scanNotes.append(.cautionPhase(
                    "Could not list \(target.url.abbreviatingWithTilde(homeDirectory: homeDirectory)): \(error.localizedDescription)"
                ))
                return [target]
            }
        }
    }

    private func inspect(_ target: ScanTarget) async throws -> FoundItem? {
        let values: URLResourceValues
        do {
            values = try target.url.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
                .contentAccessDateKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
            ])
        } catch {
            scanNotes.append(.cautionPhase("Could not read metadata for \(target.url.abbreviatingWithTilde(homeDirectory: homeDirectory)): \(error.localizedDescription)"))
            return nil
        }

        let isSymlink = values.isSymbolicLink == true
        let measurement: SizeMeasurement
        if values.isDirectory == true {
            measurement = try await directorySize(target.url)
        } else {
            measurement = SizeMeasurement(
                bytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                complete: true
            )
        }

        let safety: SafetyLevel
        if isSymlink || !measurement.complete {
            safety = .doNotAutoSelect
        } else {
            safety = initialSafety(for: target.knownPath.category)
        }

        return FoundItem(
            path: target.url,
            size: measurement.bytes,
            modified: values.contentModificationDate,
            lastAccessed: values.contentAccessDate,
            isSymlink: isSymlink,
            resolvedPath: isSymlink ? target.url.resolvingSymlinksInPath() : nil,
            category: target.knownPath.category,
            safetyLevel: safety,
            association: target.association,
            primaryApplication: target.app,
            reason: target.isInventoryChild
                ? "Immediate child of an expanded inventory root in the \(target.rule.name) rule"
                : "Exact path from the \(target.rule.name) rule",
            explanation: target.rule.name == "Phantom Application Audit"
                ? "\(target.knownPath.description) No installed application matching this namespace was found in the current application inventory. Reported separately so its exact path, size, and contents can be reviewed before reversible quarantine."
                : (target.isInventoryChild
                    ? "\(target.knownPath.description) Reported separately so its size and path can be reviewed."
                    : target.knownPath.description),
            tags: isSymlink ? [.symlink] : (target.rule.name == "Phantom Application Audit" ? [.old, .unused] : []),
            isSelected: false
        )
    }

    private struct SizeMeasurement {
        var bytes: Int64
        var complete: Bool
    }

    private func directorySize(_ root: URL) async throws -> SizeMeasurement {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        var measurement = SizeMeasurement(bytes: 0, complete: true)

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { [weak self] url, error in
                measurement.complete = false
                self?.scanNotes.append(.cautionPhase("Could not inspect \(url.path): \(error.localizedDescription)"))
                return true
            }
        ) else {
            return SizeMeasurement(bytes: 0, complete: false)
        }

        var entryCount = 0
        while let url = enumerator.nextObject() as? URL {
            entryCount += 1
            if entryCount.isMultiple(of: 512) {
                try Task.checkCancellation()
                await Task.yield()
            }

            guard let values = try? url.resourceValues(forKeys: keys) else {
                measurement.complete = false
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            measurement.bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return measurement
    }

    private func initialSafety(for category: ItemCategory) -> SafetyLevel {
        switch category {
        case .cache: return .safeToReplace
        case .logs: return .usuallySafe
        case .shared: return .sharedResource
        case .conversationData, .credentials, .projectData: return .userDataType
        case .downloadedModels, .applicationData, .preferences, .pythonEnvironment: return .reviewFirst
        case .unknown: return .doNotAutoSelect
        }
    }

    private func detectInstalledApplicationNames() -> Set<String> {
        Set(applications.compactMap { rule in
            if let bundleIdentifier = rule.bundleIdentifier,
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil {
                return rule.name
            }

            if let executableName = rule.executableName, executableExists(named: executableName) {
                return rule.name
            }

            if rule.bundleIdentifier == nil && rule.executableName == nil {
                return rule.name
            }
            return nil
        })
    }

    private func executableExists(named executableName: String) -> Bool {
        var searchDirectories = [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            searchDirectories.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
            })
        }

        let names = Set([executableName, executableName.lowercased()])
        return searchDirectories.contains { directory in
            names.contains { name in
                fileManager.isExecutableFile(atPath: directory.appendingPathComponent(name).path)
            }
        }
    }

    private func buildSummary() -> ScanResults.Summary {
        let totalSize = foundItems.reduce(0) { $0 + $1.size }
        let appGroups = Dictionary(grouping: foundItems) { $0.primaryApplication?.name ?? "Unknown" }
        return ScanResults.Summary(
            totalSize: totalSize,
            itemCount: foundItems.count,
            appsFound: appGroups.mapValues { $0.reduce(0) { $0 + $1.size } },
            remnantsFound: foundItems.filter {
                $0.primaryApplication?.isInstalled == false && $0.category != .projectData
            }.count,
            sharedResourcesFound: foundItems.filter { $0.category == .shared }.count
        )
    }

    private func isInsideHome(_ url: URL) -> Bool {
        let homeComponents = homeDirectory.pathComponents
        let candidateComponents = url.pathComponents
        guard candidateComponents.count > homeComponents.count else { return false }
        return Array(candidateComponents.prefix(homeComponents.count)) == homeComponents
    }
}

private extension URL {
    func abbreviatingWithTilde(homeDirectory: URL) -> String {
        guard path.hasPrefix(homeDirectory.path) else { return path }
        return "~" + String(path.dropFirst(homeDirectory.path.count))
    }
}
