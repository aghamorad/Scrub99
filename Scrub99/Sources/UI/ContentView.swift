// Scrub99 — ContentView

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.scanState {
            case .idle: WelcomeView()
            case .scanning: ScanningView()
            case .complete: ResultsView()
            case .error: ErrorView()
            }
        }
        .onAppear { RuleEngine.shared.loadRules() }
        .sheet(isPresented: $appState.showCleanupConfirmation) {
            CleanupView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showGuidedCleanup) {
            GuidedCleanupView(items: appState.guidedCleanupItems)
                .environmentObject(appState)
        }
        // Scrub99 deliberately draws a light Platinum-style surface. Allowing
        // inherited dark-mode labels produces white text on that light surface.
        .preferredColorScheme(.light)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Scrub 99")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(RetroColors.darkText)
                Text("Find leftovers from apps you no longer use.")
                    .font(RetroTypography.bodyFont)
                    .foregroundColor(RetroColors.darkText)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                RetroButton(label: "Scan My Mac", action: appState.startScan)
                Text("Version 0.2.6")
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.secondaryText)
                    .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Text("Scrub 99 will examine ~/Library, caches, and hidden folders.")
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 300)
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 500, minHeight: 350)
        .background(RetroColors.windowBackground)
    }

}

// MARK: - Scanning

struct ScanningView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 32))
                .foregroundColor(RetroColors.darkText)
                .rotationEffect(.degrees(Double(appState.scanProgress.progressValue) * 360))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: Date())
            Text(appState.scanProgress.title)
                .font(RetroTypography.bodyFont)
                .foregroundColor(RetroColors.darkText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            RetroProgressView(progress: appState.scanProgress.progressValue, label: "")
            RetroButton(label: "Cancel", action: appState.cancelScan)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Results

struct ResultsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showAuditExplanation = true
    @State private var sortField: ResultsSortField = .item
    @State private var sortAscending = true

    private func filteredItems(_ items: [FoundItem]) -> [FoundItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.path.path.localizedCaseInsensitiveContains(query) ||
            item.category.displayName.localizedCaseInsensitiveContains(query) ||
            (item.primaryApplication?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        if let results = appState.scanResults {
            VStack(spacing: 0) {
                SummaryBar(results: results)
                    .padding(8)
                DisclosureGroup("What these findings mean", isExpanded: $showAuditExplanation) {
                    Text("Scrub99 lists paths because they match an explicit application rule or protected workspace root. A listing is evidence of disk use, not a declaration that the item is junk. Whether it is necessary depends on whether you still use the related app, model, history, or project. Select a row to read the item-specific explanation and risk before ticking it.")
                        .font(RetroTypography.smallFont)
                        .foregroundColor(RetroColors.darkText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(RetroTypography.smallFont.bold())
                .foregroundColor(RetroColors.darkText)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Filter by name, full path, app, or category", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    if !searchText.isEmpty {
                        Button("Clear") { searchText = "" }
                            .buttonStyle(RetroButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                Divider().background(RetroColors.insetBorder).padding(.horizontal, 8)
                HSplitView {
                    ScrollView {
                        ResultsTreeView(
                            items: filteredItems(results.foundItems),
                            sortField: $sortField,
                            sortAscending: $sortAscending
                        )
                            .padding(8)
                    }
                    .frame(minWidth: 780, idealWidth: 840)

                    ResultDetailsPane(item: appState.inspectedItem)
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 520, maxHeight: .infinity)
                }
                ActionBar()
                    .padding(8)
            }
            .frame(minWidth: 1140, minHeight: 650)
            .background(RetroColors.windowBackground)
        } else {
            WelcomeView()
        }
    }
}

struct SummaryBar: View {
    let results: ScanResults
    @EnvironmentObject private var appState: AppState

    var selectedSize: Int64 {
        appState.scanResults?.foundItems.filter { $0.isSelected }.reduce(0) { $0 + $1.size } ?? 0
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("Found \(results.foundItems.count) reviewable items").font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
            Spacer()
            Text("Selected: \(selectedSize.humanReadable)").font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
            if results.summary.remnantsFound > 0 {
                Text("App removed: \(results.summary.remnantsFound)").font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
            }
            Text("Measured \(results.scannedPaths.count) paths").font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Results Tree

struct ResultsTreeView: View {
    let items: [FoundItem]
    @Binding var sortField: ResultsSortField
    @Binding var sortAscending: Bool

    private func changeSort(to field: ResultsSortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = field != .size
        }
    }

    var body: some View {
        let appGroups = Dictionary(grouping: items) { item in
            item.primaryApplication?.name ?? "Unclassified"
        }
        let orderedGroupNames = ResultsSorter.groupNames(appGroups, by: sortField, ascending: sortAscending)

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                SortHeader(label: "Item", field: .item, activeField: sortField, ascending: sortAscending, alignment: .leading) {
                    changeSort(to: .item)
                }
                .frame(width: 280, alignment: .leading)
                SortHeader(label: "Category", field: .category, activeField: sortField, ascending: sortAscending, alignment: .leading) {
                    changeSort(to: .category)
                }
                .frame(width: 150, alignment: .leading)
                SortHeader(label: "Size", field: .size, activeField: sortField, ascending: sortAscending, alignment: .trailing) {
                    changeSort(to: .size)
                }
                .frame(width: 90, alignment: .trailing)
                SortHeader(label: "Status and safety", field: .status, activeField: sortField, ascending: sortAscending, alignment: .leading) {
                    changeSort(to: .status)
                }
                .frame(width: 210, alignment: .leading)
            }
            .padding(.vertical, 5)
            .border(RetroColors.insetBorder, width: 1)

            Divider().background(RetroColors.insetBorder).padding(.vertical, 2)

            // Groups
            ForEach(orderedGroupNames, id: \.self) { appName in
                let orderedItems = ResultsSorter.items(appGroups[appName] ?? [], by: sortField, ascending: sortAscending)
                AppGroupSection(name: appName, items: orderedItems, isRemnant: appGroups[appName]?.first?.primaryApplication?.isInstalled == false)
                Divider().background(RetroColors.insetBorder)
            }
        }
    }
}

private struct SortHeader: View {
    let label: String
    let field: ResultsSortField
    let activeField: ResultsSortField
    let ascending: Bool
    let alignment: Alignment
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                if activeField == field {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(RetroTypography.smallFont.bold())
            .foregroundColor(RetroColors.darkText)
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(activeField == field ? "Sorted \(ascending ? "ascending" : "descending"). Click to reverse." : "Sort by \(label).")
        .accessibilityLabel(activeField == field ? "Sort by \(label), currently \(ascending ? "ascending" : "descending")" : "Sort by \(label)")
    }
}

struct AppGroupSection: View {
    let name: String
    let items: [FoundItem]
    let isRemnant: Bool
    @State private var isExpanded = true

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter { $0.isSelected }.reduce(0) { $0 + $1.size } }
    var containsProtectedWorkspace: Bool { items.contains { $0.category == .projectData } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    RetroDisclosureTriangle(isExpanded: isExpanded)
                        .onTapGesture { withAnimation { isExpanded.toggle() } }
                    Text(containsProtectedWorkspace ? "📁 \(name)" : (isRemnant ? "🔍 \(name)" : name))
                        .font(RetroTypography.smallFont).bold()
                        .foregroundColor(RetroColors.darkText)
                }
                .frame(width: 280, alignment: .leading)
                Text(items.count > 1 ? "\(items.count) items" : items.first?.category.displayName ?? "")
                    .font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText).frame(width: 150, alignment: .leading)
                Text(totalSize.humanReadable).font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText).frame(width: 90, alignment: .trailing)
                Text(containsProtectedWorkspace ? "Protected workspace" : (isRemnant ? "App removed" : "\(selectedSize.humanReadable) selected"))
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.darkText)
                    .frame(width: 210, alignment: .leading)
            }
            .padding(.vertical, 5)
            .background(isExpanded ? RetroColors.panelBackground : RetroColors.windowBackground)

            if isExpanded {
                ForEach(items) { item in
                    ResultRow(item: item)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ResultRow: View {
    let item: FoundItem
    @EnvironmentObject private var appState: AppState

    private var assessment: CleanupSafetyPolicy.Assessment {
        appState.cleanupAssessment(for: item)
    }

    private var isInspected: Bool {
        appState.inspectedItemID == item.id
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Button {
                appState.inspectItem(item.id)
            } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        if assessment.canBeSelected || item.isSelected {
                            Color.clear.frame(width: 22, height: 22)
                        } else {
                            Text("–")
                                .font(RetroTypography.smallFont)
                                .foregroundColor(RetroColors.darkText)
                                .frame(width: 22)
                        }
                        Text(item.path.lastPathComponent)
                            .font(RetroTypography.smallFont)
                            .foregroundColor(RetroColors.darkText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 280, alignment: .leading)

                    Text(item.category.displayName)
                        .font(RetroTypography.smallFont)
                        .foregroundColor(RetroColors.darkText)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)

                    Text(item.size.humanReadable)
                        .font(RetroTypography.smallFont)
                        .foregroundColor(RetroColors.darkText)
                        .frame(width: 90, alignment: .trailing)

                    Text("\(item.association.rawValue) · \(item.safetyLevel.rawValue)")
                        .font(RetroTypography.smallFont)
                        .foregroundColor(RetroColors.darkText)
                        .lineLimit(2)
                        .frame(width: 210, alignment: .leading)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click anywhere on this row to view details for \(item.path.path)")
            .accessibilityLabel("Inspect \(item.path.lastPathComponent), \(item.category.displayName), \(item.size.humanReadable), \(item.association.rawValue), \(item.safetyLevel.rawValue)")

            if assessment.canBeSelected || item.isSelected {
                RetroCheckbox(isChecked: item.isSelected) {
                    appState.toggleSelection(for: item.id)
                }
                .padding(.leading, 3)
                .help(assessment.reason)
                .accessibilityLabel(item.isSelected ? "Untick \(item.path.lastPathComponent)" : "Tick \(item.path.lastPathComponent)")
            }
        }
        .background(isInspected ? RetroColors.selectionOverlay : Color.clear)
        .overlay(alignment: .leading) {
            if isInspected {
                Rectangle().fill(RetroColors.selectedItem).frame(width: 4)
            }
        }
    }
}

struct ResultDetailsPane: View {
    let item: FoundItem?
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.path.lastPathComponent)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(RetroColors.darkText)

                    detailBlock("Full path", item.path.path)
                    detailBlock("Measured size", item.size.humanReadable)
                    detailBlock("Category", item.category.displayName)
                    detailBlock("Associated with", item.primaryApplication?.name ?? "Unknown")
                    detailBlock("Association", item.association.rawValue)
                    detailBlock("Safety", "\(item.safetyLevel.icon) \(item.safetyLevel.rawValue)")

                    if let modified = item.modified {
                        detailBlock("Modified", modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let reason = item.reason { detailBlock("Why it was listed", reason) }
                    if let explanation = item.explanation { detailBlock("What it contains", explanation) }

                    Divider().background(RetroColors.insetBorder)
                    Text("Plain-language assessment")
                        .font(RetroTypography.bodyFont.bold())
                        .foregroundColor(RetroColors.darkText)

                    let guide = item.readerGuide
                    detailBlock("What this is", guide.whatItIs)
                    detailBlock("Why it is here", guide.whyItExists)
                    detailBlock("Is it necessary?", guide.necessity)
                    detailBlock("Risk if quarantined", "\(guide.risk.rawValue). \(guide.riskExplanation)")

                    Text("This assessment is rule-based evidence, not proof. Scrub99 cannot know whether you have another complete copy or still depend on this exact path.")
                        .font(RetroTypography.smallFont)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    let assessment = appState.cleanupAssessment(for: item)
                    detailBlock("Cleanup status", assessment.reason)

                    HStack {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.path])
                        }
                        .buttonStyle(RetroButtonStyle())

                        if assessment.canBeSelected || item.isSelected {
                            Button(item.isSelected ? "Untick" : (assessment.requiresProtectedConfirmation ? "Tick for Protected Review" : "Tick for Quarantine")) {
                                appState.toggleSelection(for: item.id)
                            }
                            .buttonStyle(RetroButtonStyle(isDefault: !item.isSelected))
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 30))
                    Text("Select any listed path to inspect it.")
                        .font(RetroTypography.bodyFont)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .padding(16)
        .background(RetroColors.panelBackground)
    }

    private func detailBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(RetroTypography.smallFont.bold())
                .foregroundColor(RetroColors.darkText)
            Text(value)
                .font(RetroTypography.smallFont)
                .foregroundColor(RetroColors.darkText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Action Bar

struct ActionBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button("Clean Up Unnecessary Stuff…") {
                appState.beginGuidedCleanup()
            }
            .buttonStyle(RetroButtonStyle())
            .disabled(appState.recommendedCleanupItems.isEmpty)
            .help(guidedCleanupHelp)
            Spacer()
            Text("Ticked: \(appState.activeCleanupItems.count) · \(appState.activeCleanupItems.reduce(0) { $0 + $1.size }.humanReadable)")
                .font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
            if appState.hasQuarantineItems {
                Button("Undo Last Quarantine") {
                    Task { await appState.undoLastQuarantine() }
                }
                .buttonStyle(RetroButtonStyle())
            }
            Button("View Selected") {
                let item = appState.activeCleanupItems.first ?? appState.scanResults?.foundItems.first
                if let item { appState.inspectItem(item.id) }
            }
            .buttonStyle(RetroButtonStyle())
            Button("Review Quarantine") {
                appState.showCleanupConfirmation = true
            }
            .buttonStyle(RetroButtonStyle(isDefault: true))
            .keyboardShortcut(.return)
            .disabled(appState.activeCleanupItems.isEmpty)
        }
    }

    private var guidedCleanupHelp: String {
        let items = appState.recommendedCleanupItems
        let size = items.reduce(0) { $0 + $1.size }
        if items.isEmpty {
            return "No rule-backed, low-risk cache or log candidates were found."
        }
        return "Review \(items.count) low-risk cache or log path(s), one at a time, totaling \(size.humanReadable)."
    }
}

struct RetroButtonStyle: ButtonStyle {
    let isDefault: Bool
    init(isDefault: Bool = false) { self.isDefault = isDefault }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroTypography.buttonFont)
            .foregroundColor(RetroColors.darkText)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(ZStack(alignment: .topLeading) {
                Rectangle().fill(RetroColors.buttonFace).border(isDefault ? RetroColors.darkText : Color(red: 96/255, green: 96/255, blue: 96/255), width: isDefault ? 2 : 1)
                Rectangle().fill(Color.white).frame(width: 1)
                Rectangle().fill(Color.white).frame(height: 1).offset(y: -1)
            })
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

// MARK: - Error View

struct ErrorView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Scan Failed")
                .font(.title2)
                .bold()
            Text("Something went wrong during the scan.")
                .font(RetroTypography.bodyFont)
                .foregroundColor(RetroColors.darkText)
            Button("Try Again", action: {
                appState.scanState = .idle
                appState.scanResults = nil
            })
            .buttonStyle(RetroButtonStyle(isDefault: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
