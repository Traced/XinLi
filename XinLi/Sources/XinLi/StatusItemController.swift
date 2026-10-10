import AppKit
import Combine
import LunarCore
import SwiftUI

/// 菜单栏图标及日历弹出窗口
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private lazy var popoverInteraction = PopoverInteractionCoordinator(popover: popover)
    private let popoverSizing = PopoverSizingCoordinator()
    private let store = DataStore.shared
    private let model: CalendarViewModel
    private let menu = AppMenu()

    private var shownDay: SolarDate?
    private var shownAgendaDay: SolarDate?
    private var statusBarDisplay = StatusBarDisplay.load()
    private var timer: Timer?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var updateWindow: UpdateHolidaysWindowController?
    private var customEventsWindow: CustomEventsWindowController?
    private var statusBarSettingsWindow: StatusBarSettingsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var agendaObserver: AnyCancellable?
    private var dataObserver: AnyCancellable?

    override init() {
        model = CalendarViewModel(store: store)
        super.init()
        // AppPreferences may migrate a legacy calendar zone during model init.
        statusBarDisplay = StatusBarDisplay.load()

        // 记住用户按住 Command 键拖动后的图标位置
        // Keep the saved menu-bar position across the XinLi project rename.
        statusItem.autosaveName = "WanNianLiSwift"

        menu.onUpdateHolidays = { [weak self] in self?.showUpdateWindow() }
        menu.onEditCustomEvents = { [weak self] in self?.showCustomEventsWindow() }
        menu.onEditStatusBar = { [weak self] in self?.showStatusBarSettings() }
        menu.onSettings = { [weak self] in self?.showSettings() }
        menu.onNewEvent = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil)
            AgendaStore.shared.showEventEditor(on: self.model.selectedDate)
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        let hosting = NSHostingController(rootView: CalendarPopoverRoot(model: model, menu: menu, sizing: popoverSizing))
        // The measured scroll document is the only sizing authority. Automatic
        // hosting constraints can retain the taller previous page's minimum.
        hosting.sizingOptions = []
        (hosting.view as? NSHostingView<CalendarPopoverRoot>)?.sizingOptions = []
        popover.contentViewController = hosting
        popoverSizing.attach(to: popover)
        _ = popoverInteraction
        popover.animates = AppPreferences.shared.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self

        refreshStatusItem(force: true)
        // 节日设置、假日信息变化时，更新图标的提示文字
        dataObserver = store.$data.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshStatusItem(force: true)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppearance),
                                               name: AppearanceMode.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(statusBarDisplayDidChange),
                                               name: StatusBarDisplay.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockDidChange),
                                               name: .NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockDidChange),
                                               name: .NSSystemClockDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clockDidChange),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange), name: AppPreferences.didChange, object: nil)
        agendaObserver = AgendaStore.shared.$revision.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatusItem(force: true) }
        }
        Task { await AgendaStore.shared.refresh(around: model.selectedDate) }
        scheduleStatusItemTimer()
    }

    private func refreshStatusItem(force: Bool = false) {
        let now = Date()
        let today = statusBarDisplay.calendarDate(at: now)
        guard let button = statusItem.button else { return }
        // 月历按它独立配置的时区标记“今天”。
        model.refreshToday()
        let dayChanged = today != shownDay
        let agendaToday = AgendaDates.solar(now, timeZone: AppPreferences.shared.agendaTimeZone)
        if shownAgendaDay != agendaToday {
            shownAgendaDay = agendaToday
            Task { await AgendaStore.shared.refresh(around: model.selectedDate) }
        }
        if force || dayChanged {
            shownDay = today
            let day = CalendarDay(date: today, data: store.data)
            let zone = statusBarDisplay.timeZone
            let zoneName = zone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? zone.identifier
            button.toolTip = "\(day.solarText) \(day.weekdayName)\n\(day.lunarText)\n\(zoneName)（\(zone.identifier)）"
        }
        if statusBarDisplay.format == .icon {
            if force || dayChanged {
                statusItem.length = NSStatusItem.squareLength
                button.title = ""
                button.image = MenuBarIcon.image(day: today.day)
                button.imagePosition = .imageOnly
            }
        } else {
            if force {
                statusItem.length = NSStatusItem.variableLength
                button.image = AppPreferences.shared.showStatusIcon ? MenuBarIcon.image(day: today.day) : nil
                button.imagePosition = AppPreferences.shared.showStatusIcon ? .imageLeading : .noImage
                // Panel typography is independent of the macOS menu bar.
                // Fixed-width system digits also keep the clock from shifting.
                button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            }
            if dayChanged && AppPreferences.shared.showStatusIcon { button.image = MenuBarIcon.image(day: today.day) }
            let title = statusBarDisplay.renderedTitle(at: now, remainingEvents: AgendaStore.shared.remainingCount(at: now))
            if button.title != title { button.title = title }
        }
        button.setAccessibilityLabel("心历，\(button.title.isEmpty ? button.toolTip ?? "" : button.title)")
    }

    @objc private func statusBarDisplayDidChange() {
        statusBarDisplay = StatusBarDisplay.load()
        refreshStatusItem(force: true)
        scheduleStatusItemTimer()
    }

    @objc private func clockDidChange() {
        refreshStatusItem(force: true)
        scheduleStatusItemTimer()
    }

    private func scheduleStatusItemTimer() {
        timer?.invalidate()
        let interval = statusBarDisplay.refreshInterval(preferences: .shared)
        let now = Date().timeIntervalSinceReferenceDate
        // 对齐整秒 / 整分；菜单展开时也继续刷新，只有含秒的格式才每秒唤醒。
        let next = (floor(now / interval) + 1) * interval
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: next), interval: interval,
                          repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem() }
        }
        timer.tolerance = interval == 1 ? 0.05 : 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 弹出窗口

    @objc private func togglePopover() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            showContextMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let contextMenu = menu.makeContextMenu()
        statusItem.menu = contextMenu
        button.performClick(nil)
        // 恢复左键弹出月历；下次右键重新构建菜单，以反映最新设置。
        statusItem.menu = nil
        button.highlight(popover.isShown)
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        model.refreshToday()
        refreshStatusItem()

        updateAppearance()
        if let screen = button.window?.screen {
            popoverSizing.setMaximumHeight(max(1, screen.visibleFrame.height - 38))
        }
        Task { await AgendaStore.shared.refresh(around: model.selectedDate) }
        popoverInteraction.prepareToShowCalendar()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        NSApp.activate(ignoringOtherApps: true)
        popoverInteraction.focusCalendarIfRequested()

        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popoverInteraction.acceptsCalendarKeyEvent(event),
                  !self.menu.isContextMenuVisible else { return event }
            if event.keyCode == 53, !self.model.isChoosingMonth {
                self.popover.performClose(nil)
                return nil
            }
            return self.handleKey(event) ? nil : event
        }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popoverInteraction.closeForExternalInteraction() }
        }
    }

    // 应用激活是异步的，弹出窗口显示时可能还没激活，这里再次让它成为键盘焦点窗口，
    // 否则方向键、回车无法控制日历
    func popoverDidShow(_ notification: Notification) {
        popoverInteraction.focusCalendarIfRequested()
        popover.contentViewController?.view.window?.backgroundColor = .clear
    }

    /// 弹出窗口默认跟随菜单栏按钮的外观，而不是 NSApp.appearance，这里显式设置
    @objc private func updateAppearance() {
        popover.appearance = NSApp.appearance ?? NSApp.effectiveAppearance
    }

    @objc private func applicationDidBecomeActive() {
        clockDidChange()
        popoverInteraction.focusCalendarIfRequested()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverInteraction.calendarDidClose()
        model.isChoosingMonth = false
        statusItem.button?.highlight(false)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Keyboard navigation is scoped to the visible calendar, excluding text editors.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard AppPreferences.shared.keyboardShortcutEnabled, !model.isChoosingMonth,
              !(popover.contentViewController?.view.window?.firstResponder is NSTextView) else { return false }
        if event.modifierFlags.contains(.command) { return false }
        let moved: Bool
        switch event.keyCode {
        case 123: moved = event.modifierFlags.contains(.option) ? model.moveMonth(by: -1) : model.moveSelection(by: -1)
        case 124: moved = event.modifierFlags.contains(.option) ? model.moveMonth(by: 1) : model.moveSelection(by: 1)
        case 126: moved = model.moveSelection(by: -7)
        case 125: moved = model.moveSelection(by: 7)
        case 36, 76: model.showToday(); moved = true
        default: return false
        }
        if !moved { NSSound.beep() }
        return true
    }

    // MARK: - 设置窗口

    @objc private func preferencesDidChange() {
        popover.animates = AppPreferences.shared.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        refreshStatusItem(force: true)
        scheduleStatusItemTimer()
    }

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(menu: menu) }
        if let settingsWindow { popoverInteraction.presentSettingsWindow(settingsWindow) }
    }

    private func showStatusBarSettings() {
        if statusBarSettingsWindow == nil {
            statusBarSettingsWindow = StatusBarSettingsWindowController(menu: menu) { [weak self] in
                self?.statusBarSettingsWindow = nil
            }
        }
        if let statusBarSettingsWindow { popoverInteraction.presentSettingsWindow(statusBarSettingsWindow) }
    }

    private func showCustomEventsWindow() {
        popover.performClose(nil)
        if customEventsWindow == nil {
            customEventsWindow = CustomEventsWindowController(store: store) { [weak self] in
                self?.customEventsWindow = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        customEventsWindow?.showWindow(nil)
        customEventsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 更新假日信息

    private func showUpdateWindow() {
        popover.performClose(nil)
        if updateWindow == nil {
            updateWindow = UpdateHolidaysWindowController(store: store) { [weak self] in
                self?.updateWindow = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        updateWindow?.showWindow(nil)
        updateWindow?.window?.makeKeyAndOrderFront(nil)
    }
}


@MainActor
private struct CalendarPopoverRoot: View {
    @ObservedObject var model: CalendarViewModel
    let menu: AppMenu
    let sizing: PopoverSizingCoordinator
    @ObservedObject private var preferences = AppPreferences.shared
    var body: some View {
        AdaptivePopoverContent(sizing: sizing, width: preferences.displayMode.popoverWidth) {
            CalendarDashboard(model: model, menu: menu)
        }
    }
}
