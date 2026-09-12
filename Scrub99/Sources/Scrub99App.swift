// Scrub99 - App Entry Point

import SwiftUI

@main
struct Scrub99App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Scrub 99") {
                Button("Scan My Mac") {
                    appState.startScan()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Cancel Scan") {
                    appState.cancelScan()
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                // The read-only rehearsal sits above the acting menu item on
                // purpose: the cheapest way to be sure about Scrub 99 is to
                // watch it decide first, and that has to be reachable without
                // pressing anything that moves a file.
                Button("What Would Happen… (Rehearsal)") {
                    if appState.recommendedCleanupItems.isEmpty {
                        appState.lastErrorMessage = "Scrub 99 has no recommendations to rehearse yet. Scan first."
                    } else {
                        appState.showCleanupPreview = true
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Review Selected for Quarantine") {
                    if appState.activeCleanupItems.isEmpty {
                        appState.lastErrorMessage = "Select at least one reviewable item first."
                    } else {
                        appState.showCleanupConfirmation = true
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                // Always opens, empty or not. Refusing to open a window and
                // printing "the quarantine is empty" made the one screen that
                // explains where your files go the one screen you could not look
                // at — and it is the screen that says where the folder even is.
                Button("Manage Quarantine") {
                    appState.showQuarantineManagement = true
                }

                Button("Undo Last Quarantine") {
                    Task { await appState.undoLastQuarantine() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button("Show Quarantine Folder in Finder") {
                    CleanupEngine().revealQuarantine()
                }

                // Same rule as Manage Quarantine: always openable, even when the
                // list is empty. The empty list is the one that most needs saying
                // out loud, because the screen is where the whole idea of leaving
                // something alone is explained.
                Button("Left Alone") {
                    appState.showProtectionList = true
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Picker("Theme", selection: Binding(
                    get: { appState.currentTheme },
                    set: { appState.setTheme($0) }
                )) {
                    ForEach(AppState.Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
