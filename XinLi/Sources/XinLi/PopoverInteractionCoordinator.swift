import AppKit

/// Owns dismissal and focus so the calendar can remain beside its settings.
@MainActor
final class PopoverInteractionCoordinator: NSObject {
    private weak var popover: NSPopover?
    private var wantsCalendarFocus = false
    private let notificationCenter: NotificationCenter

    init(popover: NSPopover, notificationCenter: NotificationCenter = .default) {
        self.popover = popover
        self.notificationCenter = notificationCenter
        super.init()
        popover.behavior = .applicationDefined
        notificationCenter.addObserver(self, selector: #selector(applicationDidResignActive),
                                       name: NSApplication.didResignActiveNotification, object: nil)
    }

    func prepareToShowCalendar() {
        wantsCalendarFocus = true
    }

    func focusCalendarIfRequested() {
        guard wantsCalendarFocus, let popover, popover.isShown else { return }
        popover.contentViewController?.view.window?.makeKey()
    }

    func presentSettingsWindow(_ controller: NSWindowController) {
        // Activation and popoverDidShow can arrive after the settings action.
        // Neither callback should steal focus back from a settings text field.
        wantsCalendarFocus = false
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func calendarDidClose() {
        wantsCalendarFocus = false
    }

    func acceptsCalendarKeyEvent(_ event: NSEvent) -> Bool {
        guard let popover, popover.isShown,
              let window = popover.contentViewController?.view.window else { return false }
        return event.window === window && window.isKeyWindow
    }

    func closeForExternalInteraction() {
        wantsCalendarFocus = false
        // close also dismisses a nested date picker when changing applications.
        popover?.close()
    }

    @objc private func applicationDidResignActive() {
        closeForExternalInteraction()
    }
}
