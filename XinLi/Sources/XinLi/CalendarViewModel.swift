import Combine
import Foundation
import LunarCore

/// 日历弹出窗口的状态：当前显示的年月、选中的日期
@MainActor
final class CalendarViewModel: ObservableObject {
    static let years = LunarCalendar.supportedYears

    @Published private(set) var year: Int
    @Published private(set) var month: Int
    @Published private(set) var grid: MonthGrid
    /// 用户点击选中的日期；为 nil 时高亮今天
    @Published private(set) var selected: SolarDate?
    @Published private(set) var today: SolarDate
    @Published var isChoosingMonth = false

    private let store: DataStore
    private let preferences: AppPreferences
    private let now: () -> Date
    private var cancellable: AnyCancellable?
    private var preferencesObserver: AnyCancellable?
    var selectedDate: SolarDate { selected ?? today }

    init(store: DataStore, preferences: AppPreferences = .shared, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.preferences = preferences
        self.now = now
        let today = Self.calendarToday(preferences: preferences, now: now())
        self.today = today
        year = today.year
        month = today.month
        grid = MonthGrid(year: today.year, month: today.month, data: store.data, firstWeekday: preferences.firstWeekday)
        cancellable = store.$data.dropFirst().sink { [weak self] data in
            guard let self else { return }
            self.grid = MonthGrid(year: self.year, month: self.month, data: data, firstWeekday: self.preferences.firstWeekday)
        }
        preferencesObserver = NotificationCenter.default.publisher(for: AppPreferences.didChange).sink { [weak self] _ in
            guard let self else { return }
            self.refreshToday()
            self.show(year: self.year, month: self.month)
        }
    }

    private static func calendarToday(preferences: AppPreferences, now: Date) -> SolarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = preferences.calendarTimeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return SolarDate(year: c.year!, month: c.month!, day: c.day!)
    }
    @discardableResult func moveSelection(by days: Int) -> Bool {
        let date = selectedDate.adding(days: days)
        guard Self.years.contains(date.year) else { return false }
        select(CalendarDay(date: date, data: store.data))
        return true
    }

    // MARK: - 导航

    /// 回到今天，并清除选中的日期
    func showToday() {
        today = Self.calendarToday(preferences: preferences, now: now())
        selected = nil
        show(year: today.year, month: today.month)
    }

    /// 跨天时更新"今天"，保留当前显示的月份和选中的日期
    func refreshToday() {
        let current = Self.calendarToday(preferences: preferences, now: now())
        if today != current {
            let wasShowingToday = selected == nil && year == today.year && month == today.month
            today = current
            if wasShowingToday { show(year: current.year, month: current.month) }
        }
    }

    func setYear(_ y: Int) { navigate(year: y, month: month) }
    func setMonth(_ m: Int) { navigate(year: year, month: m) }

    /// 年月一次应用，避免分别改年和月时经过中间月份而意外丢失 29/30/31 日。
    @discardableResult
    func setMonth(year: Int, month: Int) -> Bool {
        guard Self.years.contains(year), (1...12).contains(month) else { return false }
        navigate(year: year, month: month)
        return true
    }

    /// 前后移动若干年；超出范围时返回 false
    @discardableResult
    func moveYear(by delta: Int) -> Bool {
        guard Self.years.contains(year + delta) else { return false }
        navigate(year: year + delta, month: month)
        return true
    }

    /// 前后移动若干月；超出范围时返回 false
    @discardableResult
    func moveMonth(by delta: Int) -> Bool {
        let index = year * 12 + (month - 1) + delta
        guard Self.years.contains(index / 12) else { return false }
        navigate(year: index / 12, month: index % 12 + 1)
        return true
    }

    var canMoveBackward: Bool { year * 12 + month > Self.years.lowerBound * 12 + 1 }
    var canMoveForward: Bool { year * 12 + month < Self.years.upperBound * 12 + 12 }

    private func navigate(year: Int, month: Int) {
        guard Self.years.contains(year), (1...12).contains(month) else { return }
        let date = SolarDate(year: year, month: month, day: min(selectedDate.day, SolarDate.daysInMonth(year: year, month: month)))
        selected = date == today ? nil : date
        show(year: year, month: month)
    }

    private func show(year: Int, month: Int) {
        guard Self.years.contains(year), (1...12).contains(month) else { return }
        self.year = year
        self.month = month
        grid = MonthGrid(year: year, month: month, data: store.data, firstWeekday: preferences.firstWeekday)
    }

    /// 点击日期：点击今天会清除选中，回到默认状态；点击上月或下月的日期时切换到该月
    func select(_ day: CalendarDay) {
        guard Self.years.contains(day.date.year) else { return }
        selected = day.date == today ? nil : day.date
        if !grid.isInMonth(day) && Self.years.contains(day.date.year) {
            show(year: day.date.year, month: day.date.month)
        }
    }

    // MARK: - 显示

    /// 高亮显示的日期：选中的日期，没有选中时为今天
    func isHighlighted(_ day: CalendarDay) -> Bool {
        day.date == (selected ?? today)
    }

    /// 详细信息面板显示的日期：选中的日期，没有选中时为今天
    var detailDay: CalendarDay {
        let date = selected ?? today
        return grid.days.first { $0.date == date } ?? CalendarDay(date: date, data: store.data)
    }

    /// 标题栏的两部分文字
    var title: (solar: String, lunar: String) {
        let visible = grid.days.filter { grid.isInMonth($0) }
        if let day = visible.first(where: isHighlighted) {
            return (day.solarText, day.lunarText)
        }
        // 当前月份中没有选中的日期或今天，显示月份信息（取 15 日，此时本月的"节"已过）
        let middle = visible[14]
        return ("\(year)年\(month)月", "\(middle.ganZhiYear)年[\(middle.shengXiao)] \(middle.ganZhiMonth)月")
    }
}
