import AppKit

enum CalendarTypography {
    static let scaleRange = 0.30...1.20
    static let scaleStep = 0.05

    static func normalizedScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        let clamped = min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
        return (clamped * 20).rounded() / 20
    }

    static func normalizedFamily(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "system" ? "system" : trimmed
    }

    @MainActor
    static func resolvedFontName(for family: String) -> String? {
        let family = normalizedFamily(family)
        guard family != "system" else { return nil }
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13)?.fontName
    }

    @MainActor
    static var installedFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
