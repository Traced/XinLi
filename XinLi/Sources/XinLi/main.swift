import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.saved.apply()
        // 移动到"应用程序"文件夹后会退出并重新启动，不再创建菜单栏图标
        if MoveToApplications.promptIfNecessary() { return }
        statusItemController = StatusItemController()
        DataStore.shared.startAutomaticHolidayUpdates()
        if let warning = DataStore.shared.loadWarning {
            let alert = NSAlert()
            alert.messageText = "心历"
            alert.informativeText = warning
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    // 只在菜单栏显示，不出现在 Dock 中
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
