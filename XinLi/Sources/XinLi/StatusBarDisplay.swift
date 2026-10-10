import Foundation
import LunarCore

enum StatusBarFormat: String, CaseIterable, Identifiable, Codable {
    case icon, yearMonthDay, yearMonthDayTime, yearMonthDayTimeSeconds
    case monthDayWeekday, monthDayWeekdayTime, monthDayWeekdayTimeSeconds
    case time, timeSeconds, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return "日历图标"
        case .yearMonthDay: return "年月日"
        case .yearMonthDayTime: return "年月日 时分"
        case .yearMonthDayTimeSeconds: return "年月日 时分秒"
        case .monthDayWeekday: return "月日 周几"
        case .monthDayWeekdayTime: return "月日 周几 时分"
        case .monthDayWeekdayTimeSeconds: return "月日 周几 时分秒"
        case .time: return "时分"
        case .timeSeconds: return "时分秒"
        case .custom: return "自定义组合"
        }
    }
}

enum StatusBarDateStyle: String, CaseIterable, Identifiable, Codable {
    case none, yearMonthDay, monthDay, chineseYearMonthDay, chineseMonthDay

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "不显示日期"
        case .yearMonthDay: return "年月日（2026-10-09）"
        case .monthDay: return "月日（10-09）"
        case .chineseYearMonthDay: return "年月日（2026年10月9日）"
        case .chineseMonthDay: return "月日（10月9日）"
        }
    }
    var pattern: String {
        switch self {
        case .none: return ""
        case .yearMonthDay: return "yyyy-MM-dd"
        case .monthDay: return "MM-dd"
        case .chineseYearMonthDay: return "yyyy年M月d日"
        case .chineseMonthDay: return "M月d日"
        }
    }
}

enum StatusBarTimeStyle: String, CaseIterable, Identifiable, Codable {
    case none, hourMinute, hourMinuteSecond

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "不显示时间"
        case .hourMinute: return "时分（14:05）"
        case .hourMinuteSecond: return "时分秒（14:05:09）"
        }
    }
    var pattern: String {
        switch self {
        case .none: return ""
        case .hourMinute: return "HH:mm"
        case .hourMinuteSecond: return "HH:mm:ss"
        }
    }
}

/// 状态栏偏好：预设与自定义组合分别保存，切换预设不会丢失自定义内容。
struct StatusBarDisplay: Codable, Equatable {
    var format: StatusBarFormat = .custom
    var customDate: StatusBarDateStyle = .chineseMonthDay
    var customWeekday = true
    var customTime: StatusBarTimeStyle = .hourMinute
    /// nil 跟随系统；指定城市时区会自动处理夏令时。
    var timeZoneIdentifier: String?

    private static let key = "statusBarDisplay"
    static let didChange = Notification.Name("XinLiStatusBarDisplayDidChange")

    static func load(from defaults: UserDefaults = .standard) -> StatusBarDisplay {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    @MainActor
    func save(to defaults: UserDefaults = .standard) {
        if defaults.data(forKey: Self.key) != nil, Self.load(from: defaults) == self { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: defaults)
    }

    var customIsEmpty: Bool { customDate == .none && !customWeekday && customTime == .none }

    var datePattern: String {
        switch format {
        case .icon: return ""
        case .yearMonthDay: return "yyyy-MM-dd"
        case .yearMonthDayTime: return "yyyy-MM-dd HH:mm"
        case .yearMonthDayTimeSeconds: return "yyyy-MM-dd HH:mm:ss"
        case .monthDayWeekday: return "MM-dd EEEE"
        case .monthDayWeekdayTime: return "MM-dd EEEE HH:mm"
        case .monthDayWeekdayTimeSeconds: return "MM-dd EEEE HH:mm:ss"
        case .time: return "HH:mm"
        case .timeSeconds: return "HH:mm:ss"
        case .custom:
            // 即使外部写入了空组合，也不能让菜单栏入口消失。
            if customIsEmpty { return "yyyy-MM-dd" }
            return [customDate.pattern, customWeekday ? "EEEE" : "", customTime.pattern]
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    var refreshInterval: TimeInterval {
        switch format {
        case .yearMonthDayTimeSeconds, .monthDayWeekdayTimeSeconds, .timeSeconds: return 1
        case .custom where customTime == .hourMinuteSecond: return 1
        default: return 60
        }
    }

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    func calendarDate(at date: Date) -> SolarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return SolarDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    func makeFormatter(timeZone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone ?? self.timeZone
        formatter.dateFormat = datePattern
        formatter.weekdaySymbols = (0..<7).map(LunarCalendar.weekdayName)
        return formatter
    }
}

@MainActor
extension StatusBarDisplay {
    func refreshInterval(preferences: AppPreferences) -> TimeInterval {
        guard format != .icon, !preferences.customDatePattern.isEmpty else { return refreshInterval }
        let tokens = preferences.customDatePattern.split(separator: "'", omittingEmptySubsequences: false)
            .enumerated().filter { $0.offset % 2 == 0 }.map { String($0.element) }.joined()
        return tokens.contains("s") || tokens.contains("S") ? 1 : 60
    }
    func renderedTitle(at date: Date, remainingEvents: Int = 0, preferences: AppPreferences = .shared) -> String {
        let formatter = makeFormatter()
        var pattern = preferences.customDatePattern.isEmpty ? datePattern : preferences.customDatePattern
        if !preferences.use24HourTime { pattern = pattern.replacingOccurrences(of: "HH", with: "hh") + (pattern.contains("HH") ? " a" : "") }
        formatter.dateFormat = pattern
        formatter.shortWeekdaySymbols = (0..<7).map(LunarCalendar.weekdayName)
        formatter.veryShortWeekdaySymbols = (0..<7).map(LunarCalendar.weekdayName)
        var components = [formatter.string(from: date)]
        let day = calendarDate(at: date)
        if preferences.showStatusLunar && LunarCalendar.supportedYears.contains(day.year) {
            let lunar = LunarCalendar.lunar(for: day)
            components.append("农历" + LunarCalendar.monthName(lunar.month, isLeap: lunar.isLeap) + "月" + LunarCalendar.dayName(lunar.day))
        }
        if preferences.showStatusSolarTerm {
            let term = SolarTermEngine.displayName(on: day, timeZone: timeZone)
            if !term.isEmpty { components.append(term) }
        }
        if preferences.showStatusAgendaCount { components.append("日程 \(remainingEvents)") }
        let title = components.filter { !$0.isEmpty }.joined(separator: " · ").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { formatter.dateFormat = "M月d日"; return formatter.string(from: date) }
        return title
    }
}
