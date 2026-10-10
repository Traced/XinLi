import AppKit
import SwiftUI
import LunarCore

@MainActor
struct SettingsView: View {
    @ObservedObject var menu: AppMenu
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var section = "外观"
    @State private var cacheMessage = ""
    private let sections = [("外观", "paintbrush"), ("状态栏", "menubar.rectangle"), ("万年历", "moon"), ("日程", "calendar.badge.clock"), ("通用", "gearshape")]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("心历").font(.title3.weight(.semibold)).padding(.bottom, 18)
                ForEach(sections, id: \.0) { title, symbol in
                    Button { section = title } label: {
                        Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(section == title ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("心历 · \(AppMenu.version)").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width: 160).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(section).font(.title2.weight(.semibold))
                    .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
                if section == "状态栏" {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            StatusBarSettingsView(menu: menu)
                            GroupBox("更多内容") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Toggle("同时显示日历图标", isOn: $preferences.showStatusIcon)
                                    Toggle("农历日期", isOn: $preferences.showStatusLunar)
                                    Toggle("今日节气", isOn: $preferences.showStatusSolarTerm)
                                    Toggle("今天剩余日程数量", isOn: $preferences.showStatusAgendaCount)
                                    TextField("自定义格式（留空使用上方组合）", text: $preferences.customDatePattern)
                                    Text("如 M月d日 EEEE HH:mm:ss 或 MM/dd E HH:mm。中文周名统一显示为“周几”。选择纯图标时不使用文字格式。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(10)
                            }
                        }.padding(.horizontal, 24).padding(.bottom, 24)
                    }
                } else {
                    Form {
                        if section == "外观" { appearance }
                        if section == "万年历" { almanac }
                        if section == "日程" { agenda }
                        if section == "通用" { general }
                    }.formStyle(.grouped)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 760, height: 650)
            .scrollIndicators(preferences.showsScrollIndicators ? .automatic : .hidden)
    }
    private var appearance: some View {
        Group {
            Section("界面") {
                Picker("界面模式", selection: $preferences.displayMode) {
                    ForEach(CalendarDisplayMode.allCases) { Text($0.title).tag($0) }
                }
                if preferences.displayMode == .minimal {
                    Text("在同一面板查看月历与黄历，可原地展开详细黄历。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("外观", selection: $menu.appearance) { ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) } }
            }
            Section("卡片与布局") {
                Picker("卡片样式", selection: $preferences.cardStyle) {
                    ForEach(CalendarCardStyle.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("布局密度", selection: $preferences.layoutDensity) {
                    ForEach(CalendarLayoutDensity.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("显示滚动条", isOn: $preferences.showsScrollIndicators)
                Text("隐藏滚动条后仍可使用鼠标或触控板滚动；布局密度调整留白，不缩小文字。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("字体与文字大小") {
                LabeledContent("字体") {
                    InstalledFontFamilyPicker(family: $preferences.fontFamily,
                                              showsScrollIndicators: preferences.showsScrollIndicators) { family in
                        if let family {
                            preferences.previewFont(family)
                        } else {
                            preferences.clearFontPreview()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("文字大小")
                        Spacer()
                        Text("\(Int((preferences.textScale * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $preferences.textScale, in: CalendarTypography.scaleRange,
                           step: CalendarTypography.scaleStep)
                        .labelsHidden().accessibilityLabel("文字大小")
                        .accessibilityValue("\(Int((preferences.textScale * 100).rounded()))%")
                    HStack {
                        Text("30%")
                        Spacer()
                        Text("120%")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Text("心历 · 周五 10月9日 22:30")
                    .font(ResolvedCalendarTheme(preferences: preferences, colorScheme: colorScheme).font(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("字体与文字大小预览")
                HStack {
                    Text("只调整应用面板的文字；状态栏字体与字号保持系统默认。未安装字体回退系统字体。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("恢复默认") {
                        preferences.fontFamily = "system"
                        preferences.textScale = 1
                    }
                    .disabled(preferences.fontFamily == "system" && preferences.textScale == 1)
                    .accessibilityLabel("恢复默认字体与文字大小")
                }
            }
            Section("配色") {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(CalendarColorTheme.allCases.filter { $0 != .custom }) { palette in
                            paletteButton(palette)
                        }
                    }
                    Button { preferences.applyColorTheme(.custom) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("自定义配色")
                            Spacer()
                            if preferences.colorTheme == .custom {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Text("调整背景、卡片与强调色").foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .foregroundStyle(preferences.colorTheme == .custom ? Color.accentColor : Color.primary)
                        .accessibilityValue(preferences.colorTheme == .custom ? "已选中" : "未选中")
                    SettingsPalettePreview(background: backgroundColor, card: cardColor, accent: accentColor,
                                           backgroundOpacity: preferences.interfaceOpacity, cardOpacity: preferences.cardOpacity)
                }.padding(.vertical, 4)
            }
            Section("自定义颜色") {
                appearanceColorPicker("背景", hex: backgroundHex, keyPath: \.customBackgroundHex)
                appearanceColorPicker("卡片", hex: cardHex, keyPath: \.customCardHex)
                appearanceColorPicker("强调色", hex: preferences.accentHex, keyPath: \.accentHex)
                Text("修改颜色后使用自定义配色；预设会随浅色、深色外观调整。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("透明度与动画") {
                opacitySlider("背景不透明度", value: $preferences.interfaceOpacity)
                opacitySlider("卡片不透明度", value: $preferences.cardOpacity)
                if preferences.displayMode == .scenic {
                    opacitySlider("顶部遮罩不透明度", value: $preferences.headerOverlayOpacity)
                    Text("0% 去掉顶部遮罩，100% 遮罩最强；文字和按钮不随之变透明。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("切换动画", isOn: $preferences.animationsEnabled)
                Text("动画同时遵循系统“减少动态效果”设置。").font(.caption).foregroundStyle(.secondary)
            }
            Section("风景图") {
                Picker("背景图片", selection: $preferences.backgroundChoice) {
                    Text("雪山日落").tag("snow-sunset"); Text("晨雾森林").tag("forest-lake")
                    Text("Bing 每日风景").tag("bing")
                    if !preferences.customBackgroundPath.isEmpty { Text("自定义图片").tag("custom") }
                }
                Picker("显示范围", selection: $preferences.backgroundImageScope) {
                    ForEach(BackgroundImageScope.allCases) { Text($0.title).tag($0) }
                }
                if preferences.backgroundImageScope != .header {
                    opacitySlider("图片浓度", value: $preferences.backgroundImageOpacity)
                }
                if let image = theme.backgroundImage {
                    GeometryReader { proxy in
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: 100).clipped()
                    }.frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("当前风景图片预览")
                }
                HStack(spacing: 10) {
                    Button("换一张 Bing 风景") {
                        Task { await theme.refreshBingBackground() }
                    }.disabled(theme.isRefreshingBackground)
                    if theme.isRefreshingBackground {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("正在下载 Bing 风景")
                    }
                    Spacer(minLength: 0)
                    Button("选择本地图片…") { theme.selectCustomImage() }
                }
                Text(backgroundScopeDescription).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = theme.backgroundError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if preferences.backgroundChoice == "bing" {
                    bingAttribution
                }
            }
        }
    }

    private var backgroundScopeDescription: String {
        switch preferences.backgroundImageScope {
        case .header:
            "仅用于风景模式顶部横幅；迷你与极简模式不显示顶部横幅。"
        case .content:
            "图片用于内容区域；迷你与极简模式同样适用。"
        case .window:
            "图片铺满整个浮窗；迷你与极简模式同样适用。"
        }
    }

    private var bingAttribution: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let url = theme.bingCopyrightURL {
                Link("图片来源：Bing", destination: url)
                    .help("查看 Bing 图片介绍及版权来源")
            }
            if let copyright = theme.bingCopyright, !copyright.isEmpty {
                Text(copyright).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption)
    }

    private var backgroundHex: String {
        if preferences.colorTheme == .custom { return preferences.customBackgroundHex }
        return colorScheme == .dark ? preferences.colorTheme.darkBackgroundHex : preferences.colorTheme.lightBackgroundHex
    }
    private var cardHex: String {
        if preferences.colorTheme == .custom { return preferences.customCardHex }
        return colorScheme == .dark ? preferences.colorTheme.darkCardHex : preferences.colorTheme.lightCardHex
    }
    private var backgroundColor: Color { SettingsColor.color(hex: backgroundHex) }
    private var cardColor: Color { SettingsColor.color(hex: cardHex) }
    private var accentColor: Color { SettingsColor.color(hex: preferences.accentHex) }

    private func paletteButton(_ palette: CalendarColorTheme) -> some View {
        let selected = preferences.colorTheme == palette
        let background = SettingsColor.color(hex: colorScheme == .dark ? palette.darkBackgroundHex : palette.lightBackgroundHex)
        let card = SettingsColor.color(hex: colorScheme == .dark ? palette.darkCardHex : palette.lightCardHex)
        let accent = SettingsColor.color(hex: palette.accentHex)
        return Button { preferences.applyColorTheme(palette) } label: {
            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 4).fill(card).frame(height: 20)
                        .overlay(alignment: .leading) {
                            Capsule().fill(accent.opacity(0.45)).frame(width: 20, height: 3).padding(.leading, 6)
                        }
                    Circle().fill(accent).frame(width: 16, height: 16)
                }.padding(7).background(background, in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 4) {
                    Text(palette.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color.accentColor) }
                }.frame(height: 16)
            }.padding(6).frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityLabel(palette.title + "配色")
            .accessibilityValue(selected ? "已选中" : "未选中")
            .help("应用" + palette.title + "配色")
    }

    private func appearanceColorPicker(_ title: String, hex: String, keyPath: ReferenceWritableKeyPath<AppPreferences, String>) -> some View {
        ColorPicker(selection: Binding(
            get: { SettingsColor.color(hex: hex) },
            set: { color in
                guard let value = SettingsColor.hex(color) else { return }
                // Keep the other two displayed colors when editing a preset.
                let previousBackground = backgroundHex
                let previousCard = cardHex
                if preferences.colorTheme != .custom {
                    preferences.customBackgroundHex = previousBackground
                    preferences.customCardHex = previousCard
                    preferences.colorTheme = .custom
                }
                preferences[keyPath: keyPath] = value
            }
        ), supportsOpacity: false) {
            HStack {
                Text(title)
                Spacer()
                Text(hex).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.help("选择" + title + "颜色")
    }

    private func opacitySlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1).labelsHidden().accessibilityLabel(title)
        }.padding(.vertical, 3)
    }
    private var almanac: some View {
        Group {
            Section("月历信息") {
                Toggle("农历", isOn: $preferences.showLunar)
                Toggle("二十四节气", isOn: $preferences.showSolarTerms)
                Toggle("法定假期与调休", isOn: $preferences.showHolidays)
                Toggle("节日与自定义纪念日", isOn: $preferences.showFestivals)
                Toggle("干支与生肖", isOn: $preferences.showGanZhi)
                Picker("每周首日", selection: $preferences.firstWeekday) { Text("周一").tag(2); Text("周日").tag(1) }
                LabeledContent("应用时区", value: preferences.timeZone.identifier)
                Text("“今天”、交节时刻与日期显示统一使用应用时区，可在通用或状态栏设置中更改。农历换算遵循中国历法。支持 1901–2099 年，精确节气时刻已核验 2025–2027 年。").font(.caption).foregroundStyle(.secondary)
            }
            Section("黄历数据") {
                Toggle("显示黄历宜忌与时辰", isOn: $preferences.showAlmanac)
                Text("显示宜忌、冲煞、彭祖百忌与时辰吉凶。传统时辰按中国历法计算，显示时间换算至应用时区；传统历书信息仅供民俗参考。").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Link(LunarGoAlmanacProvider.source.title, destination: LunarGoAlmanacProvider.source.sourceURL)
                    Link("MIT 许可", destination: LunarGoAlmanacProvider.source.licenseURL)
                }.font(.caption)
            }
        }
    }
    private var agenda: some View {
        Group {
            Section("显示与默认值") {
                LabeledContent("应用时区", value: preferences.timeZone.identifier)
                Picker("提前提醒", selection: $preferences.defaultReminderMinutes) {
                    Text("不提醒").tag(-1); Text("事件开始时").tag(0); Text("5 分钟").tag(5); Text("15 分钟").tag(15); Text("30 分钟").tag(30); Text("1 小时").tag(60); Text("1 天").tag(1440)
                }
                Picker("未来日程范围", selection: $preferences.agendaRangeDays) { Text("明天").tag(1); Text("未来 7 天").tag(7); Text("未来 30 天").tag(30) }
                Picker("本地日程默认颜色", selection: $preferences.eventColorHex) {
                    Text("蓝色").tag("#3B82F6"); Text("绿色").tag("#22A06B"); Text("橙色").tag("#F59E0B"); Text("紫色").tag("#8B5CF6"); Text("红色").tag("#EF4444")
                }
                Toggle("显示已完成任务", isOn: $preferences.showCompletedTasks)
            }
            AgendaSettingsSection(store: AgendaStore.shared)
        }
    }
    private var general: some View {
        Group {
            Section("通用") {
                TimeZonePicker(title: "应用时区", identifier: $preferences.timeZoneIdentifier)
                Text("状态栏、日历、日程、任务及日期选择统一使用此时区。已有日程的实际时刻与原有重复规则保持不变。").font(.caption).foregroundStyle(.secondary)
                Toggle("登录时自动启动", isOn: Binding(get: { menu.launchAtLogin }, set: { menu.setLaunchAtLogin($0) }))
                Toggle("24 小时制", isOn: $preferences.use24HourTime)
                Toggle("日历键盘导航", isOn: $preferences.keyboardShortcutEnabled)
                Text("方向键选择日期；Option + 左右键切换月份；回车回到今天；⌘N 新建日程。仅在日历浮窗中生效。").font(.caption).foregroundStyle(.secondary)
                LabeledContent("语言", value: "简体中文")
            }
            Section("维护与关于") {
                Button("重新加载风景缓存") { ThemeManager.shared.clearCache(); cacheMessage = "已重新加载风景图片。" }
                if !cacheMessage.isEmpty { Text(cacheMessage).font(.caption).foregroundStyle(.secondary) }
                Text("心历 \(AppMenu.version)")
                Button("公众号：\(AppMenu.publicAccountName)") { AppMenu.copyPublicAccountName() }
                    .help("点击复制公众号名称：\(AppMenu.publicAccountName)")
                    .accessibilityLabel("复制公众号名称：\(AppMenu.publicAccountName)")
                Text("日历和本地日程离线可用。系统日历权限可随时在 macOS 系统设置中管理。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A small surface sample, deliberately separate from real dates and events.
@MainActor
private struct SettingsPalettePreview: View {
    let background: Color
    let card: Color
    let accent: Color
    let backgroundOpacity: Double
    let cardOpacity: Double

    private var selectionColors: (background: ThemeRGB, foreground: ThemeRGB) {
        ThemeRGB(hex: SettingsColor.hex(accent) ?? "#3478F6").selectionColors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("配色预览").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("日历内容").font(.system(size: 12, weight: .medium))
                    HStack(spacing: 5) {
                        Capsule().fill(accent).frame(width: 24, height: 4)
                        Capsule().fill(previewForeground.opacity(0.25)).frame(width: 44, height: 4)
                    }
                }
                Spacer()
                Text("选中").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectionColors.foreground.color)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(selectionColors.background.color, in: RoundedRectangle(cornerRadius: 6))
            }.foregroundStyle(previewForeground)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(card.opacity(cardOpacity), in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
                .background(background.opacity(backgroundOpacity))
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("配色预览，显示背景、卡片与强调色")
        }
    }

    private var previewForeground: Color {
        SettingsColor.contrastingText(on: card, opacity: cardOpacity,
                                      behind: background, backgroundOpacity: backgroundOpacity)
    }
}

@MainActor
private enum SettingsColor {
    static func color(hex: String) -> Color {
        let normalized = CalendarColorTheme.normalizedHex(hex, fallback: "#3478F6")
        let value = UInt32(normalized.dropFirst(), radix: 16) ?? 0x3478F6
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }

    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        let bytes = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

    static func contrastingText(on color: Color, opacity: Double = 1,
                                behind background: Color = .white, backgroundOpacity: Double = 1) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB),
              let behind = NSColor(background).usingColorSpace(.sRGB),
              let base = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) else { return .primary }
        func composite(_ foreground: CGFloat, _ background: CGFloat, _ surface: CGFloat) -> Double {
            let underneath = Double(background) * backgroundOpacity + Double(surface) * (1 - backgroundOpacity)
            return Double(foreground) * opacity + underneath * (1 - opacity)
        }
        let channels = [composite(rgb.redComponent, behind.redComponent, base.redComponent),
                        composite(rgb.greenComponent, behind.greenComponent, base.greenComponent),
                        composite(rgb.blueComponent, behind.blueComponent, base.blueComponent)]
            .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        return luminance > 0.179 ? .black.opacity(0.88) : .white.opacity(0.94)
    }
}

struct TimeZonePicker: View {
    let title: String
    @Binding var identifier: String
    var allowsSystem = true
    var body: some View {
        Picker(title, selection: $identifier) {
            if allowsSystem { Text("跟随系统").tag("") }
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(menu: AppMenu) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(menu: menu)))
        window.title = "心历设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 650)); window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
