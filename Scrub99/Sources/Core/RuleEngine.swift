// Scrub99 — Rule Engine
// Loads application rules and matches filesystem paths against them

import AppKit
import Foundation

class RuleEngine {
    static let shared = RuleEngine()

    private(set) var applications: [ApplicationRule] = []
    private var pathToRules: [String: [ApplicationRule]] = [:]
    private var keywordToRules: [String: [ApplicationRule]] = [:]

    private init() {}

    func loadRules() {
        applications = []
        pathToRules.removeAll()
        keywordToRules.removeAll()

        var candidates: [URL] = []
        let cwd = FileManager.default.currentDirectoryPath
        let cwdURL = URL(fileURLWithPath: cwd)

        // 1. Bundle resources (for .app bundle)
        if let bundleURL = Bundle.main.resourceURL {
            candidates.append(bundleURL)
            candidates.append(bundleURL.appendingPathComponent("Rules"))
        }

        // 2. Relative to executable: ../Resources/Rules
        if let execPath = ProcessInfo.processInfo.arguments.first {
            let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent()
            // From executable dir: up 1 = Contents, up 2 = .app root
            // But when run from .build, execDir is .build, up 1 = project root
            let resourcesCandidate = execDir.deletingLastPathComponent()
                .appendingPathComponent("Scrub99.app")
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent("Rules")
            candidates.append(resourcesCandidate)

            let projectResources = execDir.deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent("Rules")
            candidates.append(projectResources)
        }

        // 3. Relative to current working directory
        candidates.append(cwdURL.appendingPathComponent("Scrub99.app/Contents/Resources/Rules"))
        candidates.append(cwdURL.appendingPathComponent("Scrub99/Resources/Rules"))

        // 4. Home directory
        candidates.append(cwdURL.parent().appendingPathComponent("Scrub99/Resources/Rules"))

        // 5. Direct paths
        candidates.append(URL(fileURLWithPath: "/Applications/Scrub99.app/Contents/Resources/Rules"))

        for rulesDir in candidates {
            guard FileManager.default.fileExists(atPath: rulesDir.path) else {
                continue
            }
            let fileCount = (try? FileManager.default.contentsOfDirectory(at: rulesDir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" }.count ?? 0
            if fileCount > 0 {
                loadRules(from: rulesDir)
                print("⚙️ RuleEngine: loaded \(applications.count) rules from \(rulesDir.path)")
                break
            }
        }

        if applications.isEmpty {
            print("⚠️ RuleEngine: no JSON rule files found in any search location")
            print("  Searched:")
            for c in candidates {
                let exists = FileManager.default.fileExists(atPath: c.path) ? "YES" : "no"
                print("    - \(c.path) (\(exists))")
            }
        }

        buildIndex()
        print("⚙️ RuleEngine: \(applications.count) application rules loaded and indexed")
    }

    private func loadRules(from directory: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            if url.pathExtension == "json",
               let data = try? Data(contentsOf: url),
               let rule = try? JSONDecoder().decode(ApplicationRule.self, from: data) {
                applications.append(rule)
            }
        }
    }

    private func buildIndex() {
        for rule in applications {
            for path in rule.knownPaths {
                let key = path.relativePath.lowercased()
                pathToRules[key, default: []].append(rule)
            }

            for keyword in rule.keywords {
                let key = keyword.lowercased()
                keywordToRules[key, default: []].append(rule)
            }

            if let bundleId = rule.bundleIdentifier {
                let key = bundleId.lowercased()
                pathToRules[key, default: []].append(rule)
                keywordToRules[key, default: []].append(rule)
            }
        }
    }

    func match(path: URL) -> [(rule: ApplicationRule, confidence: Float)] {
        let pathStr = path.path.lowercased()
        let relativePath = path.lastPathComponent.lowercased()

        var matches: [(rule: ApplicationRule, confidence: Float)] = []

        for (key, rules) in pathToRules {
            if pathStr.contains(key) || relativePath.contains(key) {
                for rule in rules {
                    if let existing = matches.firstIndex(where: { $0.rule.name == rule.name }) {
                        matches[existing].confidence += 1.0
                    } else {
                        matches.append((rule: rule, confidence: 1.0))
                    }
                }
            }
        }

        for word in pathStr.split(separator: "-") {
            let wordStr = String(word)
            if let rules = keywordToRules[wordStr] {
                for rule in rules {
                    if let existing = matches.firstIndex(where: { $0.rule.name == rule.name }) {
                        matches[existing].confidence += 0.5
                    } else {
                        matches.append((rule: rule, confidence: 0.5))
                    }
                }
            }
        }

        matches.sort { $0.confidence > $1.confidence }
        return matches
    }

    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func findBestMatch(for path: URL) -> ApplicationRule? {
        match(path: path).first?.rule
    }

    func findAllMatches(for path: URL) -> [(rule: ApplicationRule, confidence: Float, association: Association)] {
        match(path: path).map {
            (rule: $0.rule, confidence: $0.confidence, association: toAssociation($0.confidence))
        }
    }

    private func toAssociation(_ confidence: Float) -> Association {
        if confidence >= 3.0 { return .confirmed }
        if confidence >= 2.0 { return .veryLikely }
        if confidence >= 1.0 { return .possible }
        if confidence >= 0.5 { return .shared }
        return .unknown
    }
}

extension URL {
    func parent() -> URL {
        return deletingLastPathComponent()
    }
}
