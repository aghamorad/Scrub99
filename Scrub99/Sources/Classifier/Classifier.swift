// Scrub99 — Classifier
// Classifies found items by category, safety level, confidence, and finding origin

import Foundation

/// Why Scrub99 surfaced a path. This is deliberately separate from ItemCategory:
/// a Claude cache is both "AI app data" and a "Cache", while an orphaned ordinary
/// Application Support folder is an "App Leftover" and "Application Data".
enum FindingKind: String, CaseIterable {
    case undeclared = "No Rule"
    case aiAppData = "AI App Data"
    case aiLeftover = "AI Leftover"
    case applicationLeftover = "App Leftover"
    case housekeeping = "System / Developer Housekeeping"
    case userProject = "User / Project Data"
    case other = "Other"

    /// SF Symbol for this origin group. Lives here rather than in the views so a
    /// new group cannot be added without an icon, and so no view has to switch
    /// over every case just to draw a row.
    var iconName: String {
        switch self {
        case .undeclared: return "folder.badge.questionmark"
        case .aiAppData: return "sparkles"
        case .aiLeftover: return "sparkles.rectangle.stack"
        case .applicationLeftover: return "shippingbox"
        case .housekeeping: return "wrench.and.screwdriver"
        case .userProject: return "folder"
        case .other: return "questionmark.folder"
        }
    }

    /// One line that tells a reader who has never seen Scrub99 what this group
    /// means, in their terms rather than Scrub99's.
    var tagline: String {
        switch self {
        case .undeclared: return "Real folders Scrub 99 has no rule for"
        case .aiAppData: return "Belongs to an AI app you still have installed"
        case .aiLeftover: return "Belongs to an AI app Scrub 99 cannot find installed"
        case .applicationLeftover: return "Looks like residue from an app that is no longer installed"
        case .housekeeping: return "Caches, logs, and package-manager leftovers"
        case .userProject: return "Your own project and workspace data — never ticked for you"
        case .other: return "Found by a rule, but the origin is not clear"
        }
    }

    /// Order the groups by what a reader can act on. Protected user data sorts
    /// last so it is not the first thing on screen after a scan.
    static let displayOrder: [FindingKind] = [
        .undeclared,
        .aiLeftover,
        .applicationLeftover,
        .housekeeping,
        .aiAppData,
        .other,
        .userProject
    ]

    var explanation: String {
        switch self {
        case .undeclared:
            return "Scrub 99 measured this path while sweeping the folders where undeclared data collects, but no rule in its database describes it. Nothing here is a judgment about whether the contents matter — only that Scrub 99 found real, measured storage it has no rule for."
        case .aiAppData:
            return "This path belongs to a known AI application or AI tool that Scrub 99 currently detects as installed or active."
        case .aiLeftover:
            return "This path matches a known AI application rule, but Scrub 99 does not currently detect that application as installed."
        case .applicationLeftover:
            return "This path was found in an app-facing Library location, but Scrub 99 could not find an installed application that appears to own the namespace."
        case .housekeeping:
            return "This is a known operating-system, shell, package-manager, or developer-tool housekeeping path."
        case .userProject:
            return "This is user-created project or workspace data. It is shown for awareness and must not be treated as disposable application residue."
        case .other:
            return "This finding does not fit Scrub 99's AI, application-leftover, housekeeping, or user-project origin groups."
        }
    }
}

extension FoundItem {
    /// Separates why Scrub99 found an item from what kind of data it contains.
    var findingKind: FindingKind {
        Classifier.findingKind(for: self, rules: RuleEngine.shared.applications)
    }
}

class Classifier {

    /// Pure origin classifier used by the UI and tests. Passing rules explicitly keeps
    /// AI-vs-non-AI detection rule-backed instead of hard-coding vendor names.
    static func findingKind(for item: FoundItem, rules: [ApplicationRule]) -> FindingKind {
        // The sweep's own flag is authoritative. An undeclared path must not be
        // re-read as a leftover: "no rule describes this" and "the app is gone"
        // are different claims, and only the first one is supported here.
        if item.isUndeclared {
            return .undeclared
        }

        if item.category == .projectData {
            return .userProject
        }

        if item.primaryApplication?.name == "macOS Housekeeping" {
            return .housekeeping
        }

        if item.reason?.localizedCaseInsensitiveContains("Phantom Application Audit") == true {
            return .applicationLeftover
        }

        if let application = item.primaryApplication,
           let rule = rules.first(where: {
               $0.name.caseInsensitiveCompare(application.name) == .orderedSame
           }),
           rule.category == .ai {
            return application.isInstalled ? .aiAppData : .aiLeftover
        }

        if item.primaryApplication?.isInstalled == false {
            return .applicationLeftover
        }

        return .other
    }

    /// Classify a list of items and return classified results.
    func classify(items: [FoundItem]) -> [FoundItem] {
        return items.map { classify($0) }
    }

    /// Classify a single item.
    private func classify(_ item: FoundItem) -> FoundItem {
        var item = item

        if item.category == .unknown {
            item.category = classifyCategory(item)
        }

        if item.safetyLevel == .unknown {
            item.safetyLevel = classifySafety(item)
        }

        if item.association == .unknown {
            item.association = classifyAssociation(item)
        }

        item.tags = Array(Set(item.tags + classifyTags(item)))

        // Discovery and recommendation are separate from user authorization.
        // Every scan begins with an empty cleanup selection.
        item.isSelected = false

        return item
    }

    /// Determine the item's storage/content category. Root semantics are stronger
    /// evidence than loose product-name keywords.
    private func classifyCategory(_ item: FoundItem) -> ItemCategory {
        let path = item.path.path.lowercased()
        let filename = item.path.lastPathComponent.lowercased()
        let components = item.path.pathComponents.map { $0.lowercased() }

        if path.contains("/library/caches/") || path.contains("/.cache/") {
            if hasStrongModelEvidence(path: path, filename: filename, components: components) {
                return .downloadedModels
            }
            if path.contains("/.cache/pip") || path.contains("/.cache/uv") {
                return .shared
            }
            return .cache
        }

        if path.contains("/library/logs/") {
            return .logs
        }

        if path.contains("/library/preferences/") || filename.hasSuffix(".plist") {
            return .preferences
        }

        // Explicit model files remain models regardless of where they live.
        if isModelFile(filename) {
            return .downloadedModels
        }

        // Application Support and related app-facing Library roots are persistent
        // application state. Do not call a whole support folder a model merely because
        // a product/folder name happens to contain the word "model".
        if path.contains("/library/application support/") ||
           path.contains("/library/containers/") ||
           path.contains("/library/group containers/") ||
           path.contains("/library/saved application state/") ||
           path.contains("/library/httpstorages/") {
            return .applicationData
        }

        if hasStrongModelEvidence(path: path, filename: filename, components: components) {
            return .downloadedModels
        }

        if components.contains(".venv") || components.contains("venv") ||
           path.contains("site-packages") || path.contains("virtualenv") ||
           path.contains("pyenv") {
            return .pythonEnvironment
        }

        if path.contains("huggingface") || path.contains("hf-") ||
           path.contains("transformers") || path.contains("datasets") {
            return .shared
        }

        // Avoid the old broad `chat` substring check. Product names containing "chat"
        // are not evidence that an entire directory is conversation history.
        let conversationNames: Set<String> = ["conversation", "conversations", "messages", "history"]
        if components.contains(where: { conversationNames.contains($0) }) {
            return .conversationData
        }

        if path.contains("credential") || path.contains("api.key") ||
           components.contains(".env") || path.contains("secret") ||
           path.contains("token") {
            return .credentials
        }

        let userComponents: Set<String> = ["documents", "desktop", "projects", "project", "code", "work"]
        if components.contains(where: { userComponents.contains($0) }) {
            return .projectData
        }

        if item.size > 10_000_000 {
            return .applicationData
        }

        return .unknown
    }

    /// Strong model evidence uses exact extensions/path components rather than a
    /// generic `contains("model")` substring.
    private func hasStrongModelEvidence(path: String, filename: String, components: [String]) -> Bool {
        if isModelFile(filename) { return true }

        let modelDirectories: Set<String> = [
            "models", "checkpoints", "weights", "model-store", "model_store"
        ]
        if components.contains(where: { modelDirectories.contains($0) }) {
            return true
        }

        return path.contains("/.ollama/models/") ||
            path.contains("/huggingface/hub/") ||
            path.contains("/huggingface/models/")
    }

    /// Check if a filename matches known model file patterns.
    private func isModelFile(_ filename: String) -> Bool {
        let strongExtensions = ["gguf", "safetensors", "pt", "pth", "onnx", "model", "ckpt"]
        if strongExtensions.contains(where: { filename.hasSuffix(".\($0)") }) {
            return true
        }

        // `.bin` is too generic on its own. Count it only for common model-weight names.
        if filename.hasSuffix(".bin") {
            return filename.contains("pytorch_model") ||
                filename.contains("model-") ||
                filename.contains("weights")
        }

        return false
    }

    private func classifySafety(_ item: FoundItem) -> SafetyLevel {
        let path = item.path.path.lowercased()

        // These comparisons must use lowercase because `path` was lowercased above.
        if path.contains("/documents/") || path.contains("/desktop/") {
            return .userDataType
        }

        if path.contains("credential") || path.contains("api.key") ||
           path.contains(".env") || path.contains("secret") {
            return .doNotAutoSelect
        }

        if item.category == .conversationData {
            return .userDataType
        }

        if item.category == .shared {
            return .sharedResource
        }

        if item.category == .cache {
            return .safeToReplace
        }

        if item.category == .logs {
            return .usuallySafe
        }

        if item.category == .downloadedModels {
            return .reviewFirst
        }

        if item.category == .preferences && item.size < 50_000 {
            return .reviewFirst
        }

        if item.category == .pythonEnvironment {
            return .reviewFirst
        }

        return .doNotAutoSelect
    }

    private func classifyAssociation(_ item: FoundItem) -> Association {
        if let primaryApp = item.primaryApplication {
            return primaryApp.isInstalled ? .veryLikely : .possible
        }

        if item.category == .shared {
            return .shared
        }

        if item.tags.contains(where: { [.gguf, .safetensors, .model].contains($0) }) {
            return .possible
        }

        return .unknown
    }

    private func classifyTags(_ item: FoundItem) -> [Tag] {
        let path = item.path.path.lowercased()
        let filename = item.path.lastPathComponent.lowercased()
        let components = item.path.pathComponents.map { $0.lowercased() }
        var tags: [Tag] = []

        if filename.hasSuffix(".gguf") { tags.append(.gguf) }
        if filename.hasSuffix(".safetensors") { tags.append(.safetensors) }
        if filename.contains("checkpoint") { tags.append(.checkpoints) }
        if path.contains("huggingface") || path.contains("hf-") { tags.append(.huggingFace) }
        if path.contains(".ollama") { tags.append(.ollamaModel) }
        if path.contains(".venv") || path.contains("site-packages") { tags.append(.venv) }
        if path.contains(".cache/pip") { tags.append(.pipCache) }
        if path.contains(".cache/uv") { tags.append(.uvCache) }
        if hasStrongModelEvidence(path: path, filename: filename, components: components) && !isModelFile(filename) {
            tags.append(.model)
        }
        if item.isSymlink { tags.append(.symlink) }
        if item.size > 5_000_000_000 { tags.append(.largeFile) }

        return tags
    }
}
