import Foundation
import LunarCore
import SwiftUI

/// 选择器只修改草稿；确定年月之前不会影响当前日历或选中的日期。
struct MonthYearPickerDraft: Equatable, Sendable {
    let years: ClosedRange<Int>
    private(set) var year: Int
    private(set) var month: Int
    private(set) var yearPageStart: Int

    init(year: Int, month: Int, years: ClosedRange<Int> = LunarCalendar.supportedYears) {
        self.years = years
        self.year = min(max(year, years.lowerBound), years.upperBound)
        self.month = min(max(month, 1), 12)
        yearPageStart = years.lowerBound + (self.year - years.lowerBound) / 12 * 12
    }

    var visibleYears: [Int] { Array(yearPageStart...min(yearPageStart + 11, years.upperBound)) }
    var canMoveToPreviousYear: Bool { year > years.lowerBound }
    var canMoveToNextYear: Bool { year < years.upperBound }
    var canMoveToPreviousPage: Bool { yearPageStart > years.lowerBound }
    var canMoveToNextPage: Bool { yearPageStart + 12 <= years.upperBound }

    @discardableResult
    mutating func selectYear(_ value: Int) -> Bool {
        guard years.contains(value) else { return false }
        year = value
        yearPageStart = years.lowerBound + (value - years.lowerBound) / 12 * 12
        return true
    }

    @discardableResult
    mutating func selectMonth(_ value: Int) -> Bool {
        guard (1...12).contains(value) else { return false }
        month = value
        return true
    }

    @discardableResult
    mutating func moveYear(by delta: Int) -> Bool {
        guard delta == -1 || delta == 1 else { return false }
        return selectYear(year + delta)
    }

    @discardableResult
    mutating func moveYearPage(by delta: Int) -> Bool {
        guard delta == -1 || delta == 1 else { return false }
        let proposed = yearPageStart + delta * 12
        guard years.contains(proposed) else { return false }
        yearPageStart = proposed
        return true
    }

    static func validatedYear(_ text: String, in years: ClosedRange<Int> = LunarCalendar.supportedYears) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.utf8.count == 4, input.utf8.allSatisfy({ (48...57).contains($0) }),
              let year = Int(input), years.contains(year) else { return nil }
        return year
    }
}

@MainActor
struct MonthYearPicker: View {
    let today: SolarDate
    let compact: Bool
    let accent: Color
    let animationsEnabled: Bool
    let onSelect: (Int, Int) -> Void
    let onCancel: () -> Void

    @State private var draft: MonthYearPickerDraft
    @State private var yearText: String
    @State private var mode = PickerMode.months
    @State private var showsValidationError = false
    @FocusState private var yearFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chronoTheme) private var theme

    init(year: Int, month: Int, today: SolarDate, compact: Bool, accent: Color,
         animationsEnabled: Bool = true, initiallyShowsYears: Bool = false,
         initialYearText: String? = nil, onSelect: @escaping (Int, Int) -> Void,
         onCancel: @escaping () -> Void) {
        self.today = today
        self.compact = compact
        self.accent = accent
        self.animationsEnabled = animationsEnabled
        self.onSelect = onSelect
        self.onCancel = onCancel
        var initial = MonthYearPickerDraft(year: year, month: month)
        let input = initialYearText ?? String(initial.year)
        if let inputYear = MonthYearPickerDraft.validatedYear(input) { initial.selectYear(inputYear) }
        _draft = State(initialValue: initial)
        _yearText = State(initialValue: input)
        _mode = State(initialValue: initiallyShowsYears ? .years : .months)
        _showsValidationError = State(initialValue: MonthYearPickerDraft.validatedYear(input) == nil)
    }

    private var validInputYear: Int? { MonthYearPickerDraft.validatedYear(yearText, in: draft.years) }
    private var cellHeight: CGFloat { (compact ? 42 : 46) * max(1, theme.textScale) }
    private var rangeText: String { "\(String(draft.years.lowerBound))–\(String(draft.years.upperBound))" }

    var body: some View {
        VStack(spacing: 12) {
            navigation
            ZStack {
                selectionGrid
                    .id(mode)
                    .transition(.opacity)
            }
            .frame(height: cellHeight * 4 + 24)
            .animation(animationsEnabled && !reduceMotion ? .easeInOut(duration: 0.12) : nil, value: mode)
            Divider().opacity(0.5)
            yearEntry
        }
        .padding(.vertical, 4)
        .onChange(of: yearText) { _, value in
            if let year = MonthYearPickerDraft.validatedYear(value, in: draft.years) {
                draft.selectYear(year)
                showsValidationError = false
            } else {
                showsValidationError = value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
            }
        }
        .onExitCommand(perform: onCancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("选择年月")
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            Button {
                yearFieldFocused = false
                mode = mode == .months ? .years : .months
            } label: {
                HStack(spacing: 6) {
                    Text(mode == .months ? "\(String(draft.year))年" : "\(String(draft.yearPageStart))–\(String(draft.visibleYears.last!))")
                        .font(theme.font(size: compact ? 15 : 16, weight: .semibold))
                        .monospacedDigit()
                    Image(systemName: mode == .months ? "chevron.down" : "chevron.up")
                        .font(theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 28 * max(1, theme.textScale))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(mode == .months ? "选择年份" : "返回月份选择")
            .accessibilityLabel(mode == .months ? "选择年份，当前\(String(draft.year))年" : "返回月份选择，当前年份组\(String(draft.yearPageStart))至\(String(draft.visibleYears.last!))")

            Spacer(minLength: 4)
            navigationButton(direction: -1)
            navigationButton(direction: 1)
        }
    }

    private func navigationButton(direction: Int) -> some View {
        let previous = direction == -1
        let title = mode == .months ? (previous ? "上一年" : "下一年") : (previous ? "上一组年份" : "下一组年份")
        let enabled = mode == .months
            ? validInputYear != nil && (previous ? draft.canMoveToPreviousYear : draft.canMoveToNextYear)
            : (previous ? draft.canMoveToPreviousPage : draft.canMoveToNextPage)
        return Button {
            yearFieldFocused = false
            if mode == .months {
                if draft.moveYear(by: direction) { yearText = String(draft.year) }
            } else {
                draft.moveYearPage(by: direction)
            }
        } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right")
                .font(theme.font(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(MonthYearNavigationStyle())
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private var selectionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(0..<12, id: \.self) { index in
                if mode == .months {
                    let month = index + 1
                    pickerCell("\(month)月", selected: month == draft.month,
                               current: today.year == draft.year && today.month == month,
                               accessibility: "\(String(draft.year))年\(month)月") {
                        confirm(month: month)
                    }
                    .disabled(validInputYear == nil)
                } else if index < draft.visibleYears.count {
                    let year = draft.visibleYears[index]
                    pickerCell(String(year), selected: year == draft.year, current: year == today.year,
                               accessibility: "\(String(year))年") {
                        draft.selectYear(year)
                        yearText = String(year)
                        yearFieldFocused = false
                        mode = .months
                    }
                } else {
                    Color.clear.frame(height: cellHeight).accessibilityHidden(true)
                }
            }
        }
    }

    private func pickerCell(_ text: String, selected: Bool, current: Bool, accessibility: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(theme.font(size: compact ? 15 : 16, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(MonthYearCellStyle(selected: selected, current: current, accent: accent))
        .accessibilityLabel(accessibility)
        .accessibilityValue([selected ? "当前草稿选择" : "", current ? "今天所在年月" : ""].filter { !$0.isEmpty }.joined(separator: "，"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var yearEntry: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("年份").font(theme.font(size: 12)).foregroundStyle(.secondary)
                TextField(rangeText, text: $yearText)
                    .textFieldStyle(.plain)
                    .font(theme.font(size: 14).monospacedDigit())
                    .frame(width: 68 * theme.textScale)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(theme.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(showsValidationError ? theme.danger : .clear, lineWidth: 1))
                    .focused($yearFieldFocused)
                    .onSubmit { confirm(month: draft.month) }
                    .accessibilityLabel("直接输入四位年份，\(rangeText)")
                Spacer(minLength: 8)
                Button("确定") { confirm(month: draft.month) }
                    .font(theme.font(size: 12, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validInputYear == nil)
                    .accessibilityLabel("确定\(String(draft.year))年\(draft.month)月")
            }
            Text(showsValidationError ? "请输入 \(rangeText) 范围内的四位年份" : "支持 \(rangeText) 年")
                .font(theme.font(size: 11))
                .foregroundStyle(showsValidationError ? theme.danger : theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirm(month: Int) {
        guard let year = validInputYear, draft.selectYear(year), draft.selectMonth(month) else {
            showsValidationError = true
            yearFieldFocused = true
            return
        }
        yearFieldFocused = false
        onSelect(draft.year, draft.month)
    }

    private enum PickerMode: Equatable { case months, years }
}

private struct MonthYearCellStyle: ButtonStyle {
    @Environment(\.chronoTheme) private var theme
    let selected: Bool
    let current: Bool
    let accent: Color
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? theme.selectionForeground : theme.primary)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? theme.selectionBackground : theme.primary.opacity(hovered || configuration.isPressed ? 0.10 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(current && !selected ? theme.secondary.opacity(0.5) : .clear, lineWidth: 1))
            .opacity(isEnabled ? configuration.isPressed ? 0.75 : 1 : 0.4)
            .onHover { hovered = $0 }
    }
}

private struct MonthYearNavigationStyle: ButtonStyle {
    @Environment(\.chronoTheme) private var theme
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.primary.opacity(isEnabled ? 1 : 0.3))
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isEnabled && (hovered || configuration.isPressed) ? theme.primary.opacity(0.06) : .clear))
            .onHover { hovered = $0 }
    }
}
