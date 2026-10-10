import AppKit
import SwiftUI

struct StatusBarSettingsView: View {
    @ObservedObject var menu: AppMenu

    private static let commonZones: [(id: String, title: String)] = [
        ("Asia/Shanghai", "北京 / 上海"), ("Asia/Hong_Kong", "香港"),
        ("Asia/Taipei", "台北"), ("Asia/Tokyo", "东京"),
        ("Asia/Singapore", "新加坡"), ("Europe/London", "伦敦"),
        ("Europe/Paris", "巴黎"), ("America/New_York", "纽约"),
        ("America/Los_Angeles", "洛杉矶"), ("America/Sao_Paulo", "圣保罗"),
        ("Australia/Sydney", "悉尼"), ("Pacific/Auckland", "奥克兰"),
        ("Etc/UTC", "协调世界时 UTC"),
    ]
    private static let zoneGroups: [(title: String, identifiers: [String])] = {
        let regions = [("Asia", "亚洲"), ("Europe", "欧洲"), ("America", "美洲"),
                       ("Africa", "非洲"), ("Australia", "澳大利亚"), ("Pacific", "太平洋"),
                       ("Atlantic", "大西洋"), ("Indian", "印度洋"), ("Antarctica", "南极洲")]
        return regions.map { prefix, title in
            (title, TimeZone.knownTimeZoneIdentifiers.filter { $0.hasPrefix(prefix + "/") }.sorted())
        }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("实时预览").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondaryText)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Spacer(minLength: 0)
                        if menu.statusBarDisplay.format == .icon {
                            Image(nsImage: MenuBarIcon.image(day: menu.statusBarDisplay.calendarDate(at: context.date).day))
                        } else {
                            Text(menu.statusBarDisplay.renderedTitle(at: context.date, remainingEvents: AgendaStore.shared.remainingCount(at: context.date)))
                                .font(.system(size: 15, weight: .medium).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 58)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            row("显示格式") {
                Picker("显示格式", selection: $menu.statusBarDisplay.format) {
                    ForEach(StatusBarFormat.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("自定义组合").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondaryText)
                VStack(spacing: 14) {
                    row("日期") {
                        Picker("日期", selection: customBinding(\.customDate)) {
                            ForEach(StatusBarDateStyle.allCases) { style in
                                Text(style.title).tag(style)
                                    .disabled(style == .none && !menu.statusBarDisplay.customWeekday
                                              && menu.statusBarDisplay.customTime == .none)
                            }
                        }.labelsHidden()
                    }
                    row("时间") {
                        Picker("时间", selection: customBinding(\.customTime)) {
                            ForEach(StatusBarTimeStyle.allCases) { style in
                                Text(style.title).tag(style)
                                    .disabled(style == .none && !menu.statusBarDisplay.customWeekday
                                              && menu.statusBarDisplay.customDate == .none)
                            }
                        }.labelsHidden()
                    }
                    row("周几") {
                        Toggle("显示周几", isOn: customBinding(\.customWeekday))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(menu.statusBarDisplay.customDate == .none
                                      && menu.statusBarDisplay.customTime == .none)
                    }
                }
                .padding(16)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 10) {
                row("应用时区") { timeZoneMenu }
                Text("统一用于状态栏、月历、日程、任务和日期选择。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
            }
            Text("更改即时生效，自动保存。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(width: 460)
        .background(Palette.background)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Text(title).frame(width: 60, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var timeZoneMenu: some View {
        Menu {
            zoneButton("跟随系统", identifier: nil)
            Divider()
            ForEach(Self.commonZones, id: \.id) { zone in
                zoneButton(zone.title, identifier: zone.id)
            }
            Divider()
            Menu("更多时区") {
                ForEach(Self.zoneGroups, id: \.title) { group in
                    Menu(group.title) {
                        ForEach(group.identifiers, id: \.self) { identifier in
                            zoneButton(identifier, identifier: identifier)
                        }
                    }
                }
            }
        } label: {
            Text(selectedTimeZoneTitle).lineLimit(1)
        }
        .accessibilityLabel("应用时区")
    }

    private var selectedTimeZoneTitle: String {
        guard let identifier = menu.statusBarDisplay.timeZoneIdentifier else { return "跟随系统" }
        return Self.commonZones.first { $0.id == identifier }?.title ?? identifier
    }

    private func zoneButton(_ title: String, identifier: String?) -> some View {
        Button {
            menu.statusBarDisplay.timeZoneIdentifier = identifier
        } label: {
            if menu.statusBarDisplay.timeZoneIdentifier == identifier {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func customBinding<Value>(_ keyPath: WritableKeyPath<StatusBarDisplay, Value>) -> Binding<Value> {
        Binding(get: { menu.statusBarDisplay[keyPath: keyPath] }, set: { value in
            var display = menu.statusBarDisplay
            display[keyPath: keyPath] = value
            display.format = .custom
            guard !display.customIsEmpty else { return }
            menu.statusBarDisplay = display
        })
    }
}

@MainActor
final class StatusBarSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(menu: AppMenu, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let hosting = NSHostingController(rootView: StatusBarSettingsView(menu: menu))
        let window = NSWindow(contentViewController: hosting)
        window.title = "状态栏显示"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [onClose] in onClose() }
    }
}
