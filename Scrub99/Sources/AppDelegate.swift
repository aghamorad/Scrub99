// Scrub99 — AppDelegate
// Handles app lifecycle and permissions

import Foundation
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the retro cursor
        setupAppearance()

        // Load rules
        RuleEngine.shared.loadRules()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: { !$0.isMiniaturized }) ?? sender.windows.first {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    private func setupAppearance() {
        // Ensure the app doesn't appear in the dock
        NSApp.setActivationPolicy(.regular)

        // Set up menu
        setupMenu()
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: "About Scrub 99", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Scrub 99", action: #selector(NSApp.terminate), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
        let appMenuTitle = NSMenuItem()
        appMenuTitle.submenu = appMenu
        mainMenu.addItem(appMenuTitle)
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Scrub 99"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        alert.informativeText = "Version \(version)\n\nFind leftovers from apps you no longer use.\n\nBuilt with Swift and SwiftUI.\n© 2026"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
