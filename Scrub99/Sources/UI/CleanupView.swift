// Scrub99 — CleanupView

import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @State private var protectedConfirmation = ""

    var selectedItems: [FoundItem] {
        appState.scanResults?.foundItems.filter { $0.isSelected } ?? []
    }

    var totalSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var protectedItems: [FoundItem] {
        selectedItems.filter { appState.cleanupAssessment(for: $0).requiresProtectedConfirmation }
    }

    var blockedItems: [FoundItem] {
        selectedItems.filter { !appState.cleanupAssessment(for: $0).canBeSelected }
    }

    var protectedConfirmationMatches: Bool {
        protectedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "QUARANTINE"
    }

    var canProceed: Bool {
        !selectedItems.isEmpty && blockedItems.isEmpty && (protectedItems.isEmpty || protectedConfirmationMatches)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Review Quarantine")
                .font(style.titleFont)
                .foregroundColor(style.text)

            ThemePanel(padding: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You are about to move these paths into Quarantine:")
                        .font(style.bodyFont).bold()

                    Text("Quarantine is a real folder at \(CleanupEngine().quarantineURL.path). Nothing here is deleted. Each item below keeps its full contents and the exact path it came from, so it can be put back.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(selectedItems) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.path.path)
                                            .font(style.smallFont)
                                            .textSelection(.enabled)
                                        Text("\(item.readerGuide.risk.rawValue) · \(item.readerGuide.necessity)")
                                            .font(style.smallFont)
                                            .foregroundColor(item.readerGuide.risk == .low ? style.secondaryText : style.negative)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Text(item.size.sizeDescription)
                                        .font(style.smallFont)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 170)

                    if !protectedItems.isEmpty {
                        HStack {
                            Text("Protected user data")
                                .font(style.smallFont.bold())
                                .foregroundColor(style.negative)
                            Spacer()
                            Text("\(protectedItems.count) path(s) · \(protectedItems.reduce(0) { $0 + $1.size }.sizeDescription)")
                                .font(style.smallFont)
                                .foregroundColor(style.negative)
                        }
                    }

                    Divider().background(style.border)

                    HStack {
                        Text("Total:").font(style.smallFont).bold()
                        Spacer()
                        Text(totalSize.sizeDescription).font(style.smallFont).bold()
                    }
                }
            }

            if !protectedItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The selection includes projects or personal files. Moving them makes their original paths disappear until restored. Type QUARANTINE to authorize this reversible move.")
                        .font(style.smallFont)
                        .foregroundColor(style.negative)
                    TextField("Type QUARANTINE", text: $protectedConfirmation)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 12)
            }

            if !blockedItems.isEmpty {
                Text("One or more selected paths became blocked after the scan. Untick them and scan again.")
                    .font(style.smallFont)
                    .foregroundColor(style.negative)
                    .padding(.horizontal, 12)
            }

            if selectedItems.contains(where: { $0.category == .downloadedModels }) {
                Text("Caution: Models will need to be redownloaded if you use these apps again.")
                    .font(style.smallFont).foregroundColor(style.caution)
                    .padding(.horizontal, 12)
            }
            Text("Nothing is sent to the Trash. Each move is written down next to the item it moved — a dated folder holding the item and a record of where it came from — so it can be put back by Scrub 99, or by you, in Finder.")
                .font(style.smallFont)
                .foregroundColor(style.text)
                .padding(.horizontal, 12)

            if let errorMessage = appState.lastErrorMessage {
                Text(errorMessage)
                    .font(style.smallFont)
                    .foregroundColor(style.negative)
                    .padding(.horizontal, 12)
            }

            Spacer()

            HStack(spacing: 12) {
                ThemeButton(title: "Cancel", help: "Closes this screen without moving anything.") {
                    appState.lastErrorMessage = nil
                    appState.showCleanupConfirmation = false
                }
                ThemeButton(
                    title: "Move to Quarantine",
                    isPrimary: true,
                    isEnabled: canProceed,
                    help: "Moves the ticked paths into the quarantine folder. Nothing is deleted, and every move can be put back."
                ) { runCleanup() }
                    .keyboardShortcut(.return)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .padding(16)
        .preferredColorScheme(style.isRetro ? .light : nil)
    }

    private func runCleanup() {
        Task {
            do {
                appState.lastErrorMessage = nil
                let engine = CleanupEngine()
                let result = try await engine.cleanup(
                    items: selectedItems,
                    allowReviewOnly: !protectedItems.isEmpty
                )

                appState.recordCleanupResult(result)
                appState.showCleanupConfirmation = false
            } catch {
                appState.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

struct GuidedCleanupView: View {
    let items: [FoundItem]
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @State private var currentIndex = 0
    @State private var cleanedCount = 0
    @State private var cleanedSize: Int64 = 0
    @State private var keptCount = 0
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var currentItem: FoundItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var body: some View {
        VStack(spacing: 16) {
            if let item = currentItem {
                review(item)
            } else {
                completion
            }
        }
        .frame(minWidth: 660, minHeight: 580)
        .padding(18)
        .preferredColorScheme(style.isRetro ? .light : nil)
    }

    @ViewBuilder
    private func review(_ item: FoundItem) -> some View {
        Text("Clean Up Unnecessary Stuff")
            .font(style.titleFont)
            .foregroundColor(style.text)

        Text("Candidate \(currentIndex + 1) of \(items.count)")
            .font(style.smallFont)
            .foregroundColor(style.secondaryText)

        Group {
            if style.isRetro {
                RetroProgressView(
                    progress: items.isEmpty ? 0 : Float(currentIndex) / Float(items.count),
                    label: ""
                )
            } else {
                ProgressView(value: items.isEmpty ? 0 : Double(currentIndex) / Double(items.count))
                    .progressViewStyle(.linear)
            }
        }

        Text("Scrub99 classified this as a rule-backed, low-risk cache or log candidate. That is a recommendation, not proof that you do not need it. Decide on this item before Scrub99 proceeds.")
            .font(style.smallFont)
            .foregroundColor(style.text)
            .fixedSize(horizontal: false, vertical: true)

        ThemePanel(padding: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.path.lastPathComponent)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    explanation("Exact path", item.path.path)
                    explanation("Measured size", item.size.sizeDescription)

                    let guide = item.readerGuide
                    explanation("What this is", guide.whatItIs)
                    explanation("Why it is there", guide.whyItExists)
                    explanation("Is it necessary?", guide.necessity)
                    explanation("Risk if quarantined", "\(guide.risk.rawValue). \(guide.riskExplanation)")

                    Text("If approved, only this one path moves into Quarantine, at \(CleanupEngine().quarantineURL.path). Nothing goes to the Trash, and the record of where it came from is written alongside it.")
                        .font(style.smallFont.bold())
                        .foregroundColor(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .font(style.smallFont)
                .foregroundColor(style.negative)
                .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        HStack(spacing: 12) {
            ThemeButton(title: "Stop", help: "Closes the guided review. Anything not yet moved stays exactly where it is.") {
                appState.showGuidedCleanup = false
            }

            Spacer()

            ThemeButton(
                title: "Keep This Item",
                isPrimary: true,
                isEnabled: !isWorking,
                help: "Leaves this item alone and moves on to the next candidate."
            ) {
                keptCount += 1
                advance()
            }

            ThemeButton(
                title: isWorking ? "Moving…" : "Move This Item to Quarantine",
                isEnabled: !isWorking,
                help: "Moves this one path into the quarantine folder. Nothing is deleted, and it can be put back."
            ) {
                quarantine(item)
            }
        }
    }

    private var completion: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42))
                .foregroundColor(.green)
            Text("Guided Review Complete")
                .font(style.titleFont)
            Text("Moved \(cleanedCount) item(s), totaling \(cleanedSize.humanReadable), into Quarantine. Kept \(keptCount) item(s) in place.")
                .font(style.bodyFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing was deleted. The moved items are sitting in \(CleanupEngine().quarantineURL.path), and each one can be put back exactly where it came from.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ThemeButton(title: "Done", isPrimary: true, help: "Closes the guided review.") {
                appState.showGuidedCleanup = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func explanation(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(style.smallFont.bold())
            Text(value)
                .font(style.smallFont)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func advance() {
        errorMessage = nil
        currentIndex += 1
    }

    private func quarantine(_ item: FoundItem) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let result = try await CleanupEngine().cleanup(items: [item])
                guard result.successCount == 1 else {
                    errorMessage = result.movedItems.first.map { moved in
                        if case .failed(_, let message) = moved { return message }
                        return "The item was not moved."
                    } ?? "The item was not moved."
                    return
                }
                cleanedCount += 1
                cleanedSize += result.totalSize
                appState.recordCleanupResult(result)
                advance()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - What would happen

/// A rehearsal for a cleanup.
///
/// It reads the same list Scrub 99 would act on and writes down what it would
/// do with each thing, including which items it would refuse and why. The
/// refusals matter most: the owning application being open is otherwise found
/// out only as an error after the button has already been pressed, when the
/// reader has no way to tell whether the refusal was their fault or the app's.
///
/// Nothing here moves, and nothing is ticked on the reader's behalf — the
/// sheet exists to be read, and it says so.
struct CleanupPreviewView: View {
    let items: [FoundItem]
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @State private var runningApps: [ApplicationRef] = []
    @State private var hasChecked = false

    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    /// The items whose owning application is open. The engine refuses these
    /// outright; naming them here is what turns the refusal into something the
    /// reader can act on before it happens.
    private var blockedItems: [FoundItem] {
        items.filter { item in
            guard let app = item.primaryApplication else { return false }
            return runningApps.contains(app)
        }
    }

    private var movableItems: [FoundItem] {
        let blocked = Set(blockedItems.map(\.id))
        return items.filter { !blocked.contains($0.id) }
    }

    /// Everything in the scan that is not on this list, tallied by the reason
    /// Scrub 99 gives for holding it back. This is the part no other screen
    /// shows: what was considered and rejected, rather than what was found.
    private var heldBack: [(reason: String, count: Int, size: Int64)] {
        let included = Set(items.map(\.id))
        var tally: [String: (count: Int, size: Int64)] = [:]
        for item in appState.scanResults?.foundItems ?? [] where !included.contains(item.id) {
            let reason = appState.cleanupAssessment(for: item).reason
            var entry = tally[reason] ?? (count: 0, size: 0)
            entry.count += 1
            entry.size += item.size
            tally[reason] = entry
        }
        return tally
            .map { (reason: $0.key, count: $0.value.count, size: $0.value.size) }
            .sorted { $0.size > $1.size }
    }

    var body: some View {
        // The reading scrolls and the buttons do not. A rehearsal that pushes
        // its own buttons off the bottom of the window, or clips its own title,
        // is one more screen the reader has to fight.
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What Would Happen")
                        .font(style.titleFont)
                        .foregroundColor(style.text)

                    Text("Nothing has moved. Scrub 99 read the \(items.count) items it recommends cleaning and wrote down what it would do with each. Close this window and your Mac is exactly as it was.")
                        .font(style.smallFont)
                        .foregroundColor(style.text)
                        .fixedSize(horizontal: false, vertical: true)

                    section("The list, item by item") {
                        ThemePanel(padding: 8) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(items) { item in
                                        previewRow(item)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                        }
                        // Short enough that the rest of the report fits under it
                        // without the window having to scroll. This list scrolls on
                        // its own, so nothing is lost by giving it less room — and
                        // the summary below it is the part that has to be read.
                        .frame(height: 148)
                    }

                    if hasChecked {
                        Text(checkSummary)
                            .font(style.smallFont)
                            .foregroundColor(runningApps.isEmpty ? style.text : style.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("What it would leave alone, and why") {
                        VStack(alignment: .leading, spacing: 4) {
                            if heldBack.isEmpty {
                                Text("Everything measured in this scan is on the list above.")
                                    .font(style.smallFont)
                                    .foregroundColor(style.secondaryText)
                            } else {
                                ForEach(heldBack.prefix(6), id: \.reason) { held in
                                    Text("· \(held.reason) — \(held.count) item(s), \(held.size.sizeDescription)")
                                        .font(style.smallFont)
                                        .foregroundColor(style.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Scrub 99 holds these back on its own. You can still tick any of them by hand in the list, but it will never tick them for you, and it will say this again before it moves them.")
                                    .font(style.smallFont)
                                    .foregroundColor(style.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    ThemePanel(padding: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing is deleted, and nothing is ticked for you")
                                .font(style.smallFont.bold())
                            Text("Moving happens only after you tick items in the list and press Review Ticked. If you did move them, \(totalSize.sizeDescription) would be sitting in \(CleanupEngine().quarantineURL.path) — a normal folder, not a hidden one — each item keeping its full contents and a written record of where it came from, so it can be put back by Scrub 99 or by you in Finder.")
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                ThemeButton(
                    title: "Check Again",
                    systemImage: "arrow.clockwise",
                    help: "Look for open applications again. Use this after you quit one: the list above and the count of what would move both change to match."
                ) { Task { await check() } }
                    .keyboardShortcut("r", modifiers: .command)

                Spacer()

                // Escape as well as the button. A read-only sheet is the last
                // place that should trap anyone.
                ThemeButton(
                    title: "Close",
                    isPrimary: true,
                    help: "Close the rehearsal. Nothing has moved and nothing will."
                ) { appState.showCleanupPreview = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        // Tall enough that the ordinary rehearsal fits without scrolling. When
        // it does not fit, the scroll is there and the buttons stay put — but a
        // screen that is meant to be read should not open on a sentence sliced
        // through the middle.
        .frame(minWidth: 720, minHeight: 650, maxHeight: 700)
        .padding(16)
        .preferredColorScheme(style.isRetro ? .light : nil)
        // Escape closes the rehearsal from anywhere in it, keyboard focus or not.
        .onExitCommand { appState.showCleanupPreview = false }
        .task { await check() }
    }

    /// Open applications, said once each. Several rules can name the same
    /// helper, and the raw list then reads "log, log, log, log…" — which looks
    /// like a bug in Scrub 99 rather than a fact about the machine.
    private var openAppNames: [String] {
        Array(Set(runningApps.map(\.name))).sorted()
    }

    private var openAppsPhrase: String {
        let names = openAppNames
        guard names.count > 6 else { return names.joined(separator: ", ") }
        return names.prefix(6).joined(separator: ", ") + ", and \(names.count - 6) more"
    }

    private var checkSummary: String {
        runningApps.isEmpty
            ? "Checked again: no application owning these items is open, so Scrub 99 would move the whole list."
            : "\(openAppsPhrase) \(openAppNames.count == 1 ? "is" : "are") still open. Scrub 99 would move \(movableItems.count) of the \(items.count) and refuse the \(blockedItems.count) belonging to \(openAppNames.count == 1 ? "it" : "them")."
    }

    private func previewRow(_ item: FoundItem) -> some View {
        let isBlocked = blockedItems.contains { $0.id == item.id }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.path.lastPathComponent)
                    .font(style.smallFont.bold())
                Spacer()
                Text(item.size.sizeDescription)
                    .font(style.smallFont)
            }
            Text(item.path.deletingLastPathComponent().path)
                .font(style.pathFont)
                .foregroundColor(style.secondaryText)
                .lineLimit(1)
                .truncationMode(.head)
            Text("\(item.safetyLevel.rawValue) · \(item.lastUsedDate == nil ? "no dates recorded" : "last used \(item.lastUsedDescription)")")
                .font(style.smallFont)
                .foregroundColor(item.lastUsedIsStale ? style.caution : style.secondaryText)
            if isBlocked {
                Text("\(item.primaryApplication?.name ?? "Its application") is open, so Scrub 99 would skip this one.")
                    .font(style.smallFont)
                    .foregroundColor(style.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(style.smallFont.bold())
                .foregroundColor(style.secondaryText)
            content()
        }
    }

    private func check() async {
        runningApps = (try? await CleanupEngine().checkRunningApps(items)) ?? []
        hasChecked = true
    }
}

