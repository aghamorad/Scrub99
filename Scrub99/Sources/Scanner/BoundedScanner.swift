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
            explanation: target.isInventoryChild
                ? "\(target.knownPath.description) Reported separately so its size and path can be reviewed."
                : target.knownPath.description,
            tags: isSymlink ? [.symlink] : [],
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
