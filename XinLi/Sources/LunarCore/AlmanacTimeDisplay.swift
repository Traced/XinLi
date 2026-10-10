import Foundation

/// lunar-go's civil hour segments use the traditional UTC+8 clock. Only their
/// presentation is converted; the source record and its day are never rewritten.
public enum AlmanacTimeDisplay {
    public static func range(_ range: String, on date: SolarDate, in timeZone: TimeZone) -> String {
        guard (1...12).contains(date.month),
              (1...SolarDate.daysInMonth(year: date.year, month: date.month)).contains(date.day) else { return range }
        let parts = range.split(separator: "–")
        guard parts.count == 2 else { return range }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func instant(_ text: Substring) -> Date? {
            let time = text.split(separator: ":").compactMap { Int($0) }
            guard time.count == 2, (0...23).contains(time[0]), (0...59).contains(time[1]) else { return nil }
            return source.date(from: DateComponents(year: date.year, month: date.month, day: date.day,
                                                   hour: time[0], minute: time[1]))
        }
        guard let start = instant(parts[0]), let end = instant(parts[1]), end >= start else { return range }
        var target = Calendar(identifier: .gregorian)
        target.timeZone = timeZone
        func civilDay(_ instant: Date) -> SolarDate {
            let parts = target.dateComponents([.year, .month, .day], from: instant)
            return SolarDate(year: parts.year!, month: parts.month!, day: parts.day!)
        }
        let startDay = civilDay(start), endDay = civilDay(end)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = target
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        let startTime = formatter.string(from: start), endTime = formatter.string(from: end)
        func datePrefix(_ day: SolarDate) -> String {
            if day.year != date.year { return "\(day.year)年\(day.month)月\(day.day)日 " }
            return "\(day.month)月\(day.day)日 "
        }
        return (startDay == date ? "" : datePrefix(startDay)) + startTime + "–"
            + (endDay == startDay ? "" : datePrefix(endDay)) + endTime
    }
}
