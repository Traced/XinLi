import AppKit
import Combine
import EventKit
import Foundation
import LunarCore
import SwiftData

@MainActor
final class AgendaStore: ObservableObject {
    static let shared = AgendaStore()
    @Published private(set) var tasks: [AgendaTask] = []
    @Published private(set) var calendars: [AgendaCalendar] = []
    @Published private(set) var revision = 0
    @Published private(set) var calendarAccess = "尚未连接系统日历，本地日程可直接使用。"
    @Published private(set) var hasCalendarAccess = false
    @Published private(set) var notificationStatus = "未启用通知"
    @Published private(set) var notificationAuthorized = false
    @Published var errorMessage: String?
    @Published private(set) var excludedCalendarIDs: Set<String> = []
    private(set) var container: ModelContainer?
    private var context: ModelContext?
    private var localRecords: [LocalAgendaEvent] = []
    private var systemEvents: [AgendaEvent] = []
    private var systemRecords: [String: EKEvent] = [:]
    private let eventStore = EKEventStore()
    let preferences: AppPreferences
    private let allowExternalServices: Bool
    private var preferencesObserver: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var systemCache: AgendaSystemCacheWindow?
    private var additionalRange: DateInterval?
    private var lastCenter: SolarDate
    private var windows: [NSWindow] = []
    private var notificationService: AgendaNotificationService?
    private let notificationRefreshScheduler = AgendaNotificationRefreshScheduler()
    private var isRefreshing = false
    private var pendingRefresh: SolarDate?

    init(inMemory: Bool = false, storeURL: URL? = nil, allowExternalServices: Bool = true, preferences: AppPreferences = .shared) {
        self.preferences = preferences
        self.lastCenter = AgendaDates.solar(Date(), timeZone: preferences.timeZone)
        self.allowExternalServices = allowExternalServices && !inMemory
        excludedCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: "chrono.excludedCalendarIDs") ?? [])
        do {
            let schema = Schema([LocalAgendaEvent.self, LocalAgendaTask.self])
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration("ChronoAgenda", schema: schema, isStoredInMemoryOnly: true)
            } else {
                let url: URL
                if let storeURL { url = storeURL }
                else {
                    let base: URL
                    if let directory = ProcessInfo.processInfo.environment["XINLI_DATA_DIR"]
                        ?? ProcessInfo.processInfo.environment["WANNIANLI_DATA_DIR"] {
                        base = URL(fileURLWithPath: directory, isDirectory: true)
                    } else {
                        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("WanNianLi", isDirectory: true)
                    }
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    url = base.appendingPathComponent("Agenda.store")
                }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                configuration = ModelConfiguration("ChronoAgenda", schema: schema, url: url, cloudKitDatabase: .none)
            }
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            self.context = ModelContext(container)
            self.context?.autosaveEnabled = false
            reloadLocal()
        } catch {
            errorMessage = "日程数据库无法打开：\(error.localizedDescription)。未覆盖现有数据。"
        }
        if self.allowExternalServices {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.systemCache = nil
                    await self.refresh(around: self.lastCenter)
                }
            })
            observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.systemCache = nil
                    await self.refresh(around: self.lastCenter)
                }
            })
            // CLI unit tests do not have a notification bundle. Do not initialize UNUserNotificationCenter there.
            if Bundle.main.bundleURL.pathExtension == "app" {
                notificationService = AgendaNotificationService()
            }
        }
        preferencesObserver = NotificationCenter.default.publisher(for: AppPreferences.didChange).sink { [weak self] notification in
            guard let self, notification.object as? AppPreferences === self.preferences else { return }
            self.systemCache = nil
            self.revision += 1
            if self.allowExternalServices {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.refresh(around: self.lastCenter)
                }
            }
        }
    }

    var timeZone: TimeZone { preferences.timeZone }
    func newDraft(on date: SolarDate) -> AgendaDraft {
        AgendaDraft.new(on: date, timeZone: timeZone, reminderMinutes: preferences.defaultReminderMinutes, colorHex: preferences.eventColorHex)
    }
    var writableCalendars: [AgendaCalendar] { calendars.filter(\.allowsChanges) }
    var localStorageAvailable: Bool { context != nil }

    func refresh(around date: SolarDate) async {
        guard !isRefreshing else { pendingRefresh = date; return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if let pending = pendingRefresh {
                pendingRefresh = nil
                Task { @MainActor [weak self] in await self?.refresh(around: pending) }
            }
        }
        lastCenter = date
        reloadLocal()
        if allowExternalServices {
            updateCalendarAccess()
            let interval = DateInterval(start: AgendaDates.date(date.adding(days: -45), timeZone: timeZone),
                                        end: AgendaDates.date(date.adding(days: 400), timeZone: timeZone))
            let neededStart = AgendaDates.date(date.adding(days: -35), timeZone: timeZone)
            let neededEnd = AgendaDates.date(date.adding(days: 367), timeZone: timeZone)
            let required = DateInterval(start: neededStart, end: neededEnd)
            if hasCalendarAccess && systemCache?.covers(required, at: Date(), timeZone: timeZone) != true {
                loadSystemEvents(in: interval)
            } else if !hasCalendarAccess {
                calendars = []; systemEvents = []; systemRecords = [:]; systemCache = nil
            }
            await refreshNotifications()
        }
        revision += 1
    }

    func setAdditionalRange(_ range: DateInterval?) async {
        guard additionalRange != range else { return }
        additionalRange = range
        systemCache = nil
        await refresh(around: lastCenter)
    }

    func events(on date: SolarDate) -> [AgendaEvent] {
        events(in: AgendaDates.dayInterval(date, timeZone: timeZone))
    }

    func events(in range: DateInterval) -> [AgendaEvent] {
        let local = localRecords.flatMap { occurrences(of: $0, in: range) }
        let system = systemEvents.filter {
            !excludedCalendarIDs.contains($0.calendarID) && AgendaDates.overlaps(start: $0.start, end: $0.end, interval: range)
        }
        return (local + system).sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.start == $1.start ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.start < $1.start
        }
    }

    func eventColors(on date: SolarDate) -> [String] {
        Array(Set(events(on: date).map(\.colorHex))).sorted().prefix(3).map { $0 }
    }

    func remainingCount(at now: Date) -> Int {
        events(on: AgendaDates.solar(now, timeZone: timeZone)).filter { $0.end > now }.count
    }

    func setCalendar(_ id: String, visible: Bool) {
        if visible { excludedCalendarIDs.remove(id) } else { excludedCalendarIDs.insert(id) }
        UserDefaults.standard.set(excludedCalendarIDs.sorted(), forKey: "chrono.excludedCalendarIDs")
        revision += 1
    }

    /// Only call from an explicit user action.
    func requestCalendarAccess() async {
        guard allowExternalServices else { return }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            if !granted { calendarAccess = "系统日历访问未获授权。您仍可创建和保存本地日程。" }
            systemCache = nil
            await refresh(around: lastCenter)
        } catch { errorMessage = "无法连接系统日历：\(error.localizedDescription)"; updateCalendarAccess() }
    }

    /// Only call from an explicit user action.
    func requestNotificationAccess() async {
        guard let service = notificationService else {
            notificationStatus = "通知需在已打包的 macOS 应用中使用。"; return
        }
        do {
            let granted = try await service.requestAuthorization()
            if granted { preferences.notificationsEnabled = true }
            await refreshNotifications()
        } catch { notificationStatus = "通知授权失败：\(error.localizedDescription)" }
    }

    func save(_ draft: AgendaDraft, editing event: AgendaEvent? = nil, scope: AgendaEditScope = .occurrence) async throws {
        var draft = try draft.validated()
        if draft.isAllDay {
            let eventZone = TimeZone(identifier: draft.timeZoneIdentifier) ?? timeZone
            draft.start = AgendaDates.rebase(draft.start, from: timeZone, to: eventZone)
            draft.end = AgendaDates.rebase(draft.end, from: timeZone, to: eventZone)
        }
        if event?.source == .system || (event == nil && draft.calendarID != "local") {
            try saveSystem(draft, event: event, scope: scope)
            systemCache = nil
        } else {
            guard let context else { throw AgendaError.storage("本地数据库不可用，日程没有保存。") }
            if let event {
                guard let record = localRecords.first(where: { $0.id.uuidString == event.recordID }) else {
                    throw AgendaError.unavailable("此日程已被删除，请刷新后重试。")
                }
                if record.recurrence.frequency != .never && scope == .occurrence {
                    record.excludedOccurrences.insert(event.occurrenceDate.timeIntervalSince1970)
                    var detached = draft; detached.recurrence = AgendaRecurrence()
                    context.insert(LocalAgendaEvent(draft: detached, parentSeriesID: record.id))
                } else {
                    var replacement = draft
                    if record.recurrence.frequency != .never {
                        let oldZone = TimeZone(identifier: record.timeZoneIdentifier) ?? timeZone
                        let newZone = TimeZone(identifier: draft.timeZoneIdentifier) ?? timeZone
                        let calendar = AgendaDates.calendar(newZone)
                        if event.occurrenceDate != record.start {
                            // Keep the original anchor when editing a later instance, including a timezone change.
                            let oldDay = AgendaDates.solar(record.start, timeZone: oldZone)
                            let occurrenceDay = AgendaDates.solar(event.occurrenceDate, timeZone: oldZone)
                            let editedDay = AgendaDates.solar(draft.start, timeZone: newZone)
                            let anchorDay = editedDay.adding(days: oldDay.dayNumber - occurrenceDay.dayNumber)
                            let base = AgendaDates.date(anchorDay, timeZone: newZone)
                            let clock = calendar.dateComponents([.hour, .minute, .second], from: draft.start)
                            replacement.start = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: clock.second ?? 0, of: base,
                                                               matchingPolicy: .nextTimePreservingSmallerComponents,
                                                               repeatedTimePolicy: .first, direction: .forward) ?? base
                            if draft.isAllDay {
                                let days = calendar.dateComponents([.day], from: draft.start, to: draft.end).day ?? 1
                                replacement.end = calendar.date(byAdding: .day, value: max(1, days), to: replacement.start) ?? replacement.start.addingTimeInterval(86_400)
                            } else { replacement.end = replacement.start.addingTimeInterval(draft.end.timeIntervalSince(draft.start)) }
                        }
                        record.excludedOccurrences = AgendaRecurrenceEngine.remapExclusions(record.excludedOccurrences,
                            from: record.start, oldTimeZone: oldZone, to: replacement.start, newTimeZone: newZone)
                    }
                    record.apply(replacement)
                }
            } else { context.insert(LocalAgendaEvent(draft: draft)) }
            do { try context.save() } catch { context.rollback(); throw AgendaError.storage(error.localizedDescription) }
        }
        await refresh(around: lastCenter)
    }

    func delete(_ event: AgendaEvent, scope: AgendaEditScope = .occurrence) async throws {
        if event.source == .system {
            updateCalendarAccess()
            guard hasCalendarAccess else { throw AgendaError.permission("系统日历权限已撤销，未删除日程。") }
            guard let record = systemRecords[event.id], record.calendar.allowsContentModifications else {
                throw AgendaError.unavailable("此系统日历不可编辑，或日程已经不存在。")
            }
            try eventStore.remove(record, span: scope == .occurrence ? .thisEvent : .futureEvents, commit: true)
            systemCache = nil
        } else {
            guard let context, let record = localRecords.first(where: { $0.id.uuidString == event.recordID }) else {
                throw AgendaError.unavailable("此日程已不存在。")
            }
            if record.recurrence.frequency != .never && scope == .occurrence {
                record.excludedOccurrences.insert(event.occurrenceDate.timeIntervalSince1970)
            } else {
                for child in localRecords where child.parentSeriesID == record.id { context.delete(child) }
                context.delete(record)
            }
            do { try context.save() } catch { context.rollback(); throw AgendaError.storage(error.localizedDescription) }
        }
        await refresh(around: lastCenter)
    }

    func saveTask(_ task: AgendaTask) async throws {
        guard let context else { throw AgendaError.storage("本地数据库不可用，任务没有保存。") }
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgendaError.validation("请输入任务名称。") }
        let records = try context.fetch(FetchDescriptor<LocalAgendaTask>())
        if let record = records.first(where: { $0.id == task.id }) {
            record.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines); record.notes = task.notes
            record.due = task.due; record.priority = task.priority; record.isComplete = task.isComplete
            record.reminderMinutes = task.reminderMinutes
        } else {
            var task = task; task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(LocalAgendaTask(task: task))
        }
        do { try context.save() } catch { context.rollback(); throw AgendaError.storage(error.localizedDescription) }
        reloadLocal(); await refreshNotifications()
    }

    func toggleTask(_ task: AgendaTask) async {
        var task = task; task.isComplete.toggle()
        do { try await saveTask(task) } catch { errorMessage = error.localizedDescription }
    }

    func deleteTask(_ task: AgendaTask) async throws {
        guard let context else { throw AgendaError.storage("本地数据库不可用。") }
        let records = try context.fetch(FetchDescriptor<LocalAgendaTask>())
        guard let record = records.first(where: { $0.id == task.id }) else { return }
        context.delete(record)
        do { try context.save() } catch { context.rollback(); throw AgendaError.storage(error.localizedDescription) }
        reloadLocal(); await refreshNotifications()
    }

    private func reloadLocal() {
        guard let context else { return }
        do {
            localRecords = try context.fetch(FetchDescriptor<LocalAgendaEvent>())
            tasks = try context.fetch(FetchDescriptor<LocalAgendaTask>()).map(\.snapshot).sorted {
                if $0.isComplete != $1.isComplete { return !$0.isComplete }
                if $0.due != $1.due { return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.title < $1.title
            }
            revision += 1
        } catch { errorMessage = "读取日程失败：\(error.localizedDescription)" }
    }

    private func occurrences(of record: LocalAgendaEvent, in range: DateInterval, floatingAllDay: Bool = true) -> [AgendaEvent] {
        let tz = TimeZone(identifier: record.timeZoneIdentifier) ?? timeZone
        let effectiveRange: DateInterval
        if record.isAllDay && floatingAllDay {
            effectiveRange = DateInterval(start: AgendaDates.rebase(range.start, from: timeZone, to: tz),
                                          end: AgendaDates.rebase(range.end, from: timeZone, to: tz))
        } else { effectiveRange = range }
        let duration = record.end.timeIntervalSince(record.start)
        let calendar = AgendaDates.calendar(tz)
        let allDayDays = max(1, calendar.dateComponents([.day], from: record.start, to: record.end).day ?? 1)
        return AgendaRecurrenceEngine.starts(start: record.start, duration: duration, rule: record.recurrence,
                                             timeZone: tz, in: effectiveRange, excluded: record.excludedOccurrences).map { start in
            let end = record.isAllDay ? (calendar.date(byAdding: .day, value: allDayDays, to: start) ?? start.addingTimeInterval(duration)) : start.addingTimeInterval(duration)
            let displayedStart = record.isAllDay && floatingAllDay ? AgendaDates.rebase(start, from: tz, to: timeZone) : start
            let displayedEnd = record.isAllDay && floatingAllDay ? AgendaDates.rebase(end, from: tz, to: timeZone) : end
            return AgendaEvent(id: "local:\(record.id):\(start.timeIntervalSince1970)", recordID: record.id.uuidString, source: .local,
                               title: record.title, start: displayedStart, end: displayedEnd, isAllDay: record.isAllDay,
                               location: record.location, notes: record.notes, meetingURL: record.meetingURL,
                               colorHex: record.colorHex, calendarID: "local", calendarName: "本地日历",
                               timeZoneIdentifier: record.timeZoneIdentifier, reminderMinutes: record.reminderMinutes,
                               recurrence: record.recurrence, isEditable: true, occurrenceDate: start)
        }.filter { AgendaDates.overlaps(start: $0.start, end: $0.end, interval: range) }
    }

    private func updateCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        hasCalendarAccess = status == .fullAccess
        switch status {
        case .fullAccess: calendarAccess = "已连接系统日历"
        case .denied: calendarAccess = "系统日历权限已拒绝。可在系统设置 › 隐私与安全性 › 日历中允许访问。本地日程不受影响。"
        case .restricted: calendarAccess = "系统限制了日历访问，本地日程可正常使用。"
        case .writeOnly: calendarAccess = "仅有写入权限。读取和管理系统日历需要完整访问权限。"
        default: calendarAccess = "尚未连接系统日历，本地日程可直接使用。"
        }
    }

    private func loadSystemEvents(in range: DateInterval) {
        guard hasCalendarAccess else { return }
        let available = eventStore.calendars(for: .event)
        calendars = available.map {
            AgendaCalendar(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title,
                           colorHex: Self.hex($0.cgColor), allowsChanges: $0.allowsContentModifications)
        }.sorted { $0.title < $1.title }
        var fetched = eventStore.events(matching: eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: available))
        if let extra = additionalRange {
            let extras = eventStore.events(matching: eventStore.predicateForEvents(withStart: extra.start, end: extra.end, calendars: available))
            let keys = Set(fetched.map { "\($0.eventIdentifier ?? $0.calendarItemIdentifier):\($0.startDate.timeIntervalSince1970)" })
            fetched += extras.filter { !keys.contains("\($0.eventIdentifier ?? $0.calendarItemIdentifier):\($0.startDate.timeIntervalSince1970)") }
        }
        // The menu-bar count always represents today, including when browsing a remote year.
        let todayDate = AgendaDates.solar(Date(), timeZone: timeZone)
        let today = AgendaDates.dayInterval(todayDate, timeZone: timeZone)
        if !range.contains(today.start) || !range.contains(today.end) {
            let todayRecords = eventStore.events(matching: eventStore.predicateForEvents(withStart: today.start, end: today.end, calendars: available))
            let keys = Set(fetched.map { "\($0.eventIdentifier ?? $0.calendarItemIdentifier):\($0.startDate.timeIntervalSince1970)" })
            fetched += todayRecords.filter { !keys.contains("\($0.eventIdentifier ?? $0.calendarItemIdentifier):\($0.startDate.timeIntervalSince1970)") }
        }
        systemRecords = [:]
        systemEvents = fetched.map { record in
            let key = "system:\(record.eventIdentifier ?? record.calendarItemIdentifier):\(record.startDate.timeIntervalSince1970)"
            systemRecords[key] = record
            let rule = Self.recurrence(from: record.recurrenceRules?.first)
            let eventZone = record.timeZone ?? .current
            let displayedStart = record.isAllDay ? AgendaDates.rebase(record.startDate, from: eventZone, to: timeZone) : record.startDate!
            let displayedEnd = record.isAllDay ? AgendaDates.rebase(record.endDate, from: eventZone, to: timeZone) : record.endDate!
            return AgendaEvent(id: key, recordID: record.eventIdentifier ?? record.calendarItemIdentifier, source: .system,
                               title: record.title ?? "未命名日程", start: displayedStart, end: displayedEnd,
                               isAllDay: record.isAllDay, location: record.location ?? "", notes: record.notes ?? "",
                               meetingURL: record.url?.absoluteString ?? "", colorHex: Self.hex(record.calendar.cgColor),
                               calendarID: record.calendar.calendarIdentifier, calendarName: record.calendar.title,
                               timeZoneIdentifier: eventZone.identifier,
                               reminderMinutes: AgendaSystemEventEdits.reminderMinutes(for: record),
                               recurrence: rule, isEditable: record.calendar.allowsContentModifications,
                               occurrenceDate: record.occurrenceDate ?? record.startDate)
        }
        systemCache = AgendaSystemCacheWindow(range: range, today: todayDate,
                                              timeZoneIdentifier: timeZone.identifier)
    }

    private func saveSystem(_ draft: AgendaDraft, event: AgendaEvent?, scope: AgendaEditScope) throws {
        updateCalendarAccess()
        guard hasCalendarAccess else { throw AgendaError.permission("没有系统日历完整访问权限，日程没有写入。请连接系统日历或选择本地日历。") }
        let record: EKEvent
        if let event {
            guard let existing = systemRecords[event.id] else { throw AgendaError.unavailable("日程已变更，请刷新后重新编辑。") }
            guard existing.calendar.allowsContentModifications else { throw AgendaError.permission("此日历为只读，无法修改。") }
            record = existing
        } else { record = EKEvent(eventStore: eventStore) }
        guard let calendar = eventStore.calendar(withIdentifier: draft.calendarID), calendar.allowsContentModifications else {
            throw AgendaError.unavailable("所选日历不存在或不允许写入，请重新选择。")
        }
        record.title = draft.title; record.startDate = draft.start; record.endDate = draft.end
        record.isAllDay = draft.isAllDay; record.location = draft.location; record.notes = draft.notes
        record.url = AgendaDates.safeMeetingURL(draft.meetingURL)
        record.calendar = calendar; record.timeZone = TimeZone(identifier: draft.timeZoneIdentifier)
        AgendaSystemEventEdits.applyReminder(draft.reminderMinutes, originalMinutes: event?.reminderMinutes, to: record)
        // Keep complex system recurrence details untouched unless the user changes recurrence settings.
        if event == nil || ((event?.isRecurring != true || scope == .series) && draft.recurrence != event?.recurrence) {
            record.recurrenceRules = Self.eventKitRule(draft.recurrence).map { [$0] } ?? []
        }
        try eventStore.save(record, span: scope == .occurrence ? .thisEvent : .futureEvents, commit: true)
    }

    private static func recurrence(from rule: EKRecurrenceRule?) -> AgendaRecurrence {
        guard let rule else { return AgendaRecurrence() }
        let frequency: AgendaRepeat
        switch rule.frequency { case .daily: frequency = .daily; case .weekly: frequency = .weekly; case .monthly: frequency = .monthly; case .yearly: frequency = .yearly; @unknown default: frequency = .never }
        return AgendaRecurrence(frequency: frequency, interval: rule.interval,
                                weekdays: rule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } ?? [], until: rule.recurrenceEnd?.endDate)
    }

    private static func eventKitRule(_ rule: AgendaRecurrence) -> EKRecurrenceRule? {
        guard rule.frequency != .never else { return nil }
        let frequency: EKRecurrenceFrequency
        switch rule.frequency { case .daily: frequency = .daily; case .weekly: frequency = .weekly; case .monthly: frequency = .monthly; case .yearly: frequency = .yearly; case .never: return nil }
        let weekdays = rule.weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: rule.interval,
                                daysOfTheWeek: rule.frequency == .weekly && !weekdays.isEmpty ? weekdays : nil,
                                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                daysOfTheYear: nil, setPositions: nil, end: rule.until.map(EKRecurrenceEnd.init(end:)))
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let color, let converted = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return "#3B82F6" }
        return String(format: "#%02X%02X%02X", Int(converted.redComponent * 255), Int(converted.greenComponent * 255), Int(converted.blueComponent * 255))
    }

    private func refreshNotifications() async {
        guard let service = notificationService else { return }
        let now = Date()
        let range = DateInterval(start: now, end: now.addingTimeInterval(366 * 86_400))
        let events = localRecords.flatMap { occurrences(of: $0, in: range, floatingAllDay: false) }
        do {
            let state = try await service.synchronize(events: events, tasks: tasks, enabled: preferences.notificationsEnabled, now: now)
            notificationStatus = state.message; notificationAuthorized = state.authorized
            notificationRefreshScheduler.schedule(at: state.nextRefreshDate) { [weak self] in
                Task { @MainActor in await self?.refreshNotifications() }
            }
        } catch {
            notificationStatus = "提醒未完全安排：\(error.localizedDescription)"
            notificationRefreshScheduler.schedule(at: Date().addingTimeInterval(30)) { [weak self] in
                Task { @MainActor in await self?.refreshNotifications() }
            }
        }
    }

    func showEventEditor(on date: SolarDate, event: AgendaEvent? = nil) {
        openWindow(title: event == nil ? "新建日程" : "日程详情", width: 520, height: 630) { close in
            AgendaEventEditor(store: self, selectedDate: date, event: event, close: close)
        }
    }

    func showTaskEditor(task: AgendaTask? = nil) {
        openWindow(title: task == nil ? "新建任务" : "编辑任务", width: 460, height: 410) { close in
            AgendaTaskEditor(store: self, task: task, close: close)
        }
    }

    private func openWindow<Content: View>(title: String, width: CGFloat, height: CGFloat, @ViewBuilder content: (@escaping () -> Void) -> Content) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content { [weak window] in window?.close() })
        window.minSize = NSSize(width: width, height: 360)
        windows.removeAll { !$0.isVisible }
        windows.append(window)
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
}

import SwiftUI

@MainActor
enum AgendaSystemEventEdits {
    /// -2 means a richer system alarm configuration that the simple editor should preserve.
    static func reminderMinutes(for record: EKEvent) -> Int {
        guard let alarms = record.alarms, !alarms.isEmpty else { return -1 }
        guard alarms.count == 1, let alarm = alarms.first, alarm.absoluteDate == nil,
              alarm.structuredLocation == nil, alarm.relativeOffset <= 0,
              alarm.relativeOffset.truncatingRemainder(dividingBy: 60) == 0 else { return -2 }
        return Int(-alarm.relativeOffset / 60)
    }

    /// EventKit supports multiple, absolute, and post-start alarms. A title/date edit must
    /// not flatten those settings into the editor's single relative-reminder control.
    static func applyReminder(_ minutes: Int, originalMinutes: Int?, to record: EKEvent) {
        guard originalMinutes == nil || minutes != originalMinutes else { return }
        record.alarms = minutes >= 0 ? [EKAlarm(relativeOffset: -Double(minutes) * 60)] : []
    }
}
