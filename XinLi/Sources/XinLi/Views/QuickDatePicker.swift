import LunarCore
import SwiftUI

/// Native day selection keeps month browsing and typed dates local until confirmation.
@MainActor
struct QuickDatePicker: View {
    let timeZone: TimeZone
    let firstWeekday: Int
    let onSelect: (SolarDate) -> Void
    let onCancel: () -> Void
    @State private var draftDate: Date
    @Environment(\.chronoTheme) private var theme

    init(initialDate: SolarDate, timeZone: TimeZone, firstWeekday: Int,
         onSelect: @escaping (SolarDate) -> Void, onCancel: @escaping () -> Void) {
        self.timeZone = timeZone
        self.firstWeekday = firstWeekday
        self.onSelect = onSelect
        self.onCancel = onCancel
        let first = SolarDate(year: CalendarViewModel.years.lowerBound, month: 1, day: 1)
        let last = SolarDate(year: CalendarViewModel.years.upperBound, month: 12, day: 31)
        let selected = min(max(initialDate, first), last)
        _draftDate = State(initialValue: AgendaDates.date(selected, timeZone: timeZone, hour: 12))
    }

    private var calendar: Calendar {
        var calendar = AgendaDates.calendar(timeZone)
        calendar.firstWeekday = min(max(firstWeekday, 1), 7)
        return calendar
    }

    private var dateRange: ClosedRange<Date> {
        let first = AgendaDates.date(SolarDate(year: CalendarViewModel.years.lowerBound, month: 1, day: 1), timeZone: timeZone)
        let last = AgendaDates.date(SolarDate(year: CalendarViewModel.years.upperBound, month: 12, day: 31), timeZone: timeZone)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: last) ?? last
        return first...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择日期").font(theme.font(size: 15, weight: .semibold))
            DatePicker("日期月历", selection: $draftDate, in: dateRange, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("选择日期月历")
            HStack(spacing: 12) {
                Text("直接输入").font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                Spacer(minLength: 0)
                DatePicker("年月日", selection: $draftDate, in: dateRange, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .accessibilityLabel("直接输入年月日")
            }
            Text("\(String(CalendarViewModel.years.lowerBound))–\(String(CalendarViewModel.years.upperBound)) 年 · \(timeZone.identifier)")
                .font(theme.font(size: 11)).foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button("确定") {
                    let selected = AgendaDates.solar(draftDate, timeZone: timeZone)
                    guard CalendarViewModel.years.contains(selected.year) else { return }
                    onSelect(selected)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(theme.primary)
        .background(CalendarThemeBackdrop(theme: theme))
        .tint(theme.accentText)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, timeZone)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onChange(of: timeZone.identifier) { previous, _ in
            let previousTimeZone = TimeZone(identifier: previous) ?? timeZone
            let day = AgendaDates.solar(draftDate, timeZone: previousTimeZone)
            draftDate = AgendaDates.date(day, timeZone: timeZone, hour: 12)
        }
        .onExitCommand(perform: onCancel)
    }
}

struct DateNavigationButtonStyle: ButtonStyle {
    @Environment(\.chronoTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(theme.primary.opacity(isEnabled && (isHovered || configuration.isPressed) ? 0.07 : 0),
                        in: RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
    }
}
