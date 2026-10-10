import Foundation

enum CalendarCardStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case glass, simple

    var id: String { rawValue }
    var title: String { self == .glass ? "毛玻璃" : "简洁" }
}

enum CalendarLayoutDensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact, standard, relaxed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: "紧凑"
        case .standard: "标准"
        case .relaxed: "宽松"
        }
    }

    /// Scale whitespace only; text sizes remain readable at every density.
    func spacing(_ standard: CGFloat) -> CGFloat {
        switch self {
        case .compact: standard * 0.75
        case .standard: standard
        case .relaxed: standard * 1.3
        }
    }

    var cellHeightOffset: CGFloat {
        switch self {
        case .compact: -4
        case .standard: 0
        case .relaxed: 8
        }
    }
}
