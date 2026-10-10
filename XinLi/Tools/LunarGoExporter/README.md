# lunar-go 离线黄历数据导出器

本工具把用户指定的 [6tail/lunar-go](https://github.com/6tail/lunar-go) 结果转换为心历随应用携带的年度资源。应用运行时只读取 JSON/LZFSE，不需要 Go、网络服务或动态生成黄历。

## 固定来源

- 模块：`github.com/6tail/lunar-go v1.4.6`
- 标签对应提交：`dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649`
- Go module / go.mod 校验和固定在 `go.sum` 与 `source-lock.json`。
- 许可：MIT，原文保留于 `vendor/github.com/6tail/lunar-go/LICENSE`，应用资源内另附 `LICENSE-lunar-go`。
- `vendor/` 是 `go mod vendor` 生成的未修改上游依赖代码。上游的 HolidayUtil 可能作为完整 Go 包的编译依赖存在，但本工具**不导出或替换法定假期/调休数据**。

这是一套传统民俗黄历口径，可核对其来源和实现，不等同于科学预测或官方行政日历。

## 完整重建

要求 macOS（Foundation LZFSE）、Swift / Xcode Command Line Tools、Go 1.22 或更高版本。

```sh
cd XinLi/Tools/LunarGoExporter
./regenerate.sh
```

生成器只使用 `vendor/`，脚本显式禁止 Go 代理和校验服务联网。输出：

- `generated/raw/1901.json` 至 `2099.json`：按日期排列的原始年度 UTF-8 JSON，中间文件已在本目录 `.gitignore` 中排除。
- `../../Sources/LunarCore/Resources/LunarGo/1901.json.lzfse` 至 `2099.json.lzfse`：应用使用的 LZFSE 年包。
- 资源目录内的 `manifest.json`：固定来源、口径、覆盖年、总日数、每年日数、字节长度、压缩文件及解压 JSON 的 SHA-256。

JSON 由 Go `encoding/json` 按明确结构字段顺序生成，紧凑编码并以 LF 结尾；日期枚举使用 UTC 公历日期而非机器本地时间。资源和 manifest 不含生成时间、绝对机器路径或随机值。压缩器使用 `NSData.compressed(using: .lzfse)`，并逐个文件解压回读、比对原字节。原始数据 SHA-256 可独立核验来源结果；压缩流再由其自身 SHA-256 核验。

可仅生成一年用于审查：

```sh
go run -mod=vendor . -start-year 2026 -end-year 2026 -out generated/sample-raw
swift compress.swift generated/sample-raw generated/sample-packed 2026 2026
```

## 字段与历法口径

年度外层固定为 `{schemaVersion:1, year:Int, records:[...]}`。公历覆盖 **1901-01-01 至 2099-12-31**，共 72,684 天。记录中农历年可能早于公历起始年，闰月用上游的负月份表达（如 `-6`、`-11`）。

| 字段 | 上游方法 / 规则 |
| --- | --- |
| `date` | `Solar.ToYmd()`，中国历法民用日期 |
| `lunarYear/Month/Day` | `GetYear/GetMonth/GetDay` |
| `yearGanZhi` | `GetYearInGanZhiByLiChun`，立春的日期边界 |
| `monthGanZhi` | `GetMonthInGanZhi`，节令日期边界 |
| `dayGanZhi` | `GetDayInGanZhi` |
| `suitableActivities` | `GetDayYiBySect(1)`（上游默认 sect=1） |
| `unsuitableActivities` | `GetDayJiBySect(1)` |
| `clashes` | `冲` + `GetDayChongDesc()`，`煞` + `GetDaySha()` |
| `pengZu` | `GetPengZuGan()`、`GetPengZuZhi()` |
| `hours` | 直接遍历 `GetTimes()` 的 13 项，保留原顺序 |

每个时段有 `branch`、`ganZhi`、`timeRange`、`heavenlySpirit`、`luck`、`suitableActivities`、`unsuitableActivities`、`clash`、`sha`。这些分别来自 `LunarTime.GetZhi/GetGanZhi/GetMinHm/GetMaxHm/GetTianShen/GetTianShenLuck/GetYi/GetJi/GetChongDesc/GetSha`；冲、煞添加了明确的中文显示前缀，其余文本和活动顺序按上游原样输出。

`timeRange` 使用 en dash（U+2013）。早子时 `00:00–00:59`、丑时 `01:00–02:59`……晚子时 `23:00–23:59`。早/晚子时绝不合并，晚子时干支与宜忌遵循上游 `GetTimes()` 的换日逻辑。每条日记录的干支/日宜忌在该公历日期 00:00 取值；时宜忌则使用各自上游时段结果。

## 数据完整性与历史验证

生成过程保留年度 JSON、压缩回读比对和 manifest 哈希；应用读取年包时继续检查覆盖范围、每日连续性、13 时段结构及压缩/解压 SHA-256。这些检查属于资源生成和运行时读取流程。

首次接入时曾运行固定版本上游测试与导出器测试，覆盖 2000 闰年日序、JSON 往返、确定性、2025 闰六月、2033 闰十一月及早晚子时；历史结果见 [验证记录](../../VALIDATION.md)。按用户要求，现已清理测试源码、测试日志和单独样本文件，`regenerate.sh` 仅负责生产资源再生成，不再执行测试或输出 `samples.json`。
