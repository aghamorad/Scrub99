// Scrub99 — SettingsView

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

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

            Section("Scanning") {
                Toggle("Also measure folders Scrub 99 has no rule for", isOn: Binding(
                    get: { appState.deepSweep },
                    set: { appState.setDeepSweep($0) }
                ))

                Text(appState.deepSweep
                     ? "The deep sweep is on. It measures the folders where undeclared data collects — usually where the larger wins are, since nothing else reports them. It adds up to a minute to a scan, and anything it finds can only be cleaned after an extra typed confirmation."
                     : "The deep sweep is off. Scrub 99 will only report what one of its \(RuleEngine.shared.applications.count) rules describes, which means it will miss whatever those rules do not cover.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Safety") {
                safetyLine("Scrub 99 never ticks anything for you. Every scan starts with an empty selection.", icon: "checkmark.square")
                safetyLine("Cleaning moves items into Quarantine. Nothing is deleted, and everything moved can be put back.", icon: "arrow.uturn.backward")
                safetyLine("Anything Scrub 99 cannot prove is replaceable is shown but locked, with the reason stated.", icon: "lock.fill")
            }

            Section("Where quarantine lives") {
                Text(CleanupEngine().quarantineURL.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)

                Text(CleanupEngine().quarantineExists
                     ? "That is the whole path. It is a normal folder at the top of your home folder, in plain sight — not hidden inside Library or an application support folder. Things can be dragged back out of it by hand, without Scrub 99."
                     : "That is where it will be. The folder does not exist yet because nothing has been quarantined; it is created the first time you clean something. It sits at the top of your home folder in plain sight — not hidden inside Library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Show Me the Folder") { CleanupEngine().revealQuarantine() }
                    .help("Open Scrub 99's Quarantine in the Finder. It is an ordinary folder you can browse, and files can be dragged back out of it by hand without the app.")
            }

            Section("About") {
                LabeledContent("App", value: "Scrub 99")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                LabeledContent("Rules loaded", value: "\(RuleEngine.shared.applications.count)")
                LabeledContent("Purpose", value: "Find storage, explain it, and move nothing without you.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540, height: 560)
    }

    private func safetyLine(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var themeDescription: String {
        switch appState.currentTheme {
        case .classic9:
            return "Mac OS 9 / Platinum is the original retro interface: monospaced type, drawn buttons, light appearance. Every screen and button in Scrub 99 is identical to the other theme — only the look changes."
        case .liquidGlass:
            return "Liquid Glass uses native macOS navigation, materials, and controls, with real Liquid Glass surfaces on macOS 26 and later. Every screen and button in Scrub 99 is identical to the other theme — only the look changes."
        }
    }
}
