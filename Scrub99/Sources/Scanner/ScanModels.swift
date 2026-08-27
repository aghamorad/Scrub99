import Foundation

enum ScanProgress {
    case idle
    case phase(String)
    case pathProgress(path: String, current: Int, total: Int)
    case complete(ScanResults)

    var title: String {
        switch self {
        case .phase(let text): return text
        case .pathProgress(let path, let current, let total): return "Auditing: \(path) (\(current)/\(total))"
        case .complete: return "Scan complete"
        case .idle: return "Ready"
        }
    }

    var progressValue: Float {
        switch self {
        case .pathProgress(_, let current, let total):
            return total == 0 ? 0 : Float(current) / Float(total)
        case .phase: return 0
        case .complete: return 1
        case .idle: return 0
        }
    }
}

enum ScanError: Error, LocalizedError {
    case cancelled
    case permissionDenied(URL)
    case rulesUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Scan was cancelled"
        case .permissionDenied(let url): return "Permission denied: \(url.path)"
        case .rulesUnavailable: return "No application rules could be loaded."
        }
    }
}
