// Scrub99 - SettingsView

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("showExplanations") private var showExplanations = "Standard"
    @AppStorage("quarantineRetentionDays") private var quarantineRetentionDays = 7

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { appState.currentTheme },
                    set: { appState.setTheme($0) }
                )) {
                    ForEach(AppState.Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Text(themeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Explanations") {
                Picker("Detail level", selection: $showExplanations) {
                    Text("Brief").tag("Brief")
                    Text("Standard").tag("Standard")
                    Text("Detailed").tag("Detailed")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Cleanup") {
                Text("Cleanup always uses reversible Scrub99 Quarantine. Direct Trash deletion remains disabled.")
                    .font(.callout)

                Stepper(
                    "Quarantine retention: \(quarantineRetentionDays) day\(quarantineRetentionDays == 1 ? "" : "s")",
                    value: $quarantineRetentionDays,
                    in: 1...90
                )
            }

            Section("About") {
                LabeledContent("App", value: "Scrub 99")
                LabeledContent("Version", value: "0.3.0")
                LabeledContent("Purpose", value: "Find and safely review application leftovers.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 430)
    }

    private var themeDescription: String {
        switch appState.currentTheme {
        case .classic9:
            return "Mac OS 9 / Platinum keeps Scrub99's original retro interface, typography, controls, and light appearance."
        case .liquidGlass:
            return "Liquid Glass uses native macOS navigation, materials, controls, and real Liquid Glass surfaces on macOS 26 and later."
        }
    }
}
