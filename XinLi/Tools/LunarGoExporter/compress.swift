#!/usr/bin/swift
import CryptoKit
import Foundation

// Foundation's LZFSE codec matches the app's NSData.decompressed(using: .lzfse).
// Avoid timestamps and machine paths in the manifest so artifacts are reproducible.
let arguments = CommandLine.arguments
let rawDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "generated/raw", isDirectory: true)
let outputDirectory = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "../../Sources/LunarCore/Resources/LunarGo", isDirectory: true)
let firstYear = arguments.count > 3 ? Int(arguments[3])! : 1901
let lastYear = arguments.count > 4 ? Int(arguments[4])! : 2099
let expectedCommit = "dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649"
guard firstYear >= 1901, lastYear <= 2099, firstYear <= lastYear else { fatalError("Invalid supported range") }
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
var entries: [[String: Any]] = []
var total = 0
var rawBytes = 0
var compressedBytes = 0
for year in firstYear...lastYear {
    try autoreleasepool {
        let raw = try Data(contentsOf: rawDirectory.appendingPathComponent("\(year).json"))
        guard let content = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              content["schemaVersion"] as? Int == 1,
              content["year"] as? Int == year,
              let records = content["records"] as? [[String: Any]] else { fatalError("Invalid annual document \(year)") }
        let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        guard records.count == (leap ? 366 : 365),
              records.first?["date"] as? String == "\(year)-01-01",
              records.last?["date"] as? String == "\(year)-12-31",
              records.allSatisfy({ ($0["hours"] as? [[String: Any]])?.count == 13 }) else { fatalError("Incomplete dates/hours \(year)") }
        let compressed = try (raw as NSData).compressed(using: .lzfse) as Data
        let restored = try (compressed as NSData).decompressed(using: .lzfse) as Data
        guard restored == raw else { fatalError("LZFSE round-trip failed for \(year)") }
        let file = "\(year).json.lzfse"
        try compressed.write(to: outputDirectory.appendingPathComponent(file), options: .atomic)
        entries.append(["year": year, "recordCount": records.count, "file": file,
                        "sha256": hash(compressed), "uncompressedSHA256": hash(raw),
                        "uncompressedBytes": raw.count, "compressedBytes": compressed.count])
        total += records.count; rawBytes += raw.count; compressedBytes += compressed.count
    }
}
let manifest: [String: Any] = [
    "schemaVersion": 1,
    "source": ["repository": "https://github.com/6tail/lunar-go", "version": "v1.4.6",
               "commit": expectedCommit, "license": "MIT"],
    "startYear": firstYear, "endYear": lastYear, "recordCount": total,
    "years": entries,
    "dayYiJiSect": 1,
    "civilDateConvention": "China calendar civil dates (Asia/Shanghai); upstream NewSolarFromYmd at 00:00",
    "ganZhiConvention": ["year": "GetYearInGanZhiByLiChun (Li Chun civil-date boundary)",
                         "month": "GetMonthInGanZhi (civil-date solar-term boundary)",
                         "day": "GetDayInGanZhi",
                         "hours": "GetTimes; original 13 segments including separate early/late Zi"],
    "compression": "Apple Foundation NSData LZFSE",
    "rawEncoding": "UTF-8 compact Go encoding/json followed by LF",
    "licenseFile": "LICENSE-lunar-go",
    "licenseURL": "https://github.com/6tail/lunar-go/blob/\(expectedCommit)/LICENSE",
    "uncompressedBytes": rawBytes, "compressedBytes": compressedBytes,
    "notice": "Traditional cultural almanac data; not a scientific forecast. Official public-holiday datasets are not exported or replaced."
]
var serialized = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
serialized.append(10)
try serialized.write(to: outputDirectory.appendingPathComponent("manifest.json"), options: .atomic)
print("Compressed \(entries.count) years / \(total) dates: \(rawBytes) → \(compressedBytes) bytes")
