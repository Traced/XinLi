import AppKit
import Combine
import LunarCore
import ServiceManagement
import SwiftUI

/// 外观：跟随系统 / 日间模式 / 夜间模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "日间模式"
        case .dark: return "夜间模式"
        }
    }

    private static let key = "appearance"
    static let didChange = Notification.Name("XinLiAppearanceDidChange")

    static var saved: AppearanceMode {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceMode.init) ?? .system
    }

    @MainActor
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// 状态栏右键与日历齿轮共用的设置菜单。
@MainActor
final class AppMenu: NSObject, ObservableObject, NSMenuDelegate {
    static let publicAccountName = "随心记事"

    /// 选择"更新假日信息"时调用
    var onUpdateHolidays: () -> Void = {}
    /// 选择"自定义日期"时调用
    var onEditCustomEvents: () -> Void = {}
    var onEditStatusBar: () -> Void = {}
    var onSettings: () -> Void = {}
    var onNewEvent: () -> Void = {}
    private(set) var isContextMenuVisible = false

    @Published private(set) var launchAtLogin = AppMenu.isLoginItemEnabled
    @Published var appearance = AppearanceMode.saved {
        didSet { appearance.apply() }
    }
    private let displayDefaults: UserDefaults
    private var displayObserver: AnyCancellable?
    private var applyingExternalDisplay = false
    @Published var statusBarDisplay: StatusBarDisplay {
        didSet {
            guard statusBarDisplay != oldValue, !applyingExternalDisplay else { return }
            statusBarDisplay.save(to: displayDefaults)
        }
    }

    init(defaults: UserDefaults = .standard) {
        displayDefaults = defaults
        statusBarDisplay = StatusBarDisplay.load(from: defaults)
        super.init()
        displayObserver = NotificationCenter.default.publisher(for: StatusBarDisplay.didChange).sink { [weak self] _ in
            guard let self else { return }
            let latest = StatusBarDisplay.load(from: self.displayDefaults)
            guard latest != self.statusBarDisplay else { return }
            self.applyingExternalDisplay = true
            self.statusBarDisplay = latest
            self.applyingExternalDisplay = false
        }
    }

    /// 已注册为登录项（包括等待用户在系统设置中批准的情况）
    private static var isLoginItemEnabled: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    static var version: String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return "dev" }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.lowercased() != "dev" else { return "dev" }
        let number = value.hasPrefix("v") ? String(value.dropFirst()) : value
        var components = number.split(separator: ".", omittingEmptySubsequences: false)
        while components.count > 1, components.last == "0" { components.removeLast() }
        return "v" + components.joined(separator: ".")
    }

    func refresh() {
        launchAtLogin = Self.isLoginItemEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            if SMAppService.mainApp.status == .requiresApproval {
                // 需要用户在"系统设置 > 通用 > 登录项"中允许
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = enabled ? "无法设置自动启动" : "无法取消自动启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    var button: some View {
        AppMenuButton(menu: self)
            .frame(width: 28, height: 28)
    }

    /// 每次打开时重新构造菜单，让勾选状态与当前设置保持一致。
    func makeContextMenu() -> NSMenu {
        refresh()
        let menu = Self.nativeMenu()
        menu.delegate = self
        menu.addItem(ActionMenuItem("新建日程…", keyEquivalent: "n") { [weak self] in self?.onNewEvent() })
        let modes = Self.nativeMenu()
        for mode in CalendarDisplayMode.allCases {
            modes.addItem(ActionMenuItem(mode.title, checked: AppPreferences.shared.displayMode == mode) { AppPreferences.shared.displayMode = mode })
        }
        menu.addItem(Self.submenuItem("显示模式", menu: modes))
        menu.addItem(ActionMenuItem("设置…", keyEquivalent: ",") { [weak self] in self?.onSettings() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("自动启动", checked: launchAtLogin) { [weak self] in
            guard let self else { return }
            self.setLaunchAtLogin(!self.launchAtLogin)
        })

        let appearanceMenu = Self.nativeMenu()
        for mode in AppearanceMode.allCases {
            appearanceMenu.addItem(ActionMenuItem(mode.title, checked: appearance == mode) { [weak self] in
                self?.appearance = mode
            })
        }
        menu.addItem(Self.submenuItem("外观", menu: appearanceMenu))
        menu.addItem(ActionMenuItem("状态栏显示…") { [weak self] in self?.onEditStatusBar() })

        let store = DataStore.shared
        let festivalMenu = Self.nativeMenu()
        for category in FestivalCategory.allCases {
            festivalMenu.addItem(ActionMenuItem(category.title, checked: !store.hiddenCategories.contains(category)) {
                store.setCategory(category, visible: store.hiddenCategories.contains(category))
            })
        }
        menu.addItem(Self.submenuItem("显示节日", menu: festivalMenu))
        menu.addItem(ActionMenuItem("自定义日期…") { [weak self] in self?.onEditCustomEvents() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("使用帮助") { Self.showHelp() })
        menu.addItem(ActionMenuItem("更新假日信息…") { [weak self] in self?.onUpdateHolidays() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("版本: \(Self.version)") { Self.showAbout() })
        let account = ActionMenuItem("公众号：\(Self.publicAccountName)") { Self.copyPublicAccountName() }
        account.toolTip = "点击复制公众号名称：\(Self.publicAccountName)"
        menu.addItem(account)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("退出", keyEquivalent: "q") { NSApp.terminate(nil) })
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        isContextMenuVisible = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isContextMenuVisible = false
    }

    static func copyPublicAccountName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(publicAccountName, forType: .string)
    }

    private static func showHelp() {
        let alert = NSAlert()
        alert.messageText = "心历使用帮助"
        alert.informativeText = """
        点击状态栏打开或收起日历，右键状态栏可切换显示模式、打开设置。

        风景主题：显示风景横幅，以及日历、万年历、日程三个标签页。
        迷你简约：以紧凑布局保留完整的日历、万年历与日程功能。
        极简：在同一面板查看月历与黄历，点击“完整黄历”原地展开详情。

        左右滑动切换月份，点击年月标题快速选择年份和月份。外观设置可调整字体、文字大小、卡片样式、布局密度与背景。

        通用或状态栏设置中的应用时区会同步用于整个应用的日期和时间显示；修改显示时区不会移动已有日程的实际时刻。
        """
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func showAbout() {
        let alert = NSAlert()
        alert.messageText = "心历"
        alert.informativeText = "版本：\(version)\n公众号：\(publicAccountName)\n\n日历和本地日程离线可用。"
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "复制公众号名称")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { copyPublicAccountName() }
    }

    private static func nativeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    private static func submenuItem(_ title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// NSMenu 持有菜单项，菜单项自身持有动作；不依赖短命的外部 target。
@MainActor
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, keyEquivalent: String = "", action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(performAction(_:)), keyEquivalent: keyEquivalent)
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("ActionMenuItem is created programmatically")
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        handler()
    }
}

private struct AppMenuButton: NSViewRepresentable {
    @ObservedObject var menu: AppMenu

    func makeCoordinator() -> Coordinator { Coordinator(menu: menu) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.setButtonType(.momentaryChange)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.sendAction(on: .leftMouseDown)
        button.toolTip = "设置"
        button.setAccessibilityLabel("设置")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.menu = menu
    }

    @MainActor
    final class Coordinator: NSObject {
        var menu: AppMenu

        init(menu: AppMenu) { self.menu = menu }

        @objc func showMenu(_ button: NSButton) {
            menu.makeContextMenu().popUp(positioning: nil,
                                         at: NSPoint(x: 0, y: button.bounds.maxY + 4),
                                         in: button)
        }
    }
}
