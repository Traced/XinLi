import Foundation

public struct LunarMonthSummary: Equatable, Sendable {
    public let name: String
    public let isLeap: Bool
    public let numberOfDays: Int
    public var sizeName: String { numberOfDays == 30 ? "大月" : "小月" }

    public init(day: CalendarDay) {
        name = day.lunarMonthName
        isLeap = day.lunar.isLeap
        let first = day.date.adding(days: 1 - day.lunar.day)
        numberOfDays = LunarCalendar.lunar(for: first.adding(days: 29)).day == 1 ? 29 : 30
    }
}

/// 黄历内容必须附带可核验来源及复用许可；历法计算不能推导宜忌等民俗条目。
public struct AlmanacSource: Equatable, Sendable {
    public let title: String
    public let sourceURL: URL
    public let licenseURL: URL
    public let coveredYears: ClosedRange<Int>

    public init(title: String, sourceURL: URL, licenseURL: URL, coveredYears: ClosedRange<Int>) {
        self.title = title
        self.sourceURL = sourceURL
        self.licenseURL = licenseURL
        self.coveredYears = coveredYears
    }
}

/// 时段按北京时间划分；早子（00:00）和晚子（23:00）分别保留上游的干支。
public struct AlmanacHour: Codable, Equatable, Sendable, Identifiable {
    public let branch: String
    public let ganZhi: String
    public let timeRange: String
    public let heavenlySpirit: String
    public let luck: String
    public let suitableActivities: [String]
    public let unsuitableActivities: [String]
    public let clash: String
    public let sha: String
    public var id: String { timeRange }
    public var isAuspicious: Bool { luck == "吉" }
}

public struct AlmanacRecord: Equatable, Sendable {
    public let date: SolarDate
    public let suitableActivities: [String]
    public let unsuitableActivities: [String]
    public let clashes: [String]
    public let auspiciousHours: [String]
    public let source: AlmanacSource
    public let lunarYear: Int
    /// 闰月用负数表示，与 lunar-go 的接口一致。
    public let lunarMonth: Int
    public let lunarDay: Int
    public let yearGanZhi: String
    public let monthGanZhi: String
    public let dayGanZhi: String
    public let pengZu: [String]
    public let hours: [AlmanacHour]

    public init(date: SolarDate, suitableActivities: [String], unsuitableActivities: [String],
                clashes: [String], auspiciousHours: [String], source: AlmanacSource,
                lunarYear: Int = 0, lunarMonth: Int = 0, lunarDay: Int = 0,
                yearGanZhi: String = "", monthGanZhi: String = "", dayGanZhi: String = "",
                pengZu: [String] = [], hours: [AlmanacHour] = []) {
        self.date = date
        self.suitableActivities = suitableActivities
        self.unsuitableActivities = unsuitableActivities
        self.clashes = clashes
        self.auspiciousHours = auspiciousHours
        self.source = source
        self.lunarYear = lunarYear
        self.lunarMonth = lunarMonth
        self.lunarDay = lunarDay
        self.yearGanZhi = yearGanZhi
        self.monthGanZhi = monthGanZhi
        self.dayGanZhi = dayGanZhi
        self.pengZu = pengZu
        self.hours = hours
    }
}

public enum AlmanacAvailability: Equatable, Sendable {
    case available(AlmanacRecord)
    case unavailable(reason: String)
}

public protocol AlmanacProvider: Sendable {
    func record(for date: SolarDate) -> AlmanacAvailability
}

/// 供未配置其他来源的客户端使用；不可从干支自行编造黄历。
public struct UnavailableAlmanacProvider: AlmanacProvider {
    public init() {}
    public func record(for date: SolarDate) -> AlmanacAvailability {
        .unavailable(reason: "未配置黄历数据提供者；宜忌、冲煞和吉时暂不可用。")
    }
}

/// 表示实际载入的记录范围，不承诺未列出的日期或年份具有完整放假安排。
public struct HolidayCoverage: Equatable, Sendable {
    public let years: [Int]
    public let firstRecordedDate: String?
    public let lastRecordedDate: String?
    public let version: String?
    public let sources: [String]

    public init(data: HolidayData?) {
        let dates = (data?.days ?? []).map(\.date).sorted()
        years = Array(Set(dates.compactMap { Int($0.prefix(4)) })).sorted()
        firstRecordedDate = dates.first
        lastRecordedDate = dates.last
        version = data?.version
        sources = data?.sources ?? []
    }

    public func hasRecords(in year: Int) -> Bool { years.contains(year) }
}
