import AppKit
import SwiftUI

/// RGB math keeps custom colors legible, including very light accent colors.
struct ThemeRGB {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: String) {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let expanded = text.count == 3 ? text.map { "\($0)\($0)" }.joined() : String(text.prefix(6))
        let value = UInt32(expanded, radix: 16) ?? 0x3478F6
        red = Double((value >> 16) & 255) / 255
        green = Double((value >> 8) & 255) / 255
        blue = Double(value & 255) / 255
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    var usesDarkText: Bool { luminance > 0.179 }
    /// Prefer the lighter white-on-accent treatment for normal accent colors.
    /// Very pale custom colors keep their hue and use a softer dark foreground.
    var selectionColors: (background: ThemeRGB, foreground: ThemeRGB) {
        let white = ThemeRGB(hex: "#FFFFFF")
        if contrast(against: white) >= 3 {
            return (readable(on: white), white)
        }
        return (self, ThemeRGB(hex: "#263445").readable(on: self))
    }

    func contrast(against other: ThemeRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    func mixed(with other: ThemeRGB, amount: Double) -> ThemeRGB {
        ThemeRGB(red: red + (other.red - red) * amount,
                 green: green + (other.green - green) * amount,
                 blue: blue + (other.blue - blue) * amount)
    }

    func readable(on background: ThemeRGB) -> ThemeRGB {
        let target = ThemeRGB(hex: background.usesDarkText ? "#000000" : "#FFFFFF")
        for step in 0...20 {
            let candidate = mixed(with: target, amount: Double(step) / 20)
            if candidate.contrast(against: background) >= 4.5 { return candidate }
        }
        return target
    }
}

struct ResolvedCalendarTheme {
    var background: Color = Color(nsColor: .windowBackgroundColor)
    var card: Color = Color(nsColor: .controlBackgroundColor)
    var accent: Color = .blue
    var accentText: Color = .blue
    var selectionBackground: Color = .blue
    var selectionForeground: Color = .white
    var primary: Color = .primary
    var secondary: Color = .secondary
    var danger: Color = Palette.red
    var positive: Color = .green
    var cardOpacity: Double = 0.72
    var cardStyle: CalendarCardStyle = .glass
    var layoutDensity: CalendarLayoutDensity = .standard
    var textScale: CGFloat = 1
    var fontName: String?
    var backgroundOpacity: Double = 0.94
    var colorScheme: ColorScheme = .light

    init() {}

    @MainActor
    init(preferences: AppPreferences, colorScheme: ColorScheme) {
        let preset = preferences.colorTheme
        let dark = colorScheme == .dark
        let backgroundRGB = ThemeRGB(hex: preset == .custom ? preferences.customBackgroundHex
                                     : dark ? preset.darkBackgroundHex : preset.lightBackgroundHex)
        let cardRGB = ThemeRGB(hex: preset == .custom ? preferences.customCardHex
                               : dark ? preset.darkCardHex : preset.lightCardHex)
        let accentRGB = ThemeRGB(hex: preferences.accentHex)
        self.colorScheme = cardRGB.usesDarkText ? .light : .dark
        background = backgroundRGB.color
        card = cardRGB.color
        accent = accentRGB.color
        accentText = accentRGB.readable(on: cardRGB).color
        selectionBackground = accentRGB.selectionColors.background.color
        selectionForeground = accentRGB.selectionColors.foreground.color
        primary = ThemeRGB(hex: cardRGB.usesDarkText ? "#191B20" : "#F5F7FA").readable(on: cardRGB).color
        secondary = ThemeRGB(hex: cardRGB.usesDarkText ? "#586271" : "#B8C2D1").readable(on: cardRGB).color
        danger = ThemeRGB(hex: "#BD4D53").readable(on: cardRGB).color
        positive = ThemeRGB(hex: "#247D60").readable(on: cardRGB).color
        cardOpacity = min(max(preferences.cardOpacity, 0), 1)
        cardStyle = preferences.cardStyle
        layoutDensity = preferences.layoutDensity
        textScale = CGFloat(CalendarTypography.normalizedScale(preferences.textScale))
        fontName = CalendarTypography.resolvedFontName(for: preferences.effectiveFontFamily)
        backgroundOpacity = min(max(preferences.interfaceOpacity, 0), 1)
    }

    func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scaledSize = size * textScale
        if let fontName {
            return .custom(fontName, fixedSize: scaledSize).weight(weight)
        }
        return .system(size: scaledSize, weight: weight, design: design)
    }
}

private struct CalendarThemeKey: EnvironmentKey {
    static let defaultValue = ResolvedCalendarTheme()
}

extension EnvironmentValues {
    var chronoTheme: ResolvedCalendarTheme {
        get { self[CalendarThemeKey.self] }
        set { self[CalendarThemeKey.self] = newValue }
    }
}

/// The backdrop has no intrinsic size; decorations never affect popover height.
struct CalendarThemeBackdrop: View {
    let theme: ResolvedCalendarTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Rectangle().fill(.regularMaterial)
            .overlay(theme.background.opacity(reduceTransparency ? 1 : theme.backgroundOpacity))
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        RadialGradient(colors: [theme.accent.opacity(0.18), .clear],
                                       center: .topTrailing, startRadius: 0,
                                       endRadius: geometry.size.width * 0.95)
                        LinearGradient(colors: [.white.opacity(theme.colorScheme == .dark ? 0.025 : 0.22), .clear,
                                                theme.accent.opacity(0.045)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A decoration-only image layer: its crop follows the assigned area without
/// contributing a proposed height to the popover's content measurement.
struct CalendarPhotoBackdrop: View {
    let theme: ResolvedCalendarTheme
    let image: NSImage?
    let opacity: Double

    var body: some View {
        CalendarThemeBackdrop(theme: theme)
            .overlay {
                if let image {
                    GeometryReader { geometry in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .opacity(opacity)
                    }
                    .overlay(theme.background.opacity(0.18))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct GlassCardModifier: ViewModifier {
    @Environment(\.chronoTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = theme.colorScheme == .dark
        content
            .background {
                if theme.cardStyle == .glass {
                    ZStack {
                        if !reduceTransparency { shape.fill(.ultraThinMaterial) }
                        shape.fill(theme.card.opacity(reduceTransparency ? 1 : theme.cardOpacity))
                        shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.055 : 0.32), .clear],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .shadow(color: .black.opacity(dark ? 0.18 : 0.06), radius: 8, x: 0, y: 4)
                    .shadow(color: theme.accent.opacity(dark ? 0.04 : 0.025), radius: 2, x: 0, y: 1)
                } else {
                    shape.fill(theme.card.opacity(reduceTransparency ? 1 : theme.cardOpacity))
                }
            }
            .overlay {
                Group {
                    if theme.cardStyle == .glass {
                        shape.strokeBorder(LinearGradient(
                            colors: [.white.opacity(dark ? 0.20 : 0.85), theme.primary.opacity(contrast == .increased ? 0.30 : 0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: contrast == .increased ? 1.5 : 0.75)
                    } else {
                        shape.strokeBorder(theme.primary.opacity(contrast == .increased ? 0.25 : 0.06),
                                           lineWidth: contrast == .increased ? 1.5 : 0.5)
                    }
                }.allowsHitTesting(false)
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
