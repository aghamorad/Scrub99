// Scrub99 — SettingsView
// App preferences and configuration

import SwiftUI

struct SettingsView: View {
    @AppStorage("showExplanations") private var showExplanations = "Standard"
    @AppStorage("quarantineRetentionDays") private var quarantineRetentionDays = 7

    var body: some View {
        VStack(spacing: 16) {
            Text("Scrub 99 Preferences")
                .font(.title2)
                .bold()

            Divider()
                .background(RetroColors.insetBorder)

            GroupBox("Explanations") {
                Picker("Detail level", selection: $showExplanations) {
                    Text("Brief").tag("Brief")
                    Text("Standard").tag("Standard")
                    Text("Detailed").tag("Detailed")
                }
                .pickerStyle(.radioGroup)
                .padding()
            }

            GroupBox("Cleanup Behavior") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Direct Trash deletion is disabled. Cleanup always uses reversible Scrub99 Quarantine.")
                        .font(RetroTypography.smallFont)

                    TextField("Quarantine retention (days)", value: $quarantineRetentionDays, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                }
                .padding()
            }

            Divider()
                .background(RetroColors.insetBorder)

            GroupBox("About") {
                VStack(spacing: 8) {
                    Text("Scrub 99 — Find leftovers from apps you no longer use.")
                    Text("Version 0.3.0")
                    Text("Built with Swift and SwiftUI.")
                }
                .font(RetroTypography.smallFont)
                .foregroundColor(RetroColors.darkText)
                .multilineTextAlignment(.center)
                .padding()
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .preferredColorScheme(.light)
    }
}
