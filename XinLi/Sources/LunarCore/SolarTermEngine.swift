import Foundation

/// 一个交节点。instant 只在已独立核验的 2025–2027 年提供，不能把日期表当作时刻。
public struct SolarTermOccurrence: Hashable, Sendable, Identifiable {
    public let year: Int
    public let oneBasedIndex: Int
    /// 现有节气表中的北京时间日期，供无交节时刻的年份使用。
    public let date: SolarDate
    public let instant: Date?
    public var id: String { "\(year)-\(oneBasedIndex)" }
    public var name: String { LunarCalendar.solarTermNames[oneBasedIndex - 1] }

    public func calendarDate(in timeZone: TimeZone) -> SolarDate {
        guard let instant else { return date }
        return SolarTermEngine.calendarDate(at: instant, timeZone: timeZone)
    }
}

public struct SolarTermContext: Sendable {
    public let current: SolarTermOccurrence?
    public let next: SolarTermOccurrence?
    public let onDate: [SolarTermOccurrence]
    /// 日历天数差，不是四舍五入的 24 小时段；夏令时切换也不会偏一天。
    public let nextInDays: Int?
}

/// 已核验视黄经求根结果的离线查询，不在客户端使用未经验证的近似公式。
/// Astronomy Engine (MIT) SearchSunLongitude 的自生成计算结果；可复现脚本、
/// 固定版本、许可和独立比较统计见 Resources/Calendar 与 DATA-SOURCES.md。
public enum SolarTermEngine {
    public static let calendarTimeZone = TimeZone(identifier: "Asia/Shanghai")!
    public static let verifiedTimeYears = 2025...2027
    public static let timeSourceName = "Astronomy Engine 视黄经计算"
    public static let accuracyDescription = "2025–2027 年已核验，计算值与香港天文台分钟表相差不足 1 分钟"
    private static let verifiedOccurrences = verifiedTimeYears.flatMap { occurrences(in: $0) }

    /// 日历格与状态栏共用的日期标签。已核验的交节时刻按显示时区归日；
    /// 其他年份没有可靠时刻可供换算，明确标记为原始北京时间日期。
    public static func displayName(on date: SolarDate, timeZone: TimeZone = calendarTimeZone) -> String {
        guard (1900...2100).contains(date.year), (1...12).contains(date.month),
              (1...SolarDate.daysInMonth(year: date.year, month: date.month)).contains(date.day) else { return "" }
        if verifiedTimeYears.contains(date.year) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let next = date.adding(days: 1)
            guard let start = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)),
                  let end = calendar.date(from: DateComponents(year: next.year, month: next.month, day: next.day)) else { return "" }
            return verifiedOccurrences.filter { term in
                guard let instant = term.instant else { return false }
                return instant >= start && instant < end
            }.map(\.name).joined(separator: "、")
        }
        let name = LunarCalendar.solarTerm(on: date)
        return name.isEmpty ? "" : "\(name)（北京日期）"
    }

    public static func occurrences(in year: Int, timeZone: TimeZone = calendarTimeZone) -> [SolarTermOccurrence] {
        guard (1900...2100).contains(year) else { return [] }
        return (1...24).compactMap { index in
            let day = LunarCalendar.solarTermDay(year: year, index: index)
            guard day > 0 else { return nil }
            let instant = SolarTermComputedData.unixSeconds[year].map { Date(timeIntervalSince1970: $0[index - 1]) }
            return SolarTermOccurrence(year: year, oneBasedIndex: index,
                                       date: SolarDate(year: year, month: (index + 1) / 2, day: day), instant: instant)
        }
    }

    /// reference 为该日的实际参考时刻；省略时使用所选日期中午，避免将整日误称为精确时刻。
    /// 无时刻数据的交节点按北京时间日期排序，UI 必须保留“仅日期”标识。
    public static func context(on date: SolarDate, reference: Date? = nil,
                               timeZone: TimeZone = calendarTimeZone) -> SolarTermContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let anchor = reference ?? calendar.date(from: DateComponents(year: date.year, month: date.month,
                                                                     day: date.day, hour: 12))!
        let nearby = ((date.year - 1)...(date.year + 1)).flatMap { occurrences(in: $0, timeZone: timeZone) }
        let before = nearby.filter { term in
            if let instant = term.instant { return instant <= anchor }
            return term.date <= date
        }
        let after = nearby.filter { term in
            if let instant = term.instant { return instant > anchor }
            return term.date > date
        }
        let next = after.first
        return SolarTermContext(current: before.last, next: next,
                                onDate: nearby.filter { $0.calendarDate(in: timeZone) == date },
                                nextInDays: next.map { max(0, $0.calendarDate(in: timeZone).dayNumber - date.dayNumber) })
    }

    public static func calendarDate(at date: Date, timeZone: TimeZone = calendarTimeZone) -> SolarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return SolarDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }
}
