import AppKit
import LunarCore
import SwiftUI

private enum AgendaStyle {
    static func color(_ hex: String) -> Color {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x3B82F6
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    @MainActor static func time(_ date: Date, preferences: AppPreferences) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = AgendaDates.calendar(preferences.timeZone)
        formatter.timeZone = preferences.timeZone
        formatter.dateFormat = preferences.use24HourTime ? "HH:mm" : "ah:mm"
        return formatter.string(from: date)
    }
    @MainActor static func day(_ date: Date, full: Bool = false, preferences: AppPreferences) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = AgendaDates.calendar(preferences.timeZone)
        formatter.timeZone = preferences.timeZone
        formatter.shortWeekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        formatter.dateFormat = full ? "yyyy年M月d日 EEE" : "M月d日 EEE"
        return formatter.string(from: date)
    }
}

struct AgendaSummary: View {
    @Environment(\.chronoTheme) private var theme
    @ObservedObject var store: AgendaStore
    let selectedDate: SolarDate
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(10)) {
            HStack {
                Text("当日日程").font(theme.font(size: 14, weight: .semibold))
                Spacer()
                Button { store.showEventEditor(on: selectedDate) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("新建日程")
                    .accessibilityLabel("新建日程")
            }
            let events = store.events(on: selectedDate)
            if events.isEmpty {
                Label("这一天还没有日程", systemImage: "sun.max")
                    .font(theme.font(size: 13)).foregroundStyle(.secondary).padding(.vertical, 3)
            } else {
                ForEach(Array(events.prefix(2))) { event in
                    Button {
                        store.showEventEditor(on: selectedDate, event: event)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(AgendaStyle.color(event.colorHex)).frame(width: 6, height: 6)
                            Text(event.isAllDay ? "全天" : AgendaStyle.time(event.start, preferences: store.preferences))
                                .font(theme.font(size: 13).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: (store.preferences.use24HourTime ? 48 : 76) * theme.textScale, alignment: .leading)
                            Text(event.title)
                                .font(theme.font(size: 14, weight: .medium))
                                .lineLimit(2)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(event.title)，\(event.isAllDay ? "全天" : AgendaStyle.time(event.start, preferences: store.preferences))，查看日程详情")
                }
                if events.count > 2 { Text("还有 \(events.count - 2) 项，可在日程中查看").font(theme.font(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .padding(theme.layoutDensity.spacing(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .task(id: selectedDate.key) { await store.refresh(around: selectedDate) }
    }
}

struct AgendaPanel: View {
    @Environment(\.chronoTheme) private var theme
    @ObservedObject var store: AgendaStore
    let selectedDate: SolarDate
    var compact = false
    @ObservedObject private var preferences: AppPreferences
    @State private var range = "default"
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date().addingTimeInterval(7 * 86_400)

    init(store: AgendaStore, selectedDate: SolarDate, compact: Bool = false) {
        self.store = store; self.selectedDate = selectedDate; self.compact = compact
        _preferences = ObservedObject(wrappedValue: store.preferences)
    }

    private var upcomingInterval: DateInterval {
        let timeZone = preferences.agendaTimeZone
        let calendar = AgendaDates.calendar(timeZone)
        let tomorrow = AgendaDates.date(selectedDate.adding(days: 1), timeZone: timeZone)
        let end: Date
        if range == "custom" {
            let start = calendar.startOfDay(for: rangeStart)
            let inclusiveEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEnd)) ?? rangeEnd
            return DateInterval(start: start, end: max(start, min(inclusiveEnd, start.addingTimeInterval(366 * 86_400))))
        } else if range == "tomorrow" {
            end = AgendaDates.date(selectedDate.adding(days: 2), timeZone: timeZone)
        } else if range == "week" {
            end = calendar.dateInterval(of: .weekOfYear, for: AgendaDates.date(selectedDate, timeZone: timeZone))?.end ?? tomorrow
        } else {
            end = AgendaDates.date(selectedDate.adding(days: max(1, preferences.agendaRangeDays) + 1), timeZone: timeZone)
        }
        return DateInterval(start: tomorrow, end: max(tomorrow, end))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(12)) {
            header
                .padding(theme.layoutDensity.spacing(12))
                .glassCard()
            if let error = store.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(theme.font(size: 12)).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            dayEvents
                .padding(theme.layoutDensity.spacing(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            upcoming
                .padding(theme.layoutDensity.spacing(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            tasks
                .padding(theme.layoutDensity.spacing(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            if !store.hasCalendarAccess {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.calendarAccess).font(theme.font(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("连接 Apple 日历") { Task { await store.requestCalendarAccess() } }.font(theme.font(size: 12))
                    }
                }
                .padding(theme.layoutDensity.spacing(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
        }
        .environment(\.timeZone, preferences.timeZone)
        .environment(\.calendar, AgendaDates.calendar(preferences.timeZone))
        .task(id: selectedDate.key) { await store.refresh(around: selectedDate) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(selectedDate.year))年\(selectedDate.month)月\(selectedDate.day)日 \(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][selectedDate.weekday])")
                    .font(theme.font(size: compact ? 15 : 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(store.events(on: selectedDate).count) 项日程 · \(preferences.agendaTimeZone.identifier)")
                    .font(theme.font(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { store.showEventEditor(on: selectedDate) } label: {
                Image(systemName: "calendar.badge.plus")
            }.buttonStyle(.bordered).help("新建日程")
        }
    }

    private var dayEvents: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(10)) {
            Text("当日日程").font(theme.font(size: 14, weight: .semibold))
            let events = store.events(on: selectedDate)
            if events.isEmpty {
                Label("这一天还没有日程", systemImage: "sun.max")
                    .font(theme.font(size: 13)).foregroundStyle(.secondary).padding(.vertical, 3)
            } else {
                ForEach(events) { event in
                    AgendaEventRow(store: store, event: event, compact: compact)
                }
            }
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(10)) {
            HStack {
                Text("即将到来").font(theme.font(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Picker("范围", selection: $range) {
                    Text("未来 \(preferences.agendaRangeDays) 天").tag("default")
                    Text("明天").tag("tomorrow")
                    Text("本周").tag("week")
                    Text("自定义").tag("custom")
                }.labelsHidden().fixedSize().controlSize(.small)
            }
            if range == "custom" {
                VStack(alignment: .leading, spacing: 5) {
                    DatePicker("从", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("至", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                    Text("单次最多查看 366 天").font(theme.font(size: 11)).foregroundStyle(.secondary)
                }
                .onChange(of: rangeStart) { _, start in
                    if rangeEnd < start { rangeEnd = start }
                }
            }
            let events = store.events(in: upcomingInterval)
            if events.isEmpty { Text("这段时间没有日程").font(theme.font(size: 13)).foregroundStyle(.secondary) }
            ForEach(Array(events.prefix(100))) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(AgendaStyle.day(event.start, preferences: store.preferences)).font(theme.font(size: 11)).foregroundStyle(.secondary)
                    AgendaEventRow(store: store, event: event, compact: compact)
                }
            }
            if events.count > 100 { Text("已显示前 100 项，请缩小日期范围查看其余日程。").font(theme.font(size: 12)).foregroundStyle(.secondary) }
        }
        .task(id: "\(range)-\(rangeStart.timeIntervalSince1970)-\(rangeEnd.timeIntervalSince1970)-\(preferences.timeZone.identifier)") {
            await store.setAdditionalRange(range == "custom" ? upcomingInterval : nil)
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(10)) {
            let today = AgendaDates.solar(Date(), timeZone: preferences.agendaTimeZone)
            let todayTasks = store.tasks.filter { task in task.due.map { AgendaDates.solar($0, timeZone: preferences.agendaTimeZone) == today } ?? false }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("提醒与任务").font(theme.font(size: 14, weight: .semibold))
                    Text("今日完成 \(todayTasks.filter(\.isComplete).count)/\(todayTasks.count)").font(theme.font(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.showTaskEditor() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("新建任务").accessibilityLabel("新建任务")
            }
            let visible = store.tasks.filter { preferences.showCompletedTasks || !$0.isComplete }
            if visible.isEmpty { Text("没有待办任务").font(theme.font(size: 13)).foregroundStyle(.secondary) }
            ForEach(visible) { task in
                HStack(alignment: .top, spacing: 8) {
                    Button { Task { await store.toggleTask(task) } } label: {
                        Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(theme.font(size: 16)).frame(width: 20 * theme.textScale, height: 20 * theme.textScale)
                            .foregroundStyle(task.isComplete ? Color.accentColor : .secondary)
                    }.buttonStyle(.plain).accessibilityLabel(task.isComplete ? "取消完成 \(task.title)" : "完成 \(task.title)")
                    Button { store.showTaskEditor(task: task) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(theme.font(size: 14)).strikethrough(task.isComplete).lineLimit(2)
                                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(task.isComplete ? .secondary : .primary)
                            if let due = task.due {
                                Text("\(AgendaStyle.day(due, preferences: store.preferences)) \(AgendaStyle.time(due, preferences: store.preferences))")
                                    .font(theme.font(size: 11)).foregroundStyle(due < Date() && !task.isComplete ? Color.orange : .secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if task.priority > 0 { Text(task.priority == 2 ? "!!" : "!").foregroundStyle(task.priority == 2 ? Color.red : .orange).font(theme.font(size: 12, weight: .bold)) }
                }
                .padding(.vertical, 3)
            }
        }
    }
}

private struct AgendaEventRow: View {
    @Environment(\.chronoTheme) private var theme
    @ObservedObject var store: AgendaStore
    let event: AgendaEvent
    var compact: Bool
    @State private var hovered = false

    private var endFallsOnAnotherDay: Bool {
        !AgendaDates.calendar(store.timeZone).isDate(event.start, inSameDayAs: event.end)
    }

    private var timeDescription: String {
        event.isAllDay ? "全天" : "\(AgendaStyle.day(event.start, full: true, preferences: store.preferences)) \(AgendaStyle.time(event.start, preferences: store.preferences)) 至 \(AgendaStyle.day(event.end, full: true, preferences: store.preferences)) \(AgendaStyle.time(event.end, preferences: store.preferences))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.showEventEditor(on: AgendaDates.solar(event.start, timeZone: store.timeZone), event: event)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(AgendaStyle.color(event.colorHex)).frame(width: 3)
                    timeColumn
                        .frame(width: (compact ? 72 : 116) * theme.textScale, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(event.title).font(theme.font(size: 14, weight: .medium)).lineLimit(2)
                                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if event.reminderMinutes != -1 {
                                Image(systemName: "bell").font(theme.font(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label(event.location, systemImage: "mappin.and.ellipse")
                                .font(theme.font(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !event.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(event.notes).font(theme.font(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(event.calendarName + (event.isRecurring ? " · \(event.recurrence.summary)" : ""))
                            .font(theme.font(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.title)，\(timeDescription)，\(event.calendarName)，查看日程详情")

            if let url = event.safeMeetingURL {
                Link(destination: url) {
                    Label("加入会议 · \(url.host ?? "会议链接")", systemImage: "video")
                        .font(theme.font(size: 12)).lineLimit(1)
                }
                .padding(.leading, 23)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .help(url.absoluteString)
            }
        }
        .background(hovered ? Color.primary.opacity(0.055) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovered = $0 }
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            if event.isAllDay {
                Text("全天")
            } else if compact || !store.preferences.use24HourTime {
                Text(AgendaStyle.time(event.start, preferences: store.preferences))
                Text("– \(AgendaStyle.time(event.end, preferences: store.preferences))")
            } else {
                Text("\(AgendaStyle.time(event.start, preferences: store.preferences)) – \(AgendaStyle.time(event.end, preferences: store.preferences))")
            }
            if !event.isAllDay && endFallsOnAnotherDay {
                Text(AgendaStyle.day(event.end, preferences: store.preferences))
                    .font(theme.font(size: 11))
            }
        }
        .font(theme.font(size: 13).monospacedDigit())
        .foregroundStyle(.secondary)
        .help(timeDescription)
    }
}

struct AgendaSettingsSection: View {
    @ObservedObject var store: AgendaStore
    @ObservedObject private var preferences: AppPreferences
    init(store: AgendaStore) {
        self.store = store
        _preferences = ObservedObject(wrappedValue: store.preferences)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日历来源").font(.system(size: 14, weight: .semibold))
            Label("本地日历 · 保存在这台 Mac", systemImage: "internaldrive")
            Text(store.calendarAccess).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !store.hasCalendarAccess {
                Button("连接 Apple 日历…") { Task { await store.requestCalendarAccess() } }
            }
            ForEach(store.calendars) { calendar in
                Toggle(isOn: Binding(get: { !store.excludedCalendarIDs.contains(calendar.id) }, set: { store.setCalendar(calendar.id, visible: $0) })) {
                    HStack(spacing: 6) {
                        Circle().fill(AgendaStyle.color(calendar.colorHex)).frame(width: 7, height: 7)
                        Text(calendar.title)
                        Text(calendar.source + (calendar.allowsChanges ? "" : " · 只读")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text("提醒通知").font(.system(size: 14, weight: .semibold))
            Toggle("启用本地日程与任务通知", isOn: $preferences.notificationsEnabled)
            Text(store.notificationStatus).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("允许提醒通知…") { Task { await store.requestNotificationAccess() } }
            Text("本地日程和任务使用 macOS 通知；系统日历日程由 Apple 日历提醒。最近 60 条本地提醒会预先安排，应用运行时自动补充。").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .task { await store.refresh(around: AgendaDates.solar(Date(), timeZone: preferences.timeZone)) }
    }
}
