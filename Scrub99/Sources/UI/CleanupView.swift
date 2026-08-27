// Scrub99 — CleanupView

import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var appState: AppState
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
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(RetroColors.darkText)

            RetroInsetPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You are about to move these paths into Scrub99 Quarantine:")
                        .font(RetroTypography.bodyFont).bold()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(selectedItems) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.path.path)
                                            .font(RetroTypography.smallFont)
                                            .textSelection(.enabled)
                                        Text("\(item.readerGuide.risk.rawValue) · \(item.readerGuide.necessity)")
                                            .font(RetroTypography.smallFont)
                                            .foregroundColor(item.readerGuide.risk == .low ? RetroColors.secondaryText : RetroColors.criticalText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Text(item.size.humanReadable)
                                        .font(RetroTypography.smallFont)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 170)

                    if !protectedItems.isEmpty {
                        HStack {
                            Text("Protected user data")
                                .font(RetroTypography.smallFont.bold())
                                .foregroundColor(RetroColors.criticalText)
                            Spacer()
                            Text("\(protectedItems.count) path(s) · \(protectedItems.reduce(0) { $0 + $1.size }.humanReadable)")
                                .font(RetroTypography.smallFont)
                                .foregroundColor(RetroColors.criticalText)
                        }
                    }

                    Divider().background(RetroColors.insetBorder)

                    HStack {
                        Text("Total:").font(RetroTypography.smallFont).bold()
                        Spacer()
                        Text(totalSize.humanReadable).font(RetroTypography.smallFont).bold()
                    }
                }
                .padding(12)
            }

            if !protectedItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The selection includes projects or personal files. Moving them makes their original paths disappear until restored. Type QUARANTINE to authorize this reversible move.")
                        .font(RetroTypography.smallFont)
                        .foregroundColor(RetroColors.criticalText)
                    TextField("Type QUARANTINE", text: $protectedConfirmation)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 12)
            }

            if !blockedItems.isEmpty {
                Text("One or more selected paths became blocked after the scan. Untick them and scan again.")
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.criticalText)
                    .padding(.horizontal, 12)
            }

            if selectedItems.contains(where: { $0.category == .downloadedModels }) {
                Text("Caution: Models will need to be redownloaded if you use these apps again.")
                    .font(RetroTypography.smallFont).foregroundColor(RetroColors.warningText)
                    .padding(.horizontal, 12)
            }
            Text("Nothing is sent directly to Trash. Every successful move receives an append-only manifest and can be restored with Undo Last Quarantine.")
                .font(RetroTypography.smallFont)
                .foregroundColor(RetroColors.darkText)
                .padding(.horizontal, 12)

            if let errorMessage = appState.lastErrorMessage {
                Text(errorMessage)
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.criticalText)
                    .padding(.horizontal, 12)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    appState.lastErrorMessage = nil
                    appState.showCleanupConfirmation = false
                }
                .buttonStyle(RetroButtonStyle())
                Button("Move to Quarantine", action: runCleanup)
                    .buttonStyle(RetroButtonStyle(isDefault: true))
                    .keyboardShortcut(.return)
                    .disabled(!canProceed)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .padding(16)
        .preferredColorScheme(.light)
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
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func review(_ item: FoundItem) -> some View {
        Text("Clean Up Unnecessary Stuff")
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundColor(RetroColors.darkText)

        Text("Candidate \(currentIndex + 1) of \(items.count)")
            .font(RetroTypography.smallFont)
            .foregroundColor(RetroColors.secondaryText)

        RetroProgressView(
            progress: items.isEmpty ? 0 : Float(currentIndex) / Float(items.count),
            label: ""
        )

        Text("Scrub99 classified this as a rule-backed, low-risk cache or log candidate. That is a recommendation, not proof that you do not need it. Decide on this item before Scrub99 proceeds.")
            .font(RetroTypography.smallFont)
            .foregroundColor(RetroColors.darkText)
            .fixedSize(horizontal: false, vertical: true)

        RetroInsetPanel {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.path.lastPathComponent)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    explanation("Exact path", item.path.path)
                    explanation("Measured size", item.size.humanReadable)

                    let guide = item.readerGuide
                    explanation("What this is", guide.whatItIs)
                    explanation("Why it is there", guide.whyItExists)
                    explanation("Is it necessary?", guide.necessity)
                    explanation("Risk if quarantined", "\(guide.risk.rawValue). \(guide.riskExplanation)")

                    Text("If approved, only this path is moved into Scrub99 Quarantine. Nothing is sent to Trash, and the move is recorded for restoration.")
                        .font(RetroTypography.smallFont.bold())
                        .foregroundColor(RetroColors.darkText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .font(RetroTypography.smallFont)
                .foregroundColor(RetroColors.criticalText)
                .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        HStack(spacing: 12) {
            Button("Stop") {
                appState.showGuidedCleanup = false
            }
            .buttonStyle(RetroButtonStyle())

            Spacer()

            Button("Keep This Item") {
                keptCount += 1
                advance()
            }
            .buttonStyle(RetroButtonStyle(isDefault: true))
            .disabled(isWorking)

            Button(isWorking ? "Moving…" : "Move This Item to Quarantine") {
                quarantine(item)
            }
            .buttonStyle(RetroButtonStyle())
            .disabled(isWorking)
        }
    }

    private var completion: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42))
                .foregroundColor(.green)
            Text("Guided Review Complete")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
            Text("Moved \(cleanedCount) item(s), totaling \(cleanedSize.humanReadable), into reversible quarantine. Kept \(keptCount) item(s) in place.")
                .font(RetroTypography.bodyFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") {
                appState.showGuidedCleanup = false
            }
            .buttonStyle(RetroButtonStyle(isDefault: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func explanation(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(RetroTypography.smallFont.bold())
            Text(value)
                .font(RetroTypography.smallFont)
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
