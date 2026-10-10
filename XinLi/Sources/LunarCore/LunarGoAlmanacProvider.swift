import CryptoKit
import Foundation

/// Offline records exported from a pinned lunar-go release. No Go runtime or
/// subprocess is needed by the application. A small year cache is protected by
/// one lock; views load records off the main actor and may read hot records
/// synchronously through the nonblocking cachedRecord(for:) path.
public final class LunarGoAlmanacProvider: AlmanacProvider, @unchecked Sendable {
    public static let shared = LunarGoAlmanacProvider()
    public static let supportedYears = 1901...2099
    public static let version = "v1.4.6"
    public static let commit = "dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649"
    public static let source = AlmanacSource(
        title: "lunar-go \(version)",
        sourceURL: URL(string: "https://github.com/6tail/lunar-go/tree/\(commit)")!,
        licenseURL: URL(string: "https://github.com/6tail/lunar-go/blob/\(commit)/LICENSE")!,
        coveredYears: supportedYears)

    private let resourceDirectory: URL?
    private let lock = NSLock()
    // All mutable state below is accessed while holding lock.
    private var manifestResult: Result<Manifest, DataError>?
    private var cache: [Int: Result<[AlmanacRecord], DataError>] = [:]
    private var recentlyUsed: [Int] = []

    /// An explicit directory is useful for validation/imports and never falls
    /// back to bundled data if its manifest or a year file is missing.
    public init(resourceDirectory: URL? = nil) {
        self.resourceDirectory = resourceDirectory ?? Self.bundledDirectory()
    }

    public func record(for date: SolarDate) -> AlmanacAvailability {
        if let invalid = Self.validationFailure(for: date) { return invalid }
        lock.lock()
        defer { lock.unlock() }
        let loaded = cache[date.year] ?? load(year: date.year)
        cache[date.year] = loaded
        markRecentlyUsed(date.year)
        while recentlyUsed.count > 3 { cache.removeValue(forKey: recentlyUsed.removeFirst()) }
        return Self.availability(for: date, in: loaded)
    }

    /// Never reads files, decompresses data, or waits for a load in progress.
    /// A cold year or a busy cache returns nil so the caller can load off-thread.
    /// Invalid dates and already-cached failures return their actual unavailable result.
    public func cachedRecord(for date: SolarDate) -> AlmanacAvailability? {
        if let invalid = Self.validationFailure(for: date) { return invalid }
        guard lock.try() else { return nil }
        let cached = cache[date.year]
        if cached != nil { markRecentlyUsed(date.year) }
        lock.unlock()
        return cached.map { Self.availability(for: date, in: $0) }
    }

    private static func validationFailure(for date: SolarDate) -> AlmanacAvailability? {
        guard Self.supportedYears.contains(date.year) else {
            return .unavailable(reason: "lunar-go 离线黄历覆盖 1901–2099 年；所选年份不在范围内。")
        }
        guard (1...12).contains(date.month),
              (1...SolarDate.daysInMonth(year: date.year, month: date.month)).contains(date.day) else {
            return .unavailable(reason: "无效公历日期，无法读取黄历。")
        }
        return nil
    }

    /// Caller holds lock. A cache-only hit refreshes recency without evicting anything.
    private func markRecentlyUsed(_ year: Int) {
        recentlyUsed.removeAll { $0 == year }
        recentlyUsed.append(year)
    }

    private static func availability(for date: SolarDate, in loaded: Result<[AlmanacRecord], DataError>) -> AlmanacAvailability {
        switch loaded {
        case .success(let records):
            let offset = date.dayNumber - SolarDate(year: date.year, month: 1, day: 1).dayNumber
            guard records.indices.contains(offset), records[offset].date == date else {
                return .unavailable(reason: "lunar-go 黄历缺少所选日期的记录。")
            }
            return .available(records[offset])
        case .failure(let error):
            return .unavailable(reason: error.message)
        }
    }

    private func load(year: Int) -> Result<[AlmanacRecord], DataError> {
        do {
            guard let resourceDirectory else { throw DataError.missing }
            let manifest: Manifest
            if let manifestResult { manifest = try manifestResult.get() }
            else {
                let loaded: Result<Manifest, DataError>
                do {
                    let data = try Data(contentsOf: resourceDirectory.appendingPathComponent("manifest.json"))
                    let decoded = try JSONDecoder().decode(Manifest.self, from: data)
                    try decoded.validate()
                    loaded = .success(decoded)
                } catch { loaded = .failure(error as? DataError ?? .invalid) }
                manifestResult = loaded
                manifest = try loaded.get()
            }
            guard let entry = manifest.years.first(where: { $0.year == year }) else { throw DataError.missing }
            let compressed = try Data(contentsOf: resourceDirectory.appendingPathComponent(entry.file))
            guard compressed.count <= 5_000_000, Self.digest(compressed) == entry.sha256 else { throw DataError.invalid }
            let json = try (compressed as NSData).decompressed(using: .lzfse) as Data
            guard json.count <= 15_000_000, Self.digest(json) == entry.uncompressedSHA256 else { throw DataError.invalid }
            let package = try JSONDecoder().decode(YearPackage.self, from: json)
            let dayCount = SolarDate.isLeapYear(year) ? 366 : 365
            guard package.schemaVersion == 1, package.year == year,
                  entry.recordCount == dayCount, package.records.count == dayCount else { throw DataError.invalid }
            let first = SolarDate(year: year, month: 1, day: 1)
            let records = try package.records.enumerated().map { offset, item in
                let date = first.adding(days: offset)
                let expected = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
                guard item.date == expected, (year - 1...year).contains(item.lunarYear),
                      item.lunarMonth != 0, (-12...12).contains(item.lunarMonth),
                      (1...30).contains(item.lunarDay), item.hours.count == 13,
                      item.yearGanZhi.count == 2, item.monthGanZhi.count == 2, item.dayGanZhi.count == 2,
                      item.hours.map(\.timeRange) == Self.hourRanges,
                      item.hours.map(\.branch) == Array("子丑寅卯辰巳午未申酉戌亥子").map(String.init),
                      item.hours.allSatisfy({ $0.ganZhi.count == 2 && ["吉", "凶"].contains($0.luck) }) else {
                    throw DataError.invalid
                }
                return AlmanacRecord(date: date, suitableActivities: item.suitableActivities,
                                     unsuitableActivities: item.unsuitableActivities, clashes: item.clashes,
                                     auspiciousHours: item.hours.filter(\.isAuspicious).map { "\($0.ganZhi)（\($0.timeRange)）" },
                                     source: Self.source, lunarYear: item.lunarYear, lunarMonth: item.lunarMonth,
                                     lunarDay: item.lunarDay, yearGanZhi: item.yearGanZhi,
                                     monthGanZhi: item.monthGanZhi, dayGanZhi: item.dayGanZhi,
                                     pengZu: item.pengZu, hours: item.hours)
            }
            return .success(records)
        } catch {
            return .failure(error as? DataError ?? .unreadable)
        }
    }

    private static let hourRanges = ["00:00–00:59"] + stride(from: 1, through: 21, by: 2).map {
        String(format: "%02d:00–%02d:59", $0, $0 + 1)
    } + ["23:00–23:59"]

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func bundledDirectory() -> URL? {
        // Both Xcode and the release packager put SwiftPM's resource bundle
        // here. Never silently use a developer's absolute build path in .app.
        let locations = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for location in locations {
            let url = location.appendingPathComponent("XinLi_LunarCore.bundle")
            if let bundle = Bundle(url: url), let folder = bundle.url(forResource: "LunarGo", withExtension: nil) {
                return folder
            }
        }
        if Bundle.main.bundleURL.pathExtension == "app" { return nil }
        return Bundle.module.url(forResource: "LunarGo", withExtension: nil)
    }

    private enum DataError: Error {
        case missing, invalid, unreadable
        var message: String {
            switch self {
            case .missing: "未找到 lunar-go 离线黄历资源，请重新安装完整应用。"
            case .invalid: "lunar-go 黄历数据版本、完整性或日期校验失败，未显示未经验证的内容。"
            case .unreadable: "无法读取 lunar-go 离线黄历数据，请检查应用资源是否完整。"
            }
        }
    }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let source: Source
        let startYear: Int
        let endYear: Int
        let recordCount: Int
        let years: [YearEntry]
        struct Source: Decodable { let repository: String; let version: String; let commit: String; let license: String }
        struct YearEntry: Decodable {
            let year: Int; let recordCount: Int; let file: String; let sha256: String; let uncompressedSHA256: String
        }
        func validate() throws {
            let coverage = LunarGoAlmanacProvider.supportedYears
            guard schemaVersion == 1, startYear == coverage.lowerBound, endYear == coverage.upperBound,
                  source.repository == "https://github.com/6tail/lunar-go", source.version == LunarGoAlmanacProvider.version,
                  source.commit == LunarGoAlmanacProvider.commit, source.license == "MIT",
                  years.map(\.year).sorted() == Array(coverage),
                  recordCount == years.reduce(0, { $0 + $1.recordCount }),
                  years.allSatisfy({
                      $0.file == "\($0.year).json.lzfse" && $0.recordCount == (SolarDate.isLeapYear($0.year) ? 366 : 365)
                      && $0.sha256.count == 64 && $0.uncompressedSHA256.count == 64
                  }) else { throw DataError.invalid }
        }
    }

    private struct YearPackage: Decodable {
        let schemaVersion: Int
        let year: Int
        let records: [DayRecord]
    }

    private struct DayRecord: Decodable {
        let date: String
        let lunarYear: Int
        let lunarMonth: Int
        let lunarDay: Int
        let yearGanZhi: String
        let monthGanZhi: String
        let dayGanZhi: String
        let suitableActivities: [String]
        let unsuitableActivities: [String]
        let clashes: [String]
        let pengZu: [String]
        let hours: [AlmanacHour]
    }
}
