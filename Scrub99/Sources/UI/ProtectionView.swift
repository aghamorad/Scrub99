import AppKit
import SwiftUI

/// The other side of the ledger: not what Scrub 99 has done, but what it has
/// agreed never to do. Every row here is a path the reader took off the table,
/// and every row offers the way back on.
struct ProtectionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    private var entries: [ProtectionList.Entry] { appState.protectionEntries }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Left Alone")
                        .font(style.titleFont)
                    Text("Everything you have told Scrub 99 to stop offering. It will not touch these again.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
                Spacer()
                ThemeButton(
                    title: "Show Me the File",
                    systemImage: "doc.text",
                    help: "Opens Finder at the plain JSON file holding this list, so you can read it or copy it without Scrub 99."
                ) { revealListFile() }
            }

            ThemePanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What this list is")
                        .font(style.labelFont)
                    Text("Nothing on this list has been moved, deleted, or touched — that is the point of it. These are paths Scrub 99 would otherwise have offered you, and you said no. It now reports them as locked, on this and every later scan, so you stop being asked.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Protecting a folder covers everything inside it, which is why one entry can quiet a great many rows. Taking it off the list never exposes anything to cleanup by itself: the rows simply become ordinary findings again, judged by the same rules as everything else.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(appState.protectionList.fileURL.homeAbbreviatedPath)
                        .font(style.pathFont)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let note = appState.protectionList.loadFailureNote {
                ThemePanel(padding: 10) {
                    Text(note)
                        .font(style.smallFont)
                        .foregroundColor(style.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("Nothing is on the left-alone list.")
                        .font(style.bodyFont)
                    Text("Everything Scrub 99 finds is judged by its rules alone right now. When something keeps coming back that you know you want, open it and press “Leave It Alone”. It stops being offered, on this scan and every later one.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Text(entries.isEmpty
                     ? "Nothing is left alone."
                     : "\(entries.count) path\(entries.count == 1 ? "" : "s") Scrub 99 will not offer\(entries.count == 1 ? "" : ", and everything inside any of them")")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                Spacer()
                if entries.count > 1 {
                    ThemeButton(
                        title: "Offer Everything Again",
                        help: "Empties this list. It moves nothing and deletes nothing — those paths just go back to being judged by Scrub 99's rules like everything else."
                    ) { appState.releaseAllProtection() }
                }
                ThemeButton(title: "Done", isPrimary: true) { appState.showProtectionList = false }
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
        .preferredColorScheme(style.isRetro ? .light : nil)
    }

    private func entryRow(_ entry: ProtectionList.Entry) -> some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.stillExists ? "still on disk" : "no longer at that path")
                        .font(style.smallFont)
                        .foregroundColor(entry.stillExists ? style.secondaryText : style.caution)
                        .fixedSize()
                }
                Text(entry.displayPath)
                    .font(style.pathFont)
                    .foregroundColor(style.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Text("\(entry.kind) · left alone since \(entry.added.formatted(date: .abbreviated, time: .shortened))")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                HStack {
                    if entry.stillExists {
                        ThemeButton(
                            title: "Show It in Finder",
                            systemImage: "magnifyingglass",
                            help: "Opens Finder with this path selected, so you can see what you protected before deciding whether to release it."
                        ) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                        }
                    }
                    ThemeButton(
                        title: "Offer It Again",
                        systemImage: "arrow.uturn.backward",
                        isPrimary: true,
                        help: "Takes this off the list. It does not clean anything and it does not delete anything — the path goes back to being judged by Scrub 99's normal rules."
                    ) { appState.releaseProtection(path: entry.path) }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A file that does not exist yet is worth opening the folder of rather than
    /// reporting a failure: the folder may not exist either, in which case the
    /// home folder is the useful place to land.
    private func revealListFile() {
        let fileManager = FileManager.default
        let url = appState.protectionList.fileURL
        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSHomeDirectory())])
        }
    }
}
