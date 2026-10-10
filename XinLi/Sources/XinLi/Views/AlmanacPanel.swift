import SwiftUI
import LunarCore

@MainActor
struct AlmanacPanel: View {
    @Environment(\.chronoTheme) private var theme
    let day: CalendarDay
    var timeZone: TimeZone = SolarTermEngine.calendarTimeZone
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var store = DataStore.shared
    @State private var hoursExpanded: Bool

    init(day: CalendarDay, timeZone: TimeZone = SolarTermEngine.calendarTimeZone,
         initiallyExpandHours: Bool = false) {
        self.day = day
        self.timeZone = timeZone
        _hoursExpanded = State(initialValue: initiallyExpandHours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(12)) {
            dateOverview
            if preferences.showSolarTerms {
                sectionCard("节气", icon: "sun.horizon") {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        solarTerms(at: context.date)
                    }
                }
            }
            if preferences.showHolidays {
                sectionCard("假期安排", icon: "calendar.badge.checkmark") { holidayDetails }
            }
            if preferences.showAlmanac {
                AlmanacRecordContent(date: day.date) { almanac in
                    almanacContent(almanac)
                }
            }
        }
        .font(theme.font(size: 13))
        .foregroundStyle(theme.primary)
        .tint(theme.accentText)
        .disclosureGroupStyle(FullRowDisclosureStyle(animationsEnabled: preferences.animationsEnabled))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("历法详情")
    }

    private var dateOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.solarText)
                    .font(theme.font(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(day.weekdayName)
                    .font(theme.font(size: 13, weight: .medium))
                    .foregroundStyle(theme.accentText)
            }
            if preferences.showLunar {
                let month = LunarMonthSummary(day: day)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("农历 \(day.lunarMonthName)月\(day.lunarDayName)", systemImage: "moon")
                        .font(theme.font(size: 14, weight: .medium))
                    Spacer(minLength: 0)
                    Text("\(month.sizeName) · \(month.numberOfDays)天")
                        .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                }
            }
            if preferences.showGanZhi {
                Text("\(day.ganZhiYearByLiChun)年 · \(day.ganZhiMonth)月 · \(day.ganZhiDay)日 · 属\(day.shengXiao)")
                    .font(theme.font(size: 13)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup {
                    Text("生肖年以春节为界；年柱以立春日期为界。")
                        .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                } label: {
                    Text("干支与生肖说明").font(theme.font(size: 12)).foregroundStyle(theme.accentText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.layoutDensity.spacing(14))
        .glassCard()
    }

    private func sectionCard<Content: View>(_ title: String, icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(12)) {
            Label(title, systemImage: icon)
                .font(theme.font(size: 14, weight: .semibold))
                .foregroundStyle(theme.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.layoutDensity.spacing(14))
        .glassCard()
    }

    @ViewBuilder
    private func almanacContent(_ almanac: AlmanacAvailability) -> some View {
        switch almanac {
        case .unavailable(let reason):
            sectionCard("黄历数据暂不可用", icon: "info.circle") {
                Text(reason).font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .available(let record):
            almanacDetails(record)
        }
    }

    private func almanacDetails(_ record: AlmanacRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.layoutDensity.spacing(12)) {
            sectionCard("黄历宜忌", icon: "leaf") {
                activityRow("宜", values: record.suitableActivities, color: theme.positive)
                activityRow("忌", values: record.unsuitableActivities, color: theme.danger)
                Text("传统民俗参考，宜忌与吉凶不代表实际结果。")
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sectionCard("历书详记", icon: "text.book.closed") {
                detailRow("冲煞", value: joined(record.clashes))
                if preferences.showGanZhi {
                    detailRow("干支", value: "\(record.yearGanZhi)年 · \(record.monthGanZhi)月 · \(record.dayGanZhi)日")
                }
                detailRow("彭祖百忌", value: record.pengZu.isEmpty ? "未记载" : record.pengZu.joined(separator: "\n"))
            }
            sectionCard("时辰", icon: "clock") {
                hourSummary(record.hours)
                DisclosureGroup(isExpanded: $hoursExpanded) {
                    VStack(spacing: 8) {
                        ForEach(record.hours, id: \.id) { hour in hourRow(hour) }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("查看全部 \(record.hours.count) 个时段")
                        .font(theme.font(size: 13, weight: .medium))
                        .foregroundStyle(theme.accentText)
                }
                Text("时区：\(timeZone.identifier) · 跨日标注日期")
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourceCard(record.source)
        }
    }

    @ViewBuilder
    private func hourSummary(_ hours: [AlmanacHour]) -> some View {
        let auspicious = hours.filter(\.isAuspicious)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("吉时").font(theme.font(size: 13, weight: .medium)).foregroundStyle(theme.positive)
                Text(auspicious.isEmpty ? "未记载" : "\(auspicious.count) 个时段")
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
            }
            if !auspicious.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88 * theme.textScale), spacing: 7)], alignment: .leading, spacing: 7) {
                    ForEach(auspicious) { hour in
                        Text("\(branchTitle(hour)) · \(hour.ganZhi)")
                            .font(theme.font(size: 12, weight: .medium))
                            .foregroundStyle(theme.positive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(theme.positive.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("\(branchTitle(hour))时，\(hour.ganZhi)，\(hourRange(hour))，吉")
                    }
                }
            }
        }
    }

    private func sourceCard(_ source: AlmanacSource) -> some View {
        sectionCard("数据来源", icon: "link") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sourceLinks(source) }
                VStack(alignment: .leading, spacing: 8) { sourceLinks(source) }
            }
            .font(theme.font(size: 13, weight: .medium))
            Text("黄历覆盖 \(String(source.coveredYears.lowerBound))–\(String(source.coveredYears.upperBound)) 年")
                .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 7) {
                    Text("黄历时段按北京时间划分，再换算至所选时区；早子与晚子分别保留。")
                }
                .font(theme.font(size: 12))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            } label: {
                Text("时辰换算说明").font(theme.font(size: 13)).foregroundStyle(theme.accentText)
            }
        }
    }

    @ViewBuilder
    private func sourceLinks(_ source: AlmanacSource) -> some View {
        Link(source.title, destination: source.sourceURL).foregroundStyle(theme.accentText)
        Link("MIT 许可", destination: source.licenseURL).foregroundStyle(theme.accentText)
    }

    private func hourRow(_ hour: AlmanacHour) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                activityRow("宜", values: hour.suitableActivities, color: theme.positive)
                activityRow("忌", values: hour.unsuitableActivities, color: theme.danger)
                detailRow("冲煞", value: [hour.clash, hour.sha].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            .padding(.top, 9)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text("\(branchTitle(hour))时 · \(hour.ganZhi)")
                        .font(theme.font(size: 13, weight: .medium)).foregroundStyle(theme.primary)
                    Spacer(minLength: 0)
                    Text(hour.heavenlySpirit)
                        .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                    Text(hour.luck)
                        .font(theme.font(size: 12, weight: .semibold))
                        .foregroundStyle(hour.isAuspicious ? theme.positive : theme.danger)
                }
                Text(hourRange(hour))
                    .font(theme.font(size: 12).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(theme.secondary)
            }
        }
        .padding(10)
        .background(theme.card.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.primary.opacity(0.055), lineWidth: 0.75))
    }

    private func activityRow(_ title: String, values: [String], color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(theme.font(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(joined(values))
                .font(theme.font(size: 13))
                .foregroundStyle(theme.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                .frame(width: 52 * theme.textScale, alignment: .leading)
            Text(value.isEmpty ? "未记载" : value)
                .font(theme.font(size: 13)).foregroundStyle(theme.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lineSpacing(4)
    }

    private func joined(_ values: [String]) -> String {
        values.isEmpty ? "未记载" : values.joined(separator: "、")
    }

    private func branchTitle(_ hour: AlmanacHour) -> String {
        if hour.branch == "子" {
            if hour.timeRange.hasPrefix("00:") { return "早子" }
            if hour.timeRange.hasPrefix("23:") { return "晚子" }
        }
        return hour.branch
    }

    private func hourRange(_ hour: AlmanacHour) -> String {
        AlmanacTimeDisplay.range(hour.timeRange, on: day.date, in: timeZone)
    }

    @ViewBuilder
    private func solarTerms(at now: Date) -> some View {
        let isToday = SolarTermEngine.calendarDate(at: now, timeZone: timeZone) == day.date
        let terms = SolarTermEngine.context(on: day.date, reference: isToday ? now : nil, timeZone: timeZone)
        VStack(alignment: .leading, spacing: 11) {
            if let onDate = terms.onDate.first { termRow("当日交节", term: onDate) }
            if let current = terms.current { termRow("当前节气", term: current) }
            if let next = terms.next {
                termRow("下一节气", term: next, remainingDays: terms.nextInDays)
            }
            Text(isToday ? "时区：\(timeZone.identifier)" : "以所选日期 12:00 为参考 · \(timeZone.identifier)")
                .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !SolarTermEngine.verifiedTimeYears.contains(day.date.year) {
                Label("该年份仅提供北京时间日期；已核验时刻覆盖 2025–2027 年。", systemImage: "info.circle")
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                DisclosureGroup {
                    Text("交节时刻为计算值；2025–2027 年与香港天文台分钟表核验差小于 1 分钟。")
                        .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                } label: {
                    Text("交节时刻说明 · 2025–2027")
                        .font(theme.font(size: 12)).foregroundStyle(theme.accentText)
                }
            }
        }
    }

    private func termRow(_ title: String, term: SolarTermOccurrence, remainingDays: Int? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                .frame(width: 52 * theme.textScale, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(term.name).font(theme.font(size: 14, weight: .medium)).foregroundStyle(theme.primary)
                    Spacer(minLength: 0)
                    if let days = remainingDays {
                        Text(days == 0 ? "今日交节" : "还有 \(days) 天")
                            .font(theme.font(size: 12, weight: .medium)).foregroundStyle(theme.accentText)
                    }
                }
                Text(termTime(term)).font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func termTime(_ term: SolarTermOccurrence) -> String {
        guard let instant = term.instant else {
            return "\(term.date.year)年\(term.date.month)月\(term.date.day)日 · 仅日期（北京）"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let rounded = Date(timeIntervalSince1970: (instant.timeIntervalSince1970 / 60).rounded() * 60)
        return "约 " + formatter.string(from: rounded)
    }

    private var holidayDetails: some View {
        let coverage = HolidayCoverage(data: store.holidays)
        return VStack(alignment: .leading, spacing: 8) {
            if let holiday = day.holiday {
                Label("\(holiday.name) · \(holiday.isOffDay ? "放假" : "调休上班")",
                      systemImage: holiday.isOffDay ? "sun.max" : "briefcase")
                    .font(theme.font(size: 14, weight: .medium))
                    .foregroundStyle(holiday.isOffDay ? theme.danger : theme.primary)
            } else if coverage.hasRecords(in: day.date.year) {
                Text(day.isWeekend ? "周末 · 当日无调休记录" : "当日无放假或调休记录")
                    .font(theme.font(size: 13)).foregroundStyle(theme.primary)
            } else {
                Text("\(String(day.date.year)) 年暂无已载入的假期安排")
                    .font(theme.font(size: 13)).foregroundStyle(theme.primary)
            }
            if coverage.years.isEmpty {
                Text("假期数据尚未载入。节日名称不等同于放假安排。")
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
            } else {
                Text("假期记录年份：" + coverage.years.map(String.init).joined(separator: "、"))
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
                Text("仅依据已载入的安排；未列出的年份不推算放假。")
                    .font(theme.font(size: 12)).foregroundStyle(theme.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
