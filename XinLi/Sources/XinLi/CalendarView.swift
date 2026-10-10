import AppKit
import LunarCore
import SwiftUI

/// 中性色在浅色和深色模式下保持一致的层次；强调色由主题设置提供。
enum Palette {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }

    static let red = dynamic(light: 0xB9534D, dark: 0xDC8981)
    static let blue = dynamic(light: 0x536F8A, dark: 0x8BB0CB)
    static let accent = Color.accentColor
    static let background = dynamic(light: 0xFCFCFD, dark: 0x1E1E22)
    static let nsBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x22 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xFC / 255.0, green: 0xFC / 255.0, blue: 0xFD / 255.0, alpha: 1)
    }
    static let secondaryText = dynamic(light: 0x6D6D74, dark: 0xA3A3AA)
    static let panel = dynamic(light: 0xF2F3F5, dark: 0x29292E)
    static let hovered = dynamic(light: 0xEBEDF1, dark: 0x33333A)
    static let selected = Color.accentColor.opacity(0.09)
}

/// 可复用的月历网格。外层 Dashboard 决定横幅、面板与整体宽度。
@MainActor
struct CalendarView: View {
    @ObservedObject var model: CalendarViewModel
    let menu: AppMenu
    var cellSize = CGSize(width: 50, height: 54)

    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var agenda: AgendaStore
    @State private var hovered: SolarDate?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chronoTheme) private var theme

    init(model: CalendarViewModel, menu: AppMenu, cellSize: CGSize = CGSize(width: 50, height: 54),
         agendaStore: AgendaStore = .shared) {
        self.model = model
        self.menu = menu
        self.cellSize = cellSize
        self.agenda = agendaStore
        self.preferences = agendaStore.preferences
    }

    private var compact: Bool { preferences.displayMode.isCompactLayout }
    private var accent: Color { ChronoThemeColor.color(hex: preferences.accentHex) }
    private var weekdays: [Int] {
        let start = min(max(preferences.firstWeekday, 1), 7) - 1
        return (0..<7).map { (start + $0) % 7 }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
                .padding(.bottom, preferences.layoutDensity.spacing(compact ? 10 : 14))
            if model.isChoosingMonth {
                MonthYearPicker(year: model.year, month: model.month, today: model.today, compact: compact,
                                accent: accent, animationsEnabled: preferences.animationsEnabled) { year, month in
                    guard model.isChoosingMonth else { return }
                    if model.setMonth(year: year, month: month) { model.isChoosingMonth = false }
                } onCancel: {
                    model.isChoosingMonth = false
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    weekdayBar
                    CalendarMonthPager(model: model, size: CGSize(width: cellSize.width * 7, height: cellSize.height * 6),
                                       animationsEnabled: preferences.animationsEnabled) { month in
                        grid(for: month)
                    }
                }
                .modifier(CalendarMonthSwipeModifier { delta in
                    guard !model.isChoosingMonth else { return }
                    hovered = nil
                    model.moveMonth(by: delta)
                })
                .transition(.opacity)
            }
        }
        .frame(width: cellSize.width * 7)
        .animation(preferences.animationsEnabled && !reduceMotion ? .easeInOut(duration: 0.12) : nil, value: model.isChoosingMonth)
        .onChange(of: model.month) { _, _ in hovered = nil }
        .onChange(of: model.isChoosingMonth) { _, _ in hovered = nil }
        .onDisappear { hovered = nil; model.isChoosingMonth = false }
        .task(id: model.year * 12 + model.month) {
            await agenda.refresh(around: SolarDate(year: model.year, month: model.month, day: 15))
        }
    }

    private var titleBar: some View {
        HStack(spacing: compact ? 2 : 4) {
            Button {
                model.isChoosingMonth.toggle()
            } label: {
                Text("\(String(model.year))年\(model.month)月")
                    .font(theme.font(size: compact ? 21 : 24, weight: .semibold))
                    .foregroundStyle(theme.accentText)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(model.isChoosingMonth ? "收起年月选择" : "选择年份和月份")
            .accessibilityLabel(model.isChoosingMonth ? "收起年月选择" : "选择年份和月份")
            .accessibilityValue("\(String(model.year))年\(model.month)月")

            Spacer(minLength: 4)
            if model.isChoosingMonth {
                Button("取消") { model.isChoosingMonth = false }
                    .font(theme.font(size: 12, weight: .medium))
                    .buttonStyle(CalendarControlStyle())
                    .keyboardShortcut(.cancelAction)
                    .help("取消年月选择 (Esc)")
            } else {
                Button("今天") { model.showToday() }
                    .font(theme.font(size: 12, weight: .medium))
                    .buttonStyle(CalendarControlStyle())
                    .help("回到今天")
                monthButton("上一月", icon: "chevron.left") { model.moveMonth(by: -1) }
                    .disabled(!model.canMoveBackward)
                monthButton("下一月", icon: "chevron.right") { model.moveMonth(by: 1) }
                    .disabled(!model.canMoveForward)
            }
        }
        .frame(height: 32 * max(1, theme.textScale))
    }

    private var weekdayBar: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(String(Array("日一二三四五六")[weekday]))
                    .font(theme.font(size: 12, weight: .medium))
                    .foregroundStyle(weekday == 0 || weekday == 6 ? theme.danger : theme.secondary)
                    .frame(width: cellSize.width, height: 24 * max(1, theme.textScale))
            }
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private func grid(for month: MonthGrid) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        cell(day: month.days[row * 7 + column], month: month)
                    }
                }
            }
        }
    }

    private func cell(day: CalendarDay, month: MonthGrid) -> some View {
        let inMonth = month.isInMonth(day)
        let isToday = inMonth && day.date == model.today
        let isSelected = inMonth && day.date == model.selectedDate
        let label = secondaryLabel(for: day)
        let colors = agenda.eventColors(on: day.date)
        let fill = isSelected ? theme.selectionBackground : hovered == day.date ? theme.primary.opacity(0.06) : .clear
        let restDay = preferences.showHolidays ? day.isRestDay : day.isWeekend

        return VStack(spacing: compact ? 1 : 2) {
            HStack(alignment: .top, spacing: 2) {
                Text("\(day.date.day)")
                    .font(theme.font(size: compact ? 21 : 23, weight: isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? theme.selectionForeground : restDay ? theme.danger : theme.primary)
                if preferences.showHolidays, inMonth, let holiday = day.holiday {
                    Text(holiday.isOffDay ? "休" : "班")
                        .font(theme.font(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.selectionForeground : holiday.isOffDay ? theme.danger : theme.secondary)
                        .frame(width: 14 * theme.textScale, height: 15 * theme.textScale)
                        .background(isSelected ? .clear : (holiday.isOffDay ? theme.danger : theme.secondary).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 2))
                        .padding(.top, 2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Text(label.text.isEmpty ? " " : label.text)
                .font(theme.font(size: compact ? 11 : 12))
                .foregroundStyle(isSelected ? theme.selectionForeground : label.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 2)
            HStack(spacing: 3) {
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(ChronoThemeColor.color(hex: color))
                        .overlay(Circle().strokeBorder(isSelected ? theme.selectionForeground.opacity(0.8) : .clear, lineWidth: 0.7))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(width: cellSize.width - 6, height: cellSize.height - 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isToday && !isSelected ? theme.secondary.opacity(0.55) : .clear, lineWidth: 1))
        .frame(width: cellSize.width, height: cellSize.height)
        .opacity(inMonth ? 1 : 0.3)
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? day.date : (hovered == day.date ? nil : hovered) }
        .onTapGesture {
            hovered = nil
            model.select(day)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.solarText)，\(day.weekdayName)，\(label.text)")
        .accessibilityValue([isToday ? "今天" : "", isSelected ? "已选中" : "", colors.isEmpty ? "" : "有日程"]
            .filter { !$0.isEmpty }.joined(separator: "，"))
        .accessibilityAddTraits(.isButton)
        .help(day.solarText + " " + label.text)
    }

    private func secondaryLabel(for day: CalendarDay) -> (text: String, color: Color) {
        if preferences.showFestivals, let event = day.events.first {
            return (event.name, event.highlight ? theme.danger : theme.secondary)
        }
        if preferences.showSolarTerms {
            let term = SolarTermEngine.displayName(on: day.date, timeZone: preferences.timeZone)
            if !term.isEmpty { return (term, theme.accentText) }
        }
        if preferences.showLunar {
            return (day.lunar.day == 1 ? day.lunarMonthName + "月" : day.lunarDayName, theme.secondary)
        }
        return ("", theme.secondary)
    }

    private func monthButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(theme.font(size: 12, weight: .medium))
                .frame(width: 14, height: 18)
        }
        .buttonStyle(CalendarControlStyle())
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct CalendarControlStyle: ButtonStyle {
    @Environment(\.chronoTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? theme.primary : theme.secondary.opacity(0.4))
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isEnabled && (hovered || configuration.isPressed) ? theme.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .onHover { hovered = $0 }
    }
}

/// 日历页的选中日期摘要；更完整的历法内容位于「万年历」页。
@MainActor
struct DetailPanel: View {
    @Environment(\.chronoTheme) private var theme
    let day: CalendarDay
    let onShowAlmanac: (() -> Void)?
    let isAlmanacExpanded: Bool
    @ObservedObject private var preferences: AppPreferences

    init(day: CalendarDay, preferences: AppPreferences = .shared, isAlmanacExpanded: Bool = false,
         onShowAlmanac: (() -> Void)? = nil) {
        self.day = day
        self.preferences = preferences
        self.onShowAlmanac = onShowAlmanac
        self.isAlmanacExpanded = isAlmanacExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(6)) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    summaryDate.fixedSize()
                    Spacer(minLength: 0)
                    summaryLunar.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    summaryDate
                    summaryLunar
                }
            }
            if preferences.showGanZhi {
                Text("\(day.ganZhiYearByLiChun)年 · \(day.ganZhiMonth)月 · \(day.ganZhiDay)日 · 属\(day.shengXiao)")
                    .font(theme.font(size: 12))
                    .foregroundStyle(theme.secondary)
            }
            if preferences.showAlmanac {
                Divider().opacity(0.55).padding(.vertical, 3)
                AlmanacRecordContent(date: day.date) { almanac in
                    almanacSummary(almanac)
                }
                HStack {
                    Text("民俗参考")
                        .font(theme.font(size: 12))
                        .foregroundStyle(theme.secondary)
                    Spacer(minLength: 8)
                    if let onShowAlmanac {
                        Button(action: onShowAlmanac) {
                            HStack(spacing: 4) {
                                Text(isAlmanacExpanded ? "收起详细黄历" : "完整黄历")
                                Image(systemName: isAlmanacExpanded ? "chevron.up" : preferences.displayMode == .minimal ? "chevron.down" : "chevron.right")
                                    .font(theme.font(size: 10, weight: .medium))
                            }
                            .font(theme.font(size: 12, weight: .medium))
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accentText)
                        .help(preferences.displayMode == .minimal
                              ? (isAlmanacExpanded ? "收起当前面板中的详细黄历" : "在当前面板展开完整宜忌、冲煞与时辰")
                              : "在万年历中查看所选日期的完整宜忌、冲煞与时辰")
                        .accessibilityLabel(isAlmanacExpanded ? "收起详细黄历" : "查看\(day.solarText)的完整黄历")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.layoutDensity.spacing(12))
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("选中日期摘要")
    }

    private var summaryDate: some View {
        Text("\(day.solarText)  \(day.weekdayName)")
            .font(theme.font(size: 13, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var summaryLunar: some View {
        if preferences.showLunar {
            Text("农历\(day.lunarMonthName)月\(day.lunarDayName)")
                .font(theme.font(size: 12))
                .foregroundStyle(theme.secondary)
        }
    }

    @ViewBuilder
    private func almanacSummary(_ almanac: AlmanacAvailability) -> some View {
        switch almanac {
        case .available(let record):
            VStack(alignment: .leading, spacing: 6) {
                activitySummary("宜", values: record.suitableActivities, color: theme.positive)
                activitySummary("忌", values: record.unsuitableActivities, color: theme.danger)
            }
        case .unavailable(let reason):
            Label("黄历数据暂不可用", systemImage: "info.circle")
                .font(theme.font(size: 12))
                .foregroundStyle(theme.secondary)
                .help(reason)
                .accessibilityLabel("黄历数据暂不可用，\(reason)")
        }
    }

    private func activitySummary(_ title: String, values: [String], color: Color) -> some View {
        let limit = preferences.displayMode.isCompactLayout ? 3 : 4
        let complete = values.isEmpty ? "未记载" : values.joined(separator: "、")
        let summary = values.isEmpty ? "未记载" : values.prefix(limit).joined(separator: "、") + (values.count > limit ? "等" : "")
        return HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(theme.font(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            Text(summary)
                .font(theme.font(size: 13))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .help("\(title)：\(complete)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(complete)")
    }

}
