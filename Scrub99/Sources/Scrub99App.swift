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

                Button("Review Selected for Quarantine") {
                    if appState.activeCleanupItems.isEmpty {
                        appState.lastErrorMessage = "Select at least one reviewable item first."
                    } else {
                        appState.showCleanupConfirmation = true
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Manage Quarantine") {
                    if appState.hasQuarantineItems {
                        appState.showQuarantineManagement = true
                    } else {
                        appState.lastErrorMessage = "Scrub99 Quarantine is currently empty."
                    }
                }

                Button("Undo Last Quarantine") {
                    Task { await appState.undoLastQuarantine() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

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
