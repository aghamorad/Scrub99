// Scrub99 — Simple glob pattern matcher

import Foundation

struct GlobMatcher {
    private let pattern: String

    init(pattern: String) {
        self.pattern = pattern
    }

    func matches(_ input: String) -> Bool {
        // Convert glob pattern to regex
        let escaped = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        return input.contains(escaped)
    }
}