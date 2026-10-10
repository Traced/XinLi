import AppKit
import LunarCore
import SwiftUI

/// 三种模式共用日历选择与偏好，切换模式保留原有标签页和所选日期。
@MainActor
struct CalendarDashboard: View {
    @ObservedObject var model: CalendarViewModel
    let menu: AppMenu

    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var agenda: AgendaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var localSelectedTab: DashboardTab
    @State private var isChoosingDay = false
    @State private var isMinimalAlmanacExpanded: Bool
    private let selection: Binding<DashboardTab>?

    init(model: CalendarViewModel, menu: AppMenu, agendaStore: AgendaStore = .shared,
         initialTab: DashboardTab = .calendar, selection: Binding<DashboardTab>? = nil,
         initiallyExpandMinimalAlmanac: Bool = false) {
        self.model = model
        self.menu = menu
        self.agenda = agendaStore
        self.preferences = agendaStore.preferences
        self.selection = selection
        _localSelectedTab = State(initialValue: initialTab)
        _isMinimalAlmanacExpanded = State(initialValue: initiallyExpandMinimalAlmanac)
    }

    private var selectedTab: DashboardTab {
        get { selection?.wrappedValue ?? localSelectedTab }
        nonmutating set {
            if let selection { selection.wrappedValue = newValue }
            else { localSelectedTab = newValue }
        }
    }

    private var compact: Bool { preferences.displayMode.isCompactLayout }
    private var minimal: Bool { preferences.displayMode == .minimal }
    private var width: CGFloat { preferences.displayMode.popoverWidth }
    private var contentPadding: CGFloat { compact ? 12 : 16 }
    private var density: CalendarLayoutDensity { preferences.layoutDensity }
    private var calendarPadding: CGFloat { density.spacing(compact ? 8 : 12) }
    private var calendarCellSize: CGSize {
        CGSize(width: (width - (contentPadding + calendarPadding) * 2) / 7,
               height: ((compact ? 54 : 58) + density.cellHeightOffset) * max(1, CGFloat(preferences.textScale)))
    }
    private var colors: ResolvedCalendarTheme { ResolvedCalendarTheme(preferences: preferences, colorScheme: colorScheme) }
    private var accent: Color { colors.accentText }
    private var headerForeground: Color { preferences.backgroundImageScope == .header ? .white : colors.primary }
    private var tabAnimation: Animation? {
        preferences.animationsEnabled && !reduceMotion ? .easeInOut(duration: 0.16) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                scenicHeader
            }
            dashboardContent
                .background {
                    if preferences.backgroundImageScope == .content { photoBackdrop }
                }
        }
        .frame(width: width)
        .background {
            if preferences.backgroundImageScope == .window { photoBackdrop }
            else { CalendarThemeBackdrop(theme: colors) }
        }
        .font(colors.font(size: 13))
        .foregroundStyle(colors.primary)
        .tint(accent)
        .environment(\.chronoTheme, colors)
        .environment(\.colorScheme, colors.colorScheme)
    }

    private var photoBackdrop: some View {
        CalendarPhotoBackdrop(theme: colors, image: theme.backgroundImage,
                              opacity: preferences.backgroundImageOpacity)
    }

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            if !minimal {
                tabs
                    .padding(4)
                    .glassCard(cornerRadius: 10)
                    .padding(.horizontal, contentPadding)
                    .padding(.top, density.spacing(compact ? 12 : 14))
            }

            ZStack(alignment: .top) {
                if minimal {
                    minimalContent
                } else {
                    tabContent
                        .id(selectedTab)
                        .transition(.opacity)
                }
            }
                .animation(tabAnimation, value: selectedTab)
                .padding(.horizontal, contentPadding)
                .padding(.top, density.spacing(12))
                .padding(.bottom, density.spacing(16))

            Divider().overlay(colors.primary.opacity(0.04))
            utilityBar
                .padding(.horizontal, contentPadding)
                .padding(.vertical, density.spacing(8))
                .background(colors.card.opacity(preferences.backgroundImageScope == .header ? 0.30 : 0.85))
        }
    }

    private var scenicHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack {
                if preferences.backgroundImageScope != .header {
                    Color.clear
                } else if let image = theme.backgroundImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.34, blue: 0.45),
                                            Color(red: 0.57, green: 0.64, blue: 0.71),
                                            Color(red: 0.83, green: 0.78, blue: 0.72)],
                                   startPoint: .bottomLeading, endPoint: .topTrailing)
                }
            }
            .frame(width: width, height: 132 * max(1, colors.textScale))
            .clipped()
            .overlay {
                if preferences.backgroundImageScope == .header {
                    LinearGradient(colors: [.black.opacity(0.05), .black],
                                   startPoint: .top, endPoint: .bottom)
                        .opacity(preferences.headerOverlayOpacity)
                } else {
                    colors.card.opacity(preferences.headerOverlayOpacity)
                }
            }
            .overlay {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("心历")
                            .font(colors.font(size: 13, weight: .semibold))
                            .tracking(0.4)
                        Spacer()
                        Text(headerDate(context.date))
                            .font(colors.font(size: 12, weight: .medium))
                            .monospacedDigit()
                        Button {
                            Task { await theme.refreshBingBackground() }
                        } label: {
                            Group {
                                if theme.isRefreshingBackground {
                                    ProgressView().controlSize(.small).tint(headerForeground)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(colors.font(size: 12, weight: .medium))
                                }
                            }
                            .frame(width: 28, height: 28)
                            .background(preferences.backgroundImageScope == .header ? .black.opacity(0.18) : colors.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(theme.isRefreshingBackground)
                        .help(theme.backgroundError ?? "换一张 Bing 风景")
                        .accessibilityLabel(theme.isRefreshingBackground ? "正在获取 Bing 风景" : "换一张 Bing 风景")
                    }
                    .foregroundStyle(headerForeground.opacity(0.88))
                    Spacer()
                    Text(greeting(at: context.date))
                        .font(colors.font(size: 25, weight: .medium))
                        .foregroundStyle(headerForeground)
                    HStack(spacing: 8) {
                        Text("把时间留给重要的事。")
                            .font(colors.font(size: 12))
                        Spacer(minLength: 0)
                        if let error = theme.backgroundError {
                            Label("刷新失败", systemImage: "exclamationmark.circle")
                                .font(colors.font(size: 10)).help(error)
                                .accessibilityLabel("背景刷新失败，\(error)")
                        } else if preferences.backgroundChoice == "bing", let url = theme.bingCopyrightURL {
                            Link(destination: url) {
                                Label("Bing · 图片来源", systemImage: "info.circle")
                                    .font(colors.font(size: 10))
                            }
                            .help(theme.bingCopyright ?? "查看 Bing 图片来源")
                            .accessibilityLabel(theme.bingCopyright ?? "查看 Bing 图片来源")
                        }
                    }
                    .foregroundStyle(headerForeground.opacity(0.88))
                    .padding(.top, 6)
                }
                .padding(.horizontal, contentPadding)
                .padding(.vertical, 20)
                .shadow(color: .black.opacity(preferences.backgroundImageScope == .header ? 0.12 : 0), radius: 8, y: 2)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(colors.font(size: 12, weight: .medium))
                        Text(tab.title)
                            .font(colors.font(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34 * max(1, colors.textScale))
                    .foregroundStyle(selectedTab == tab ? accent : colors.secondary)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == tab ? accent.opacity(0.09) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .calendar:
            VStack(spacing: density.spacing(12)) {
                calendarCard
                DetailPanel(day: model.detailDay, preferences: preferences) {
                    selectedTab = .almanac
                }
                AgendaSummary(store: agenda, selectedDate: model.selectedDate, compact: compact)
            }
        case .almanac:
            VStack(spacing: density.spacing(10)) {
                selectedDateNavigation
                AlmanacPanel(day: model.detailDay, timeZone: preferences.calendarTimeZone)
            }
        case .agenda:
            VStack(spacing: density.spacing(10)) {
                selectedDateNavigation
                AgendaPanel(store: agenda, selectedDate: model.selectedDate, compact: compact)
            }
        }
    }

    private var calendarCard: some View {
        CalendarView(model: model, menu: menu,
                     cellSize: calendarCellSize, agendaStore: agenda)
            .frame(maxWidth: .infinity)
            .padding(calendarPadding)
            .glassCard()
    }

    private var minimalContent: some View {
        VStack(spacing: density.spacing(12)) {
            calendarCard
            DetailPanel(day: model.detailDay, preferences: preferences,
                        isAlmanacExpanded: isMinimalAlmanacExpanded) {
                isMinimalAlmanacExpanded.toggle()
            }
            if isMinimalAlmanacExpanded && preferences.showAlmanac {
                AlmanacPanel(day: model.detailDay, timeZone: preferences.calendarTimeZone)
                    .accessibilityIdentifier("minimal-almanac-details")
                    .transition(.opacity)
            }
        }
        .animation(tabAnimation, value: isMinimalAlmanacExpanded)
        .accessibilityIdentifier("minimal-calendar")
    }

    private var selectedDateNavigation: some View {
        HStack(spacing: 6) {
            Button { isChoosingDay = true } label: {
                Label(model.detailDay.solarText, systemImage: "calendar")
                    .font(colors.font(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(colors.accentText)
                    .padding(.horizontal, 6)
                    .frame(height: 30 * max(1, colors.textScale))
            }
            .help("选择年月日")
            .accessibilityLabel("选择日期，当前\(model.detailDay.solarText)")
            .popover(isPresented: $isChoosingDay, arrowEdge: .top) {
                QuickDatePicker(initialDate: model.selectedDate, timeZone: preferences.timeZone,
                                firstWeekday: preferences.firstWeekday) { date in
                    // moveSelection constructs the day using the model's own data
                    // and commits one selection; browsing the picker is draft-only.
                    model.moveSelection(by: date.dayNumber - model.selectedDate.dayNumber)
                    isChoosingDay = false
                } onCancel: {
                    isChoosingDay = false
                }
                .environment(\.chronoTheme, colors)
                .environment(\.colorScheme, colors.colorScheme)
            }
            Spacer(minLength: 0)
            Button { model.showToday() } label: {
                Text("今天").padding(.horizontal, 8).frame(height: 30 * max(1, colors.textScale))
            }
            .help("回到应用时区的今天")
            HStack(spacing: 2) {
                Button { model.moveSelection(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 26, height: 30)
                }
                .disabled(!CalendarViewModel.years.contains(model.selectedDate.adding(days: -1).year))
                .help("前一天")
                .accessibilityLabel("前一天")
                Button { model.moveSelection(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 26, height: 30)
                }
                .disabled(!CalendarViewModel.years.contains(model.selectedDate.adding(days: 1).year))
                .help("后一天")
                .accessibilityLabel("后一天")
            }
        }
        .font(colors.font(size: 12, weight: .medium))
        .foregroundStyle(colors.primary)
        .buttonStyle(DateNavigationButtonStyle())
        .padding(density.spacing(6))
        .glassCard(cornerRadius: 10)
        .onDisappear { isChoosingDay = false }
    }

    private var utilityBar: some View {
        HStack(spacing: 8) {
            menu.button
                .frame(width: 24, height: 24)
            Text(compact ? "心历" : timeZoneLabel)
                .font(colors.font(size: 12))
                .foregroundStyle(colors.secondary)
                .lineLimit(1)
                .help(preferences.calendarTimeZone.identifier)
            Spacer()
            if compact, preferences.backgroundImageScope != .header {
                if preferences.backgroundChoice == "bing", let url = theme.bingCopyrightURL {
                    Link(destination: url) {
                        Image(systemName: "info.circle").frame(width: 20, height: 24)
                    }
                    .help(theme.bingCopyright ?? "Bing 图片来源")
                    .accessibilityLabel(theme.bingCopyright ?? "Bing 图片来源")
                }
                Button {
                    Task { await theme.refreshBingBackground() }
                } label: {
                    Group {
                        if theme.isRefreshingBackground {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(theme.isRefreshingBackground)
                .help(theme.backgroundError ?? "换一张 Bing 风景")
                .accessibilityLabel("换一张 Bing 风景")
            }
            if !minimal {
                Button {
                    agenda.showEventEditor(on: model.selectedDate, event: nil)
                } label: {
                    Label("新建日程", systemImage: "plus")
                        .font(colors.font(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .help("新建日程 (⌘N)")
            }
        }
        .frame(minHeight: 28 * max(1, colors.textScale))
    }

    private var timeZoneLabel: String {
        preferences.calendarTimeZone.localizedName(for: .shortGeneric, locale: Locale(identifier: "zh_CN"))
            ?? preferences.calendarTimeZone.identifier
    }

    private func headerDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = preferences.calendarTimeZone
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        formatter.weekdaySymbols = weekdays
        formatter.shortWeekdaySymbols = weekdays
        formatter.veryShortWeekdaySymbols = weekdays
        formatter.dateFormat = preferences.use24HourTime ? "M月d日 EEEE · HH:mm" : "M月d日 EEEE · a h:mm"
        return formatter.string(from: date)
    }

    private func greeting(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = preferences.calendarTimeZone
        switch calendar.component(.hour, from: date) {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<24: return "晚上好"
        default: return "夜深了"
        }
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case calendar, almanac, agenda
    var id: Self { self }
    var title: String {
        switch self {
        case .calendar: return "日历"
        case .almanac: return "万年历"
        case .agenda: return "日程"
        }
    }
    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .almanac: return "sun.max"
        case .agenda: return "list.bullet.rectangle"
        }
    }
}

/// 日历与日程颜色统一接受持久化的 RGB / RGBA 十六进制值。
enum ChronoThemeColor {
    static func color(hex: String) -> Color {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard (text.count == 6 || text.count == 8), let value = UInt64(text, radix: 16) else {
            return Color.accentColor
        }
        let hasAlpha = text.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        return Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255,
                     green: Double((rgb >> 8) & 0xff) / 255,
                     blue: Double(rgb & 0xff) / 255,
                     opacity: hasAlpha ? Double(value & 0xff) / 255 : 1)
    }
}
