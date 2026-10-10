import Foundation
@preconcurrency import UserNotifications

struct AgendaNotificationState: Sendable {
    var authorized: Bool
    var message: String
    var nextRefreshDate: Date? = nil
}

struct AgendaReminder: Sendable, Equatable {
    var id: String
    var title: String
    var body: String
    var date: Date
    var signature: String { "\(id)|\(title)|\(body)|\(date.timeIntervalSince1970)" }
}

/// Pure scheduling policy: keep a bounded set and refill shortly after the earliest
/// pending reminder fires. With no overflow there is no background refill timer.
struct AgendaNotificationPlan: Sendable {
    var upcoming: [AgendaReminder]
    var hasOverflow: Bool
    var nextRefreshDate: Date?

    init(events: [AgendaEvent], tasks: [AgendaTask], now: Date, limit: Int = 60) {
        var reminders: [AgendaReminder] = events.compactMap { event in
            guard event.reminderMinutes >= 0 else { return nil }
            let fire = event.start.addingTimeInterval(-Double(event.reminderMinutes) * 60)
            guard fire > now else { return nil }
            return AgendaReminder(id: "chrono.event.\(event.id)", title: event.title,
                                  body: event.location.isEmpty ? "日程即将开始" : event.location, date: fire)
        }
        reminders += tasks.compactMap { task in
            guard !task.isComplete, let due = task.due, task.reminderMinutes >= 0 else { return nil }
            let fire = due.addingTimeInterval(-Double(task.reminderMinutes) * 60)
            guard fire > now else { return nil }
            return AgendaReminder(id: "chrono.task.\(task.id)", title: task.title, body: "任务即将到期", date: fire)
        }
        reminders.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        upcoming = Array(reminders.prefix(max(1, limit)))
        hasOverflow = reminders.count > max(1, limit)
        nextRefreshDate = hasOverflow ? upcoming.first?.date.addingTimeInterval(0.25) : nil
    }
}

@MainActor
final class AgendaNotificationRefreshScheduler {
    private var timer: Timer?
    private(set) var scheduledDate: Date?

    func schedule(at date: Date?, action: @escaping @MainActor () -> Void) {
        guard scheduledDate != date else { return }
        timer?.invalidate()
        timer = nil
        scheduledDate = date
        guard let date else { return }
        let timer = Timer(timeInterval: max(0.01, date.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.scheduledDate == date else { return }
                self.timer = nil
                self.scheduledDate = nil
                action()
            }
        }
        timer.tolerance = 0.1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

@MainActor
final class AgendaNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private var lastSignature: String?
    private var scheduledSignatures: [String: String] = [:]
    private var synchronizationTask: Task<AgendaNotificationState, Error>?
    override init() {
        center = UNUserNotificationCenter.current()
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func synchronize(events: [AgendaEvent], tasks: [AgendaTask], enabled: Bool, now: Date) async throws -> AgendaNotificationState {
        let previous = synchronizationTask
        let next = Task { @MainActor in
            _ = try? await previous?.value
            return try await self.performSynchronization(events: events, tasks: tasks, enabled: enabled, now: now)
        }
        synchronizationTask = next
        return try await next.value
    }

    private func performSynchronization(events: [AgendaEvent], tasks: [AgendaTask], enabled: Bool, now: Date) async throws -> AgendaNotificationState {
        let settings = await center.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        guard enabled, authorized else {
            let existing = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix("chrono.") }.map(\.identifier))
            lastSignature = nil
            scheduledSignatures = [:]
            let message: String
            if !enabled { message = "通知已关闭" }
            else if settings.authorizationStatus == .denied { message = "通知权限被拒绝，请在系统设置 › 通知中允许心历。" }
            else { message = "尚未允许通知，请点击“允许提醒通知”。" }
            return AgendaNotificationState(authorized: authorized, message: message)
        }
        let plan = AgendaNotificationPlan(events: events, tasks: tasks, now: now)
        let signature = plan.upcoming.map(\.signature).joined(separator: "\n")
        if signature != lastSignature {
            let existing = await center.pendingNotificationRequests()
            let pendingIDs = Set(existing.map(\.identifier))
            let desiredIDs = Set(plan.upcoming.map(\.id))
            center.removePendingNotificationRequests(withIdentifiers: existing.filter {
                $0.identifier.hasPrefix("chrono.") && !desiredIDs.contains($0.identifier)
            }.map(\.identifier))
            for reminder in plan.upcoming {
                // Replenishing the 61st reminder leaves the other 59 pending requests untouched.
                guard scheduledSignatures[reminder.id] != reminder.signature || !pendingIDs.contains(reminder.id) else { continue }
                let content = UNMutableNotificationContent()
                content.title = reminder.title; content.body = reminder.body; content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                scheduledSignatures[reminder.id] = reminder.signature
            }
            scheduledSignatures = scheduledSignatures.filter { desiredIDs.contains($0.key) }
            lastSignature = signature
        }
        return AgendaNotificationState(authorized: true,
            message: "已安排 \(plan.upcoming.count) 条提醒" + (plan.hasOverflow ? "（最近 60 条；运行应用时自动补充）" : ""),
            nextRefreshDate: plan.nextRefreshDate)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
