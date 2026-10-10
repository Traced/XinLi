import Foundation
import LunarCore
import SwiftData

enum AgendaRepeat: String, Codable, CaseIterable, Identifiable, Sendable {
    case never, daily, weekly, monthly, yearly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: "不重复"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }
}

struct AgendaRecurrence: Codable, Equatable, Sendable {
    var frequency: AgendaRepeat = .never
    var interval: Int = 1
    /// Foundation weekday values: 1 = Sunday, 2 = Monday.
    var weekdays: [Int] = []
    var until: Date?
    var summary: String {
        guard frequency != .never else { return "不重复" }
        let unit: String
        switch frequency { case .daily: unit = "天"; case .weekly: unit = "周"; case .monthly: unit = "月"; case .yearly: unit = "年"; case .never: unit = "" }
        return interval == 1 ? frequency.title : "每 \(interval) \(unit)"
    }
}

enum AgendaSource: String, Codable, Sendable { case local, system }
enum AgendaEditScope: String, CaseIterable, Identifiable, Sendable {
    case occurrence, series
    var id: String { rawValue }
}

struct AgendaEvent: Identifiable, Equatable, Sendable {
    var id: String
    var recordID: String
    var source: AgendaSource
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var meetingURL: String
    var colorHex: String
    var calendarID: String
    var calendarName: String
    var timeZoneIdentifier: String
    var reminderMinutes: Int
    var recurrence: AgendaRecurrence
    var isEditable: Bool
    var occurrenceDate: Date
    var isRecurring: Bool { recurrence.frequency != .never }
    var safeMeetingURL: URL? { AgendaDates.safeMeetingURL(meetingURL) }
}

struct AgendaTask: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var due: Date?
    /// 0 = normal, 1 = medium, 2 = high.
    var priority: Int
    var isComplete: Bool
    var reminderMinutes: Int
}

struct AgendaCalendar: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var source: String
    var colorHex: String
    var allowsChanges: Bool
}

struct AgendaDraft: Sendable {
    var title = ""
    var start = Date()
    var end = Date().addingTimeInterval(3600)
    var isAllDay = false
    var location = ""
    var notes = ""
    var meetingURL = ""
    var colorHex = "#3B82F6"
    var calendarID = "local"
    var timeZoneIdentifier = TimeZone.current.identifier
    var reminderMinutes = -1
    var recurrence = AgendaRecurrence()

    init() {}
    init(event: AgendaEvent) {
        title = event.title; start = event.start; end = event.end; isAllDay = event.isAllDay
        location = event.location; notes = event.notes; meetingURL = event.meetingURL
        colorHex = event.colorHex; calendarID = event.calendarID
        timeZoneIdentifier = event.timeZoneIdentifier; reminderMinutes = event.reminderMinutes
        recurrence = event.recurrence
    }

    static func new(on date: SolarDate, timeZone: TimeZone, reminderMinutes: Int, colorHex: String) -> AgendaDraft {
        var result = AgendaDraft()
        result.start = AgendaDates.date(date, timeZone: timeZone, hour: 9)
        result.end = result.start.addingTimeInterval(3600)
        result.timeZoneIdentifier = timeZone.identifier
        result.reminderMinutes = reminderMinutes
        result.colorHex = colorHex
        return result
    }

    /// A display-zone change never shifts timed events or the origin of an existing series.
    /// All-day dates float: rebase only the editor representation, then save() converts it back.
    mutating func updateDisplayTimeZone(from previous: TimeZone, to current: TimeZone, isNew: Bool) {
        if isAllDay {
            start = AgendaDates.rebase(start, from: previous, to: current)
            end = AgendaDates.rebase(end, from: previous, to: current)
        }
        if isNew { timeZoneIdentifier = current.identifier }
    }

    func validated() throws -> AgendaDraft {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.title.isEmpty else { throw AgendaError.validation("请输入日程名称。") }
        guard end > start else { throw AgendaError.validation("结束时间必须晚于开始时间。") }
        guard recurrence.interval >= 1 && recurrence.interval <= 999 else { throw AgendaError.validation("重复间隔须为 1–999。") }
        guard meetingURL.isEmpty || AgendaDates.safeMeetingURL(meetingURL) != nil else {
            throw AgendaError.validation("会议链接请使用完整的 https:// 或 http:// 地址。")
        }
        if let until = recurrence.until, until < start { throw AgendaError.validation("重复结束日期不能早于开始日期。") }
        return result
    }
}

enum AgendaError: LocalizedError {
    case validation(String), storage(String), permission(String), unavailable(String)
    var errorDescription: String? {
        switch self { case .validation(let message), .storage(let message), .permission(let message), .unavailable(let message): message }
    }
}

@Model
final class LocalAgendaEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var meetingURL: String
    var colorHex: String
    var timeZoneIdentifier: String
    var reminderMinutes: Int
    var recurrenceJSON: String
    var excludedOccurrencesJSON: String
    var parentSeriesID: UUID?

    init(id: UUID = UUID(), draft: AgendaDraft, parentSeriesID: UUID? = nil) {
        self.id = id; title = draft.title; start = draft.start; end = draft.end
        isAllDay = draft.isAllDay; location = draft.location; notes = draft.notes
        meetingURL = draft.meetingURL; colorHex = draft.colorHex
        timeZoneIdentifier = draft.timeZoneIdentifier; reminderMinutes = draft.reminderMinutes
        recurrenceJSON = String(data: (try? JSONEncoder().encode(draft.recurrence)) ?? Data(), encoding: .utf8) ?? "{}"
        excludedOccurrencesJSON = "[]"; self.parentSeriesID = parentSeriesID
    }
    var recurrence: AgendaRecurrence {
        get { (try? JSONDecoder().decode(AgendaRecurrence.self, from: Data(recurrenceJSON.utf8))) ?? AgendaRecurrence() }
        set { recurrenceJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data(), encoding: .utf8) ?? "{}" }
    }
    var excludedOccurrences: Set<Double> {
        get { Set((try? JSONDecoder().decode([Double].self, from: Data(excludedOccurrencesJSON.utf8))) ?? []) }
        set { excludedOccurrencesJSON = String(data: (try? JSONEncoder().encode(newValue.sorted())) ?? Data(), encoding: .utf8) ?? "[]" }
    }
    func apply(_ draft: AgendaDraft) {
        title = draft.title; start = draft.start; end = draft.end; isAllDay = draft.isAllDay
        location = draft.location; notes = draft.notes; meetingURL = draft.meetingURL
        colorHex = draft.colorHex; timeZoneIdentifier = draft.timeZoneIdentifier
        reminderMinutes = draft.reminderMinutes; recurrence = draft.recurrence
    }
}

@Model
final class LocalAgendaTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var due: Date?
    var priority: Int
    var isComplete: Bool
    var reminderMinutes: Int
    init(task: AgendaTask) {
        id = task.id; title = task.title; notes = task.notes; due = task.due
        priority = task.priority; isComplete = task.isComplete; reminderMinutes = task.reminderMinutes
    }
    var snapshot: AgendaTask {
        AgendaTask(id: id, title: title, notes: notes, due: due, priority: priority,
                   isComplete: isComplete, reminderMinutes: reminderMinutes)
    }
}

enum AgendaDates {
    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone; c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        return c
    }
    static func date(_ day: SolarDate, timeZone: TimeZone, hour: Int = 0) -> Date {
        calendar(timeZone).date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour)) ?? .distantPast
    }
    static func solar(_ date: Date, timeZone: TimeZone) -> SolarDate {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return SolarDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }
    static func dayInterval(_ day: SolarDate, timeZone: TimeZone) -> DateInterval {
        DateInterval(start: date(day, timeZone: timeZone), end: date(day.adding(days: 1), timeZone: timeZone))
    }
    /// All-day dates float with the display calendar; their stored reminder instant stays in the event timezone.
    static func rebase(_ date: Date, from source: TimeZone, to destination: TimeZone) -> Date {
        let parts = calendar(source).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return calendar(destination).date(from: parts) ?? date
    }
    static func safeMeetingURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func overlaps(start: Date, end: Date, interval: DateInterval) -> Bool {
        start < interval.end && end > interval.start
    }
}

/// Calendar-day recurrence preserves wall clock time through DST. Missing monthly/yearly dates
/// are skipped (for example, January 31 does not silently become February 28).
enum AgendaRecurrenceEngine {
    /// Exclusions identify the original occurrence day in a series. When its anchor or wall
    /// clock changes, migrate the timestamp while keeping detached overrides independent.
    static func remapExclusions(_ excluded: Set<Double>, from oldAnchor: Date, oldTimeZone: TimeZone,
                                to newAnchor: Date, newTimeZone: TimeZone) -> Set<Double> {
        let oldDay = AgendaDates.solar(oldAnchor, timeZone: oldTimeZone)
        let newDay = AgendaDates.solar(newAnchor, timeZone: newTimeZone)
        let calendar = AgendaDates.calendar(newTimeZone)
        let clock = calendar.dateComponents([.hour, .minute, .second], from: newAnchor)
        return Set(excluded.compactMap { value in
            let occurrenceDay = AgendaDates.solar(Date(timeIntervalSince1970: value), timeZone: oldTimeZone)
            let targetDay = newDay.adding(days: occurrenceDay.dayNumber - oldDay.dayNumber)
            let midnight = AgendaDates.date(targetDay, timeZone: newTimeZone)
            return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                 second: clock.second ?? 0, of: midnight,
                                 matchingPolicy: .nextTimePreservingSmallerComponents,
                                 repeatedTimePolicy: .first, direction: .forward)?.timeIntervalSince1970
        })
    }

    static func starts(start: Date, duration: TimeInterval, rule: AgendaRecurrence,
                       timeZone: TimeZone, in range: DateInterval, excluded: Set<Double> = []) -> [Date] {
        let c = AgendaDates.calendar(timeZone)
        if rule.frequency == .never {
            return AgendaDates.overlaps(start: start, end: start.addingTimeInterval(duration), interval: range)
                && !excluded.contains(start.timeIntervalSince1970) ? [start] : []
        }
        let anchor = AgendaDates.solar(start, timeZone: timeZone)
        let anchorParts = c.dateComponents([.hour, .minute, .second], from: start)
        let first = AgendaDates.solar(max(start, range.start.addingTimeInterval(-max(0, duration))), timeZone: timeZone)
        let last = AgendaDates.solar(range.end, timeZone: timeZone)
        guard first <= last else { return [] }
        let interval = max(1, rule.interval)
        let anchorMonday = anchor.dayNumber - ((anchor.weekday + 6) % 7)
        var results: [Date] = []
        for number in first.dayNumber...last.dayNumber {
            let day = SolarDate(dayNumber: number)
            let distance = number - anchor.dayNumber
            guard distance >= 0 else { continue }
            let matches: Bool
            switch rule.frequency {
            case .never: matches = distance == 0
            case .daily: matches = distance % interval == 0
            case .weekly:
                let monday = number - ((day.weekday + 6) % 7)
                let weekdays = rule.weekdays.isEmpty ? [anchor.weekday + 1] : rule.weekdays
                matches = (monday - anchorMonday) / 7 % interval == 0 && weekdays.contains(day.weekday + 1)
            case .monthly:
                let months = (day.year - anchor.year) * 12 + day.month - anchor.month
                matches = months >= 0 && months % interval == 0 && day.day == anchor.day
            case .yearly: matches = (day.year - anchor.year) % interval == 0 && day.month == anchor.month && day.day == anchor.day
            }
            guard matches || distance == 0 else { continue }
            let midnight = AgendaDates.date(day, timeZone: timeZone)
            guard let occurrence = c.date(bySettingHour: anchorParts.hour ?? 0, minute: anchorParts.minute ?? 0,
                                          second: anchorParts.second ?? 0, of: midnight,
                                          matchingPolicy: .nextTimePreservingSmallerComponents,
                                          repeatedTimePolicy: .first, direction: .forward),
                  occurrence >= start,
                  rule.until == nil || occurrence <= rule.until!,
                  !excluded.contains(occurrence.timeIntervalSince1970),
                  AgendaDates.overlaps(start: occurrence, end: occurrence.addingTimeInterval(duration), interval: range) else { continue }
            results.append(occurrence)
        }
        return results
    }
}

/// A remote-month fetch includes a separate copy of today's events for the menu bar.
/// Its validity therefore depends on both the requested month and the agenda-zone date.
struct AgendaSystemCacheWindow {
    var range: DateInterval
    var today: SolarDate
    var timeZoneIdentifier: String

    func covers(_ requested: DateInterval, at now: Date, timeZone: TimeZone) -> Bool {
        timeZoneIdentifier == timeZone.identifier
            && today == AgendaDates.solar(now, timeZone: timeZone)
            && range.start <= requested.start && range.end >= requested.end
    }
}
