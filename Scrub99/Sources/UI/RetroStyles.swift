// Scrub99 — Retro UI Styles
// Mac OS 9 / Platinum interface styling for SwiftUI

import SwiftUI

// MARK: - Color Palette (Mac OS 9)

struct RetroColors {
    // Classic Mac OS 9 palette
    static let titleBarGradientStart = Color(red: 176/255, green: 182/255, blue: 198/255)
    static let titleBarGradientEnd = Color(red: 130/255, green: 140/255, blue: 160/255)
    static let windowBackground = Color(red: 242/255, green: 242/255, blue: 238/255)
    static let panelBackground = Color(red: 226/255, green: 228/255, blue: 224/255)
    static let buttonFace = Color(red: 238/255, green: 238/255, blue: 234/255)
    static let buttonHighlight = Color.white
    static let buttonShadow = Color(red: 128/255, green: 128/255, blue: 128/255)
    static let darkText = Color(red: 20/255, green: 20/255, blue: 20/255)
    static let secondaryText = Color(red: 48/255, green: 48/255, blue: 48/255)
    static let warningText = Color(red: 108/255, green: 58/255, blue: 0/255)
    static let criticalText = Color(red: 148/255, green: 18/255, blue: 18/255)
    static let lightText = Color.white
    static let insetBorder = Color(red: 128/255, green: 128/255, blue: 128/255)
    static let outsetBorder = Color.white
    static let stripedBackground = Color(red: 200/255, green: 200/255, blue: 200/255)
    static let selectedItem = Color(red: 36/255, green: 91/255, blue: 168/255)
    static let selectionOverlay = Color(red: 190/255, green: 214/255, blue: 246/255)

    // Modern system colors
    static let systemBackground = Color(NSColor.controlBackgroundColor)
    static let systemText = Color(NSColor.textColor)
    static let systemSelectedText = Color(NSColor.selectedControlTextColor)
    static let systemSelectedBackground = Color(NSColor.selectedControlColor)
}

// MARK: - Retro Typography

struct RetroTypography {
    static let titleFont = Font.system(size: 15, weight: .bold, design: .monospaced)
    static let bodyFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let smallFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let buttonFont = Font.system(size: 13, weight: .semibold, design: .monospaced)
}

// MARK: - Retro Views

struct RetroWindowBackground<Content: View>: View {
    let title: String
    let subtitle: String?
    let onClose: (() -> Void)?
    let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView(title: title, subtitle: subtitle, onClose: onClose)
                .frame(height: 28)
            content()
                .background(RetroColors.windowBackground)
                .border(RetroColors.outsetBorder, width: 1)
        }
        .border(RetroColors.insetBorder, width: 1)
    }
}

struct TitleBarView: View {
    let title: String
    let subtitle: String?
    var onClose: (() -> Void)? = nil

    var body: some View {
        LinearGradient(
            colors: [RetroColors.titleBarGradientStart, RetroColors.titleBarGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            HStack {
                if onClose != nil {
                    CloseButton()
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(title)
                        .font(RetroTypography.titleFont)
                        .foregroundColor(RetroColors.darkText)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(RetroTypography.smallFont)
                            .foregroundColor(RetroColors.secondaryText)
                    }
                }
                .padding(.trailing, 8)
                Spacer()
            }
            .padding(.leading, 4)
        )
    }
}

struct CloseButton: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .circular)
                .fill(Color(red: isDark ? 0.9 : 128/255, green: isDark ? 0.9 : 128/255, blue: isDark ? 0.9 : 128/255))
                .border(Color(red: 64/255, green: 64/255, blue: 64/255), width: 1)
            RoundedRectangle(cornerRadius: 1, style: .circular)
                .fill(Color.white)
                .border(Color(red: isDark ? 0.9 : 192/255, green: isDark ? 0.9 : 192/255, blue: isDark ? 0.9 : 192/255), width: 1)
            Text("✕")
                .font(Font.system(size: 9, weight: .bold, design: .default))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Retro Controls

struct RetroButton: View {
    let label: String
    let action: () -> Void
    var isDefault: Bool = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(RetroTypography.buttonFont)
                .foregroundColor(RetroColors.darkText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RetroButtonBorder(isDefault: isDefault))
        }
        .buttonStyle(.plain)
    }
}

struct RetroButtonBorder: View {
    let isDefault: Bool

    var body: some View {
        let light = Color.white
        let dark = Color(red: 128/255, green: 128/255, blue: 128/255)
        let shadow = Color(red: 96/255, green: 96/255, blue: 96/255)

        return ZStack(alignment: .topLeading) {
            Rectangle().fill(shadow).offset(x: 2, y: 2)
            Rectangle().fill(RetroColors.buttonFace).border(dark, width: 1)
            Rectangle().fill(light).frame(width: 2).offset(x: -1)
            Rectangle().fill(light).frame(height: 1).offset(y: -1)
            if isDefault {
                Rectangle().fill(light).scaleEffect(0.95)
                    .overlay(Rectangle().stroke(light, lineWidth: 1).scaleEffect(0.95))
            }
        }
    }
}

struct RetroInsetPanel: View {
    var content: AnyView
    let padding: CGFloat

    init(padding: CGFloat = 8, @ViewBuilder content: @escaping () -> some View) {
        self.content = AnyView(content())
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(RetroColors.panelBackground)
                    Rectangle().fill(Color(red: 128/255, green: 128/255, blue: 128/255)).frame(width: 1).offset(x: -1)
                    Rectangle().fill(Color(red: 128/255, green: 128/255, blue: 128/255)).frame(height: 1).offset(y: -1)
                    Rectangle().fill(Color.white).frame(width: 1).offset(x: 1)
                    Rectangle().fill(Color.white).frame(height: 1).offset(y: 1)
                }
            )
    }
}

struct RetroDisclosureTriangle: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(RetroTypography.smallFont)
            .foregroundColor(RetroColors.darkText)
            .scaleEffect(x: 1.2, y: 1.0)
    }
}

struct RetroCheckbox: View {
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isChecked {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(RetroColors.darkText).frame(width: 18, height: 18)
                    Text("✓").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                } else {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Color.white).frame(width: 18, height: 18)
                        .border(RetroColors.darkText, width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
    }
}

struct RetroProgressView: View {
    let progress: Float
    let label: String

    /// The track's full width. The filled part is a fraction of this, so the two
    /// numbers have to be the same number.
    private let trackWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .circular)
                    .fill(Color(red: 200/255, green: 200/255, blue: 200/255))
                    .frame(width: trackWidth, height: 16)
                    .border(Color(red: 128/255, green: 128/255, blue: 128/255), width: 1)
                if progress > 0 {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Color(red: 130/255, green: 170/255, blue: 255/255))
                        .frame(
                            width: trackWidth * CGFloat(min(max(progress, 0), 1)),
                            height: 14
                        )
                        .padding(.leading, 1)
                }
            }
            .frame(width: trackWidth)
        }
    }
}

/// Scrub99 has two appearances, not two applications. These tokens are the
/// whole difference between them: every screen is built once and reads its
/// colours, fonts, and chrome from here. Keeping the difference this narrow is
/// what stops one appearance from quietly falling behind the other.
struct UIStyle {
    let theme: AppState.Theme

    var isRetro: Bool { theme == .classic9 }

    let text: Color
    let secondaryText: Color
    let accent: Color
    let border: Color
    let rowSelection: Color
    let rowBackground: Color
    let windowBackground: Color
    let groupingBackground: Color
    let positive: Color
    let caution: Color
    let negative: Color

    let titleFont: Font
    let bodyFont: Font
    let smallFont: Font
    let labelFont: Font
    let pathFont: Font

    static func resolve(_ theme: AppState.Theme) -> UIStyle {
        switch theme {
        case .classic9:
            return UIStyle(
                theme: theme,
                text: RetroColors.darkText,
                secondaryText: RetroColors.secondaryText,
                accent: RetroColors.selectedItem,
                border: RetroColors.insetBorder,
                rowSelection: RetroColors.selectionOverlay,
                rowBackground: RetroColors.panelBackground,
                windowBackground: RetroColors.windowBackground,
                groupingBackground: RetroColors.panelBackground,
                positive: Color(red: 22/255, green: 108/255, blue: 54/255),
                caution: RetroColors.warningText,
                negative: RetroColors.criticalText,
                titleFont: Font.system(size: 22, weight: .bold, design: .monospaced),
                bodyFont: RetroTypography.bodyFont,
                smallFont: RetroTypography.smallFont,
                labelFont: RetroTypography.smallFont.bold(),
                pathFont: Font.system(size: 11, weight: .regular, design: .monospaced)
            )
        case .liquidGlass:
            return UIStyle(
                theme: theme,
                text: Color(nsColor: .labelColor),
                secondaryText: Color(nsColor: .secondaryLabelColor),
                accent: Color.accentColor,
                border: Color(nsColor: .separatorColor),
                rowSelection: Color.accentColor.opacity(0.14),
                rowBackground: Color.clear,
                windowBackground: Color(nsColor: .windowBackgroundColor),
                groupingBackground: Color(nsColor: .underPageBackgroundColor),
                positive: Color.green,
                caution: Color.orange,
                negative: Color.red,
                titleFont: .system(size: 26, weight: .semibold),
                bodyFont: .system(size: 13),
                smallFont: .system(size: 11),
                labelFont: .system(size: 11, weight: .semibold),
                pathFont: .system(size: 11, design: .monospaced)
            )
        }
    }
}

private struct UIStyleKey: EnvironmentKey {
    static let defaultValue = UIStyle.resolve(.classic9)
}

extension EnvironmentValues {
    var uiStyle: UIStyle {
        get { self[UIStyleKey.self] }
        set { self[UIStyleKey.self] = newValue }
    }
}

// MARK: - Theme-aware chrome

/// Draws the surface a screen sits on. Retro gets a drawn panel; Liquid Glass
/// gets a real glass surface on macOS 26 and a material fallback below it.
private struct ThemePanelChrome: ViewModifier {
    let isRetro: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRetro {
            content
                .background(RetroColors.panelBackground)
                .overlay(Rectangle().stroke(RetroColors.insetBorder, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct ThemePanel<Content: View>: View {
    @Environment(\.uiStyle) private var style
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .modifier(ThemePanelChrome(isRetro: style.isRetro))
    }
}

struct ThemeButton: View {
    @Environment(\.uiStyle) private var style
    let title: String
    var systemImage: String? = nil
    var isPrimary: Bool = false
    var isEnabled: Bool = true
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        content
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
            .helpIfPresent(help)
            // SwiftUI does not derive an accessibility name from a drawn label, so
            // without this every button in Scrub 99 reaches VoiceOver — and any
            // script driving the app — as an unnamed "button".
            .accessibilityLabel(title)
            .accessibilityHint(help ?? "")
    }

    @ViewBuilder
    private var content: some View {
        if style.isRetro {
            RetroButton(label: title, action: action, isDefault: isPrimary)
        } else if isPrimary {
            Button(action: action) { label }.buttonStyle(.borderedProminent)
        } else {
            Button(action: action) { label }.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

struct ThemeCheckbox: View {
    @Environment(\.uiStyle) private var style
    let isChecked: Bool
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if style.isRetro {
                RetroCheckbox(isChecked: isChecked, action: action)
            } else {
                Button(action: action) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isChecked ? style.accent : style.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .helpIfPresent(help ?? (isChecked ? "Remove from the cleanup review" : "Add to the cleanup review"))
        .accessibilityLabel(isChecked ? "Untick" : "Tick for the cleanup review")
    }
}

private struct HelpIfPresent: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    func helpIfPresent(_ text: String?) -> some View {
        modifier(HelpIfPresent(text: text))
    }
}

// MARK: - Button style

struct RetroButtonStyle: ButtonStyle {
    let isDefault: Bool
    init(isDefault: Bool = false) { self.isDefault = isDefault }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroTypography.buttonFont)
            .foregroundColor(RetroColors.darkText)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(ZStack(alignment: .topLeading) {
                Rectangle().fill(RetroColors.buttonFace).border(isDefault ? RetroColors.darkText : Color(red: 96/255, green: 96/255, blue: 96/255), width: isDefault ? 2 : 1)
                Rectangle().fill(Color.white).frame(width: 1)
                Rectangle().fill(Color.white).frame(height: 1).offset(y: -1)
            })
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
