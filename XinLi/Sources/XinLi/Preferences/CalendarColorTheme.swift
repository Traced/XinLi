import Foundation

/// Muted surface palettes with separate light/dark colors. Custom colors are
/// stored in AppPreferences; this case's palette supplies their safe defaults.
enum CalendarColorTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case frost, ocean, jade, lavender, rose, graphite, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .frost: "霜白"
        case .ocean: "海湾"
        case .jade: "青玉"
        case .lavender: "薰衣草"
        case .rose: "蔷薇"
        case .graphite: "石墨"
        case .custom: "自定义"
        }
    }
    var lightBackgroundHex: String { palette.lightBackground }
    var darkBackgroundHex: String { palette.darkBackground }
    var lightCardHex: String { palette.lightCard }
    var darkCardHex: String { palette.darkCard }
    var accentHex: String { palette.accent }

    private var palette: (lightBackground: String, darkBackground: String, lightCard: String, darkCard: String, accent: String) {
        switch self {
        case .frost, .custom: ("#EAF0F8", "#111923", "#FFFFFF", "#243143", "#3478F6")
        case .ocean: ("#E3EEF5", "#101E2C", "#F3FAFF", "#1D3448", "#337BAE")
        case .jade: ("#E6F0EA", "#14221E", "#F5FBF6", "#263B31", "#237C61")
        case .lavender: ("#EEEAF5", "#1D1929", "#FAF7FF", "#332B44", "#795AA6")
        case .rose: ("#F6E9EC", "#281B21", "#FFF8FA", "#422B35", "#B45373")
        case .graphite: ("#E8EBEF", "#171A20", "#F5F6F8", "#2D323B", "#59697F")
        }
    }

    /// Accept RGB shorthand or six digits, with an optional leading #. Persist
    /// one canonical form; alpha belongs to the separate opacity preference.
    static func normalizedHex(_ value: String, fallback: String) -> String {
        var digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard (digits.count == 3 || digits.count == 6),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return fallback
        }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        return "#" + digits.uppercased()
    }

    static func normalizedOpacity(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : fallback
    }
}
