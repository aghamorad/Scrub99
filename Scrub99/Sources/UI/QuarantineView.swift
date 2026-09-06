import AppKit
import SwiftUI

struct QuarantineView: View {
    @EnvironmentObject private var appState: AppState
    @State private var entries: [QuarantineEntry] = []
    @State private var pendingPermanentDeletion: QuarantineEntry?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scrub99 Quarantine")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    Text("Items remain recoverable here until you permanently delete them.")
                        .font(RetroTypography.smallFont)
                }
                Spacer()
                Button("Reveal Folder") { CleanupEngine().revealQuarantine() }
                    .buttonStyle(RetroButtonStyle())
            }

            RetroInsetPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exact quarantine location")
                        .font(RetroTypography.smallFont.bold())
                    Text(CleanupEngine().quarantineURL.path)
                        .font(RetroTypography.smallFont)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }

            if entries.isEmpty {
                Spacer()
                Text("Quarantine is empty.")
                    .font(RetroTypography.bodyFont)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            quarantineRow(entry)
                        }
                    }
                }
            }

            if let error = appState.lastErrorMessage {
                Text(error)
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.criticalText)
                    .textSelection(.enabled)
            }

            HStack {
                Text("\(entries.count) item(s) · \(entries.reduce(0) { $0 + $1.size }.humanReadable)")
                    .font(RetroTypography.smallFont)
                Spacer()
                Button("Close") { appState.showQuarantineManagement = false }
                    .buttonStyle(RetroButtonStyle(isDefault: true))
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 540)
        .preferredColorScheme(.light)
        .onAppear { reload() }
        .alert("Delete permanently?", isPresented: Binding(
            get: { pendingPermanentDeletion != nil },
            set: { if !$0 { pendingPermanentDeletion = nil } }
        )) {
            Button("Delete Permanently", role: .destructive) {
                guard let entry = pendingPermanentDeletion else { return }
                appState.permanentlyDeleteQuarantineEntries([entry])
                pendingPermanentDeletion = nil
                reload()
            }
            Button("Cancel", role: .cancel) { pendingPermanentDeletion = nil }
        } message: {
            if let entry = pendingPermanentDeletion {
                Text("This permanently removes \(entry.size.humanReadable) from:\n\(entry.originalPath)\n\nIt cannot be restored afterward.")
            }
        }
    }

    private func quarantineRow(_ entry: QuarantineEntry) -> some View {
        RetroInsetPanel {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.originalPath)
                        .font(RetroTypography.smallFont.bold())
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Text(entry.size.humanReadable)
                        .font(RetroTypography.smallFont)
                }
                Text("Stored at: \(entry.quarantinePath)")
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Text("\(entry.category) · \(entry.appName ?? "Unclassified") · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(RetroTypography.smallFont)
                    .foregroundColor(RetroColors.secondaryText)
                HStack {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.quarantinePath)])
                    }
                    .buttonStyle(RetroButtonStyle())
                    Button("Restore") {
                        appState.restoreQuarantineEntry(entry)
                        reload()
                    }
                    .buttonStyle(RetroButtonStyle(isDefault: true))
                    Spacer()
                    Button("Delete Permanently") { pendingPermanentDeletion = entry }
                        .buttonStyle(RetroButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    private func reload() {
        entries = appState.quarantineEntries()
    }
}
