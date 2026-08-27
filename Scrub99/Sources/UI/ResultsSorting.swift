// Scrub99 — deterministic sorting for the grouped results table

import Foundation

enum ResultsSortField: String, CaseIterable {
    case item = "Item"
    case category = "Category"
    case size = "Size"
    case status = "Status and safety"
}

enum ResultsSorter {
    static func items(
        _ items: [FoundItem],
        by field: ResultsSortField,
        ascending: Bool
    ) -> [FoundItem] {
        items.sorted { left, right in
            let comparison = compare(left, right, by: field)
            if comparison == .orderedSame {
                return left.path.path.localizedStandardCompare(right.path.path) == .orderedAscending
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    static func groupNames(
        _ groups: [String: [FoundItem]],
        by field: ResultsSortField,
        ascending: Bool
    ) -> [String] {
        groups.keys.sorted { leftName, rightName in
            let comparison: ComparisonResult
            switch field {
            case .item:
                comparison = leftName.localizedStandardCompare(rightName)
            case .category:
                comparison = groupText(groups[leftName] ?? [], field: .category)
                    .localizedStandardCompare(groupText(groups[rightName] ?? [], field: .category))
            case .size:
                let leftSize = (groups[leftName] ?? []).reduce(Int64(0)) { $0 + $1.size }
                let rightSize = (groups[rightName] ?? []).reduce(Int64(0)) { $0 + $1.size }
                comparison = leftSize == rightSize ? .orderedSame : (leftSize < rightSize ? .orderedAscending : .orderedDescending)
            case .status:
                comparison = groupText(groups[leftName] ?? [], field: .status)
                    .localizedStandardCompare(groupText(groups[rightName] ?? [], field: .status))
            }

            if comparison == .orderedSame {
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private static func compare(
        _ left: FoundItem,
        _ right: FoundItem,
        by field: ResultsSortField
    ) -> ComparisonResult {
        switch field {
        case .item:
            return left.path.lastPathComponent.localizedStandardCompare(right.path.lastPathComponent)
        case .category:
            return left.category.displayName.localizedStandardCompare(right.category.displayName)
        case .size:
            if left.size == right.size { return .orderedSame }
            return left.size < right.size ? .orderedAscending : .orderedDescending
        case .status:
            let leftStatus = "\(left.association.rawValue) \(left.safetyLevel.rawValue)"
            let rightStatus = "\(right.association.rawValue) \(right.safetyLevel.rawValue)"
            return leftStatus.localizedStandardCompare(rightStatus)
        }
    }

    private static func groupText(_ items: [FoundItem], field: ResultsSortField) -> String {
        switch field {
        case .category:
            return items.map(\.category.displayName).min { $0.localizedStandardCompare($1) == .orderedAscending } ?? ""
        case .status:
            return items.map { "\($0.association.rawValue) \($0.safetyLevel.rawValue)" }
                .min { $0.localizedStandardCompare($1) == .orderedAscending } ?? ""
        default:
            return ""
        }
    }
}
