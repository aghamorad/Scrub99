// Scrub99 — Classifier
// Classifies found items by category, safety level, and confidence

import Foundation
class Classifier {

    /// Classify a list of items and return classified results.
    func classify(items: [FoundItem]) -> [FoundItem] {
        return items.map { classify($0) }
    }

    /// Classify a single item.
    private func classify(_ item: FoundItem) -> FoundItem {
        var item = item

        // Determine category
        if item.category == .unknown {
            item.category = classifyCategory(item)
        }

        // Determine safety level
        if item.safetyLevel == .unknown {
            item.safetyLevel = classifySafety(item)
        }

        // Determine association
        if item.association == .unknown {
            item.association = classifyAssociation(item)
        }

        // Assign tags
        item.tags = Array(Set(item.tags + classifyTags(item)))

        // Auto-select based on safety
        // Discovery and recommendation are separate from user authorization.
        // Every scan begins with an empty cleanup selection.
        item.isSelected = false

        return item
    }

    /// Determine the item's category based on path analysis.
    private func classifyCategory(_ item: FoundItem) -> ItemCategory {
        let path = item.path.path.lowercased()
        let filename = item.path.lastPathComponent.lowercased()

        // Check by path segments first (most reliable)
        if path.contains("/Library/Caches/") || path.contains("/.cache/") {
            // But model caches are models, not regular caches
            if path.contains("huggingface") || path.contains("ollama") {
                return .downloadedModels
            }
            if path.contains("pip") || path.contains("uv") {
                return .shared
            }
            return .cache
        }

        if path.contains("/Library/Logs/") {
            return .logs
        }

        if filename.hasSuffix(".plist") {
            return .preferences
        }

        // Check for model files
        if isModelFile(filename) {
            return .downloadedModels
        }

        // Check path for model-related keywords
        let modelKeywords = ["model", "checkpoint", "weights", "gguf", "safetensors",
                           "model-store", "models"]
        if modelKeywords.contains(where: { path.contains($0) }) {
            return .downloadedModels
        }

        // Python environments
        if path.contains(".venv") || path.contains("site-packages") ||
           path.contains("virtualenv") || path.contains("pyenv") {
            return .pythonEnvironment
        }

        // Shared resources
        if path.contains("huggingface") || path.contains("hf-") ||
           path.contains("transformers") || path.contains("datasets") {
            return .shared
        }

        // Conversation data
        if path.contains("conversation") || path.contains("chat") ||
           path.contains("messages") {
            return .conversationData
        }

        // Credentials
        if path.contains("credential") || path.contains("api.key") ||
           path.contains(".env") || path.contains("token") {
            return .credentials
        }

        // User data (documents, projects, etc.)
        let userPaths = ["documents", "desktop", "projects", "code", "work"]
        if userPaths.contains(where: { path.contains($0) }) {
            return .projectData
        }

        // Default for large items
        if item.size > 10_000_000 {
            return .applicationData
        }

        return .unknown
    }

    /// Check if a filename matches known model file patterns.
    private func isModelFile(_ filename: String) -> Bool {
        let modelExtensions = ["gguf", "safetensors", "pt", "pth", "onnx",
                             "bin", "model", "ckpt"]
        return modelExtensions.contains { filename.hasSuffix(".\($0)") }
            || filename.contains("model")
    }

    /// Classify safety level.
    private func classifySafety(_ item: FoundItem) -> SafetyLevel {
        let path = item.path.path.lowercased()

        // Never auto-select user data
        if path.contains("/Documents/") || path.contains("/Desktop/") {
            return .userDataType
        }

        // Credentials are always sensitive
        if path.contains("credential") || path.contains("api.key") ||
           path.contains(".env") || path.contains("secret") {
            return .doNotAutoSelect
        }

        // Conversation data
        if item.category == .conversationData {
            return .userDataType
        }

        // Shared resources
        if item.category == .shared {
            return .sharedResource
        }

        // Cache
        if item.category == .cache {
            return .safeToReplace
        }

        // Logs
        if item.category == .logs {
            return .usuallySafe
        }

        // Models
        if item.category == .downloadedModels {
            return .reviewFirst
        }

        // Preferences (small ones are trivial)
        if item.category == .preferences && item.size < 50_000 {
            return .reviewFirst
        }

        // Python environments
        if item.category == .pythonEnvironment {
            return .reviewFirst
        }

        // Unknown or project data
        return .doNotAutoSelect
    }

    /// Classify the association confidence.
    private func classifyAssociation(_ item: FoundItem) -> Association {
        // Use rule engine if available
        if let primaryApp = item.primaryApplication {
            // If we found a rule match, use its confidence
            return primaryApp.isInstalled ? .veryLikely : .possible
        }

        // No app match found
        if item.category == .shared {
            return .shared
        }

        if item.tags.contains(where: { [.gguf, .safetensors, .model].contains($0) }) {
            return .possible  // We know it's a model but not which app
        }

        return .unknown
    }

    /// Classify tags for an item.
    private func classifyTags(_ item: FoundItem) -> [Tag] {
        let path = item.path.path
        let filename = item.path.lastPathComponent.lowercased()
        var tags: [Tag] = []

        if filename.hasSuffix(".gguf") { tags.append(.gguf) }
        if filename.hasSuffix(".safetensors") { tags.append(.safetensors) }
        if filename.contains("checkpoint") { tags.append(.checkpoints) }
        if path.contains("huggingface") || path.contains("hf-") { tags.append(.huggingFace) }
        if path.contains(".ollama") { tags.append(.ollamaModel) }
        if path.contains(".venv") || path.contains("site-packages") { tags.append(.venv) }
        if path.contains(".cache/pip") { tags.append(.pipCache) }
        if path.contains(".cache/uv") { tags.append(.uvCache) }
        if path.contains("model") && !isModelFile(filename) { tags.append(.model) }
        if item.isSymlink { tags.append(.symlink) }
        if item.size > 5_000_000_000 { tags.append(.largeFile) }

        return tags
    }

}
