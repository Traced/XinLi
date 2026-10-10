import AppKit
import LunarCore
import SwiftUI

struct AgendaEventEditor: View {
    @ObservedObject var store: AgendaStore
    let selectedDate: SolarDate
    let event: AgendaEvent?
    let close: () -> Void
    @State private var draft: AgendaDraft
    @State private var scope = AgendaEditScope.occurrence
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var endRepeat = false
    @ObservedObject private var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    private var theme: ResolvedCalendarTheme { ResolvedCalendarTheme(preferences: preferences, colorScheme: colorScheme) }
    private let colors = ["#3B82F6", "#22A06B", "#F59E0B", "#8B5CF6", "#EF4444", "#64748B"]

    init(store: AgendaStore, selectedDate: SolarDate, event: AgendaEvent?, close: @escaping () -> Void) {
        self.store = store; self.selectedDate = selectedDate; self.event = event; self.close = close
        _preferences = ObservedObject(wrappedValue: store.preferences)
        let initial = event.map(AgendaDraft.init(event:)) ?? store.newDraft(on: selectedDate)
        _draft = State(initialValue: initial)
        _endRepeat = State(initialValue: initial.recurrence.until != nil)
    }

    private var editable: Bool { event?.isEditable ?? true }
    private var isLocal: Bool { draft.calendarID == "local" }
    private var dateComponents: DatePickerComponents { draft.isAllDay ? [.date] : [.date, .hourAndMinute] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Form {
                    Section {
                        TextField("日程名称", text: $draft.title)
                        Toggle("全天日程", isOn: $draft.isAllDay)
                            .onChange(of: draft.isAllDay) { _, allDay in normalizeDates(allDay: allDay) }
                        DatePicker("开始", selection: $draft.start, displayedComponents: dateComponents)
                        if draft.isAllDay {
                            DatePicker("结束", selection: Binding(get: {
                                AgendaDates.calendar(preferences.agendaTimeZone).date(byAdding: .day, value: -1, to: draft.end) ?? draft.end
                            }, set: { inclusive in
                                let c = AgendaDates.calendar(preferences.agendaTimeZone)
                                draft.end = c.date(byAdding: .day, value: 1, to: c.startOfDay(for: inclusive)) ?? inclusive
                            }), displayedComponents: .date)
                        } else {
                            DatePicker("结束", selection: $draft.end, displayedComponents: dateComponents)
                        }
                        Text("显示时区：\(preferences.agendaTimeZone.identifier)").font(theme.font(size: 12)).foregroundStyle(.secondary)
                        TextField("地点", text: $draft.location)
                        TextField("会议链接（https://…）", text: $draft.meetingURL)
                        if let url = AgendaDates.safeMeetingURL(draft.meetingURL) {
                            Link(destination: url) { Label("打开会议链接 · \(url.host ?? "")", systemImage: "video") }
                        }
                        TextField("备注", text: $draft.notes, axis: .vertical).lineLimit(3...6)
                    }
                    Section("日历和提醒") {
                        Picker("所属日历", selection: $draft.calendarID) {
                            Text("本地日历").tag("local")
                            ForEach(store.writableCalendars) { calendar in
                                Text("\(calendar.title) · \(calendar.source)").tag(calendar.id)
                            }
                            if let event, event.source == .system, !store.writableCalendars.contains(where: { $0.id == event.calendarID }) {
                                Text(event.calendarName).tag(event.calendarID)
                            }
                        }
                        .disabled(event != nil)
                        if isLocal {
                            Picker("事件颜色", selection: $draft.colorHex) {
                                Text("蓝色 · 工作").tag("#3B82F6")
                                Text("绿色 · 个人").tag("#22A06B")
                                Text("橙色 · 重要").tag("#F59E0B")
                                Text("紫色 · 生活").tag("#8B5CF6")
                                Text("红色 · 紧急").tag("#EF4444")
                                Text("灰色").tag("#64748B")
                                if !colors.contains(draft.colorHex) { Text("自定义颜色").tag(draft.colorHex) }
                            }
                        } else { Text("系统日程颜色跟随所属日历。").font(theme.font(size: 12)).foregroundStyle(.secondary) }
                        ReminderPicker(minutes: $draft.reminderMinutes)
                        if isLocal && draft.reminderMinutes >= 0 && (!preferences.notificationsEnabled || !store.notificationAuthorized) {
                            Text("提醒尚未启用。保存后可在设置中允许通知；日程仍会正常保存。").font(theme.font(size: 12)).foregroundStyle(.orange)
                        }
                    }
                    Section("重复") {
                        Picker("重复频率", selection: $draft.recurrence.frequency) {
                            ForEach(AgendaRepeat.allCases) { Text($0.title).tag($0) }
                        }
                        .disabled(event?.isRecurring == true && scope == .occurrence)
                        if event?.isRecurring == true && scope == .occurrence {
                            Text("仅修改这一次日程，不改变系列的重复规则。选择整个系列后可修改重复设置。").font(theme.font(size: 12)).foregroundStyle(.secondary)
                        }
                        if draft.recurrence.frequency != .never {
                            Stepper("每 \(draft.recurrence.interval) 个周期", value: $draft.recurrence.interval, in: 1...999)
                            if draft.recurrence.frequency == .weekly { weekdayPicker }
                            Toggle("设置重复结束日期", isOn: $endRepeat)
                                .onChange(of: endRepeat) { _, enabled in
                                    draft.recurrence.until = enabled ? AgendaDates.calendar(preferences.timeZone).date(byAdding: .year, value: 1, to: draft.start) : nil
                                }
                            if endRepeat {
                                DatePicker("结束重复", selection: Binding(get: { draft.recurrence.until ?? draft.start }, set: { value in
                                    let c = AgendaDates.calendar(preferences.timeZone)
                                    draft.recurrence.until = c.date(byAdding: .day, value: 1, to: c.startOfDay(for: value))?.addingTimeInterval(-1)
                                }), in: draft.start..., displayedComponents: .date)
                            }
                            if draft.recurrence.frequency == .monthly || draft.recurrence.frequency == .yearly {
                                Text("不存在的日期自动跳过，例如每月 31 日会跳过 2 月。").font(theme.font(size: 12)).foregroundStyle(.secondary)
                            }
                            Text("重复规则保留创建时的时区：\(draft.timeZoneIdentifier)。").font(theme.font(size: 12)).foregroundStyle(.secondary)
                        }
                        if event?.isRecurring == true {
                            Picker("修改范围", selection: $scope) {
                                Text("仅此日程").tag(AgendaEditScope.occurrence)
                                Text(event?.source == .system ? "此日程及后续日程" : "整个系列").tag(AgendaEditScope.series)
                            }
                            if event?.source == .system {
                                Text("修改频率会替换系统日历的原重复规则；不修改时保留原有规则。").font(theme.font(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(!editable || saving)
            }
            Divider()
            HStack {
                if event != nil && editable {
                    Button("删除日程", role: .destructive) { confirmDelete = true }.disabled(saving)
                }
                if !editable {
                    Text("此日历为只读").font(theme.font(size: 12)).foregroundStyle(.secondary)
                    if let url = event?.safeMeetingURL { Link("进入会议", destination: url) }
                }
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                if editable {
                    Button(saving ? "正在保存…" : "保存") {
                        saving = true
                        Task {
                            do { try await store.save(draft, editing: event, scope: scope); close() }
                            catch { self.error = error.localizedDescription; saving = false }
                        }
                    }.keyboardShortcut(.defaultAction).disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(16)
        }
        .font(theme.font(size: 13))
        .scrollIndicators(preferences.showsScrollIndicators ? .automatic : .hidden)
        .environment(\.timeZone, preferences.timeZone)
        .environment(\.calendar, AgendaDates.calendar(preferences.timeZone))
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(minWidth: 470, minHeight: 360)
        .alert("未能保存日程", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("删除\(event?.isRecurring == true ? (scope == .occurrence ? "这一次日程" : (event?.source == .system ? "这一次及后续日程" : "整个日程系列")) : "日程")？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                guard let event else { return }
                saving = true
                Task {
                    do { try await store.delete(event, scope: scope); close() }
                    catch { self.error = error.localizedDescription; saving = false }
                }
            }
        }
        .onChange(of: preferences.timeZone.identifier) { previous, current in
            guard let oldZone = TimeZone(identifier: previous), let newZone = TimeZone(identifier: current) else { return }
            draft.updateDisplayTimeZone(from: oldZone, to: newZone, isNew: event == nil)
        }
        .task { await store.refresh(around: selectedDate) }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            Text("重复日").font(theme.font(size: 12))
            Spacer(minLength: 4)
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                Toggle(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][day - 1], isOn: Binding(get: {
                    draft.recurrence.weekdays.contains(day)
                }, set: { included in
                    if included { draft.recurrence.weekdays.append(day) }
                    else { draft.recurrence.weekdays.removeAll { $0 == day } }
                })).toggleStyle(.button).controlSize(.mini)
            }
        }
    }

    private func normalizeDates(allDay: Bool) {
        let c = AgendaDates.calendar(preferences.agendaTimeZone)
        if allDay {
            draft.start = c.startOfDay(for: draft.start)
            draft.end = c.date(byAdding: .day, value: 1, to: c.startOfDay(for: max(draft.start, draft.end))) ?? draft.start.addingTimeInterval(86_400)
        } else {
            draft.start = c.date(bySettingHour: 9, minute: 0, second: 0, of: draft.start) ?? draft.start
            draft.end = draft.start.addingTimeInterval(3600)
        }
    }
}

struct AgendaTaskEditor: View {
    @ObservedObject var store: AgendaStore
    let original: AgendaTask?
    let close: () -> Void
    @State private var task: AgendaTask
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @ObservedObject private var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    private var theme: ResolvedCalendarTheme { ResolvedCalendarTheme(preferences: preferences, colorScheme: colorScheme) }

    init(store: AgendaStore, task: AgendaTask?, close: @escaping () -> Void) {
        self.store = store; original = task; self.close = close
        _preferences = ObservedObject(wrappedValue: store.preferences)
        let initial = task ?? AgendaTask(id: UUID(), title: "", notes: "", due: nil, priority: 0, isComplete: false,
                                        reminderMinutes: store.preferences.defaultReminderMinutes)
        _task = State(initialValue: initial); _hasDue = State(initialValue: initial.due != nil)
        _due = State(initialValue: initial.due ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("任务名称", text: $task.title)
                TextField("备注", text: $task.notes, axis: .vertical).lineLimit(2...4)
                Toggle("设置截止日期", isOn: $hasDue)
                if hasDue { DatePicker("截止", selection: $due, displayedComponents: [.date, .hourAndMinute]) }
                Picker("优先级", selection: $task.priority) {
                    Text("普通").tag(0); Text("中").tag(1); Text("高").tag(2)
                }
                if hasDue { ReminderPicker(minutes: $task.reminderMinutes) }
                Toggle("已完成", isOn: $task.isComplete)
                if hasDue && task.reminderMinutes >= 0 && (!preferences.notificationsEnabled || !store.notificationAuthorized) {
                    Text("提醒尚未启用，可在设置中允许通知。").font(theme.font(size: 12)).foregroundStyle(.orange)
                }
            }.formStyle(.grouped).disabled(saving)
            Divider()
            HStack {
                if original != nil { Button("删除任务", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button(saving ? "正在保存…" : "保存") {
                    task.due = hasDue ? due : nil; saving = true
                    Task {
                        do { try await store.saveTask(task); close() }
                        catch { self.error = error.localizedDescription; saving = false }
                    }
                }.keyboardShortcut(.defaultAction).disabled(saving || task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)
        }
        .font(theme.font(size: 13))
        .scrollIndicators(preferences.showsScrollIndicators ? .automatic : .hidden)
        .environment(\.timeZone, preferences.timeZone)
        .environment(\.calendar, AgendaDates.calendar(preferences.timeZone))
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(minWidth: 420, minHeight: 350)
        .alert("任务操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("删除这项任务？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                saving = true
                Task {
                    do { try await store.deleteTask(task); close() }
                    catch { self.error = error.localizedDescription; saving = false }
                }
            }
        }
    }
}

private struct ReminderPicker: View {
    @Binding var minutes: Int
    private let choices = [-1, 0, 5, 10, 15, 30, 60, 120, 1_440]
    var body: some View {
        Picker("提前提醒", selection: $minutes) {
            Text("不提醒").tag(-1)
            Text("准时").tag(0)
            Text("5 分钟").tag(5); Text("10 分钟").tag(10); Text("15 分钟").tag(15)
            Text("30 分钟").tag(30); Text("1 小时").tag(60); Text("2 小时").tag(120); Text("1 天").tag(1_440)
            if minutes == -2 { Text("系统提醒（保留原设置）").tag(-2) }
            else if !choices.contains(minutes) { Text("\(minutes) 分钟").tag(minutes) }
        }
    }
}
