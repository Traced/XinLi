# 心历历法数据来源、精度与复现

核验日期：2026-10-09。全应用日期与时间显示使用同一个可配置时区；中国农历与传统黄历的源数据仍按中国历法解释。

本文中的测试结果属于历史核验记录。测试源码、测试脚本、独立样本及日志已按用户要求清理；生产历法实现、资源生成工具、运行时完整性检查与来源许可继续保留。

## 农历、闰月与月份大小

继续采用项目原有 `LunarCalendar`：Apple Foundation 的 Chinese Calendar（ICU），按北京时间的公历日期转换，并保留项目对已核验 ICU 边界情况的修正。此次升级没有用新的近似公式替换农历实现。

项目曾将 1921–2099 年结果与[香港天文台公历与农历对照表](https://www.hko.gov.hk/en/gts/time/conversion.htm)核对，并使用历法基准文件做跨系统版本回归检查；后续检查补充春节、2023 闰二月、2025 闰六月与大小月边界。相关测试文件和脚本现已移除，历史执行结果保留在 [VALIDATION.md](VALIDATION.md)。生产实现通过本农历月初一后的第 29 天是否已经进入下月计算大小月，因此闰月也独立处理。

干支保持原项目约定：生肖年以春节为界；日历年柱以立春日期为界，月柱以当月“节”的日期为界，日柱按连续日序。它们是日历层面的标记，不是按出生时刻排出的命理四柱，也不据此生成宜忌。

## 交节时刻：仅 2025–2027 年

客户端内置 72 个自行计算的交节时刻。数值由 [Astronomy Engine](https://github.com/cosinekitty/astronomy) 的 `SearchSunLongitude` 求解太阳地心视黄经每增加 15° 的时刻，小寒从 285° 起算。该实现基于截断 VSOP87，包含岁差、章动和光行时处理，其作者提供了与 NOVAS/JPL Horizons 的验证；它不是本项目临时拼出的经验多项式。

- 固定源码提交：`865d3da7d8112bbc7911238052c6af4aaf877181`
- Python 源码 SHA-256：`41248c7b1edbf9d11119528eef7455a6dc55abde9f1aab40d363015e956c1729`
- 原项目许可：MIT；全文在 `Resources/Calendar/ASTRONOMY-ENGINE-LICENSE.txt`。
- 自生成数值、来源标识和核验统计：`Resources/Calendar/solar-terms-computed-2025-2027.json`。
- 客户端离线表：`Sources/LunarCore/SolarTermComputedData.swift`；没有运行时网络或 Python 依赖。

每个数值都与[香港天文台二十四节气时刻](https://www.hko.gov.hk/en/gts/astronomy/Solar_Term.htm)的官方机器 XML 表独立比较（该表使用香港时间 UTC+8）：

| 年份 | 比较数量 | 与官方分钟值的最大绝对差 | 平均绝对差 |
| --- | ---: | ---: | ---: |
| 2025 | 24 | 43.23 秒 | 18.15 秒 |
| 2026 | 24 | 59.46 秒 | 21.00 秒 |
| 2027 | 24 | 42.20 秒 | 20.54 秒 |

2026 年春分、夏至、秋分、冬至还与 [USNO Seasons API](https://aa.usno.navy.mil/api/seasons?year=2026)交叉比较，最大差约 60.32 秒。HKO 与 USNO 的 2026 夏至公布分钟值本身相差一分钟。这些比较只说明与相应分钟表的差异，不构成物理真值的秒级准确度保证。

UI 将时刻四舍五入显示到分钟并加“约”，说明“2025–2027 与香港天文台分钟表核验差 < 1 分钟”。内部秒数只为交节排序和时区转换，不能解读为秒级精度。选中今天时按当前时刻判断上一/下一节气，选中其他日期时按当地中午参考，并在界面说明。

**2024 年及以前、2028 年及以后不提供交节时刻。** 这些年份继续使用原有 1900–2100 年节气日期表，`instant` 返回 `nil`，UI 显示“仅日期（北京）”，绝不把午夜或近似时刻伪装成精确交节。没有时刻的数据无法作真实的跨时区瞬间转换，因此日期仍明确按北京时间显示。下一节气跨越验证范围时也保留这个限制。

### 复现

在 `XinLi` 目录执行：

```sh
python3 Resources/Calendar/generate-solar-terms.py
```

脚本只需 Python 标准库，会下载固定提交的 Astronomy Engine，先校验 SHA-256，再计算 72 个时刻并临时读取 HKO 参考表；若任何差异达到 60 秒即失败。随后生成 JSON 和 Swift 查询表。参考 XML 只用于核验，不随产品打包；JSON 保留参考 URL、内容哈希和统计值，供上游表修订时追溯。

HKO 页面注明数据基于 HM Nautical Almanac Office 和 USNO；其[网站非商业使用条款](https://www.hko.gov.hk/en/appweb/applink.htm)与[刊物商业使用条件](https://www.hko.gov.hk/en/publica/commercialuse.htm)不能当作允许任意商业再分发的通用开源许可。因此本次没有复制整套官方时刻表为产品数据；分发的是使用 MIT 实现产生的计算结果。核验并不意味着这些机构认可本应用。

## 假期与调休

继续读取项目现有 `holidays.json`，其中 `sources` 保存国务院通知链接，`version` 是数据版本。UI 根据实际载入的记录列出年份和明确放假/调休条目；一个年份没有记录时显示“暂无已载入的假期安排”，不能把周末、传统节日或另一年的规律外推为法定假期。`HolidayCoverage` 保留年份空档，不把最早至最晚年份之间的缺失年份自动视为覆盖。

### 已核验的内置覆盖与公告

此次逐项检查 `docs/data/holidays.json` 的 **2020–2026** 年安排，覆盖 234 条独立日期记录：188 条放假记录和 46 条调休上班记录。其余普通周末由日历周末规则处理；旧数据对部分连休假期省略了周末条目，因此“放假记录条数”不等于官方连续假期总天数。记录最早为 2020-01-01，最晚为 2026-10-10；未内置 2027 年及以后安排。

| 年份 | 放假记录 | 调休上班记录 | 核对的正式公告 |
| --- | ---: | ---: | --- |
| 2020 | 20 | 6 | [2020 年安排，国办发明电〔2019〕16号](https://app.www.gov.cn/govdata/gov/201911/21/451111/article.html)，以及[春节假期延长通知，国办发明电〔2020〕1号](https://app.www.gov.cn/govdata/gov/202001/27/453442/article.html) |
| 2021 | 27 | 7 | [2021 年安排，国办发明电〔2020〕27号](https://app.www.gov.cn/govdata/gov/202011/25/465322/article.html) |
| 2022 | 32 | 7 | [2022 年安排，国办发明电〔2021〕11号](https://app.www.gov.cn/govdata/gov/202110/25/477428/article.html)；12 月 31 日来自 2023 年元旦公告 |
| 2023 | 26 | 7 | [2023 年安排，国办发明电〔2022〕16号](https://app.www.gov.cn/govdata/gov/202212/08/495070/article.html) |
| 2024 | 28 | 8 | [2024 年安排，国办发明电〔2023〕7号](https://www.gov.cn/zhengce/content/202310/content_6911527.htm?version=zzzq) |
| 2025 | 28 | 5 | [2025 年安排，国办发明电〔2024〕12号](https://big5.www.gov.cn/gate/big5/www.gov.cn/zhengce/zhengceku/202411/content_6986383.htm) |
| 2026 | 27 | 6 | [2026 年安排](https://big5.www.gov.cn/gate/big5/www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm) |

核验发现并修正了旧数据中的一处冲突：**2020-02-01 应休假，不能继续标为调休上班。** 2019 年发布的原安排将其列为补班日，但 2020-01-26 成文的春节延长通知已把假期延至 2 月 2 日、2 月 3 日起正常上班；后发布的专项通知优先。内置数据版本提升为 `20261010`，保留上述原始与修订来源。

清理前的假期来源测试使用从上述正式公告独立整理的放假范围和补班日期，核验了 2020–2026 每一天的休息/工作判断，以及全部 46 个补班日期与公告的一致性。核验允许省略普通周末记录，但不允许把假期标为上班、漏掉工作日放假，或平空增加放假日；也覆盖了 2020 年专项延长通知对原补班日的覆盖。对应测试源码现已清理，正式来源和生产假期数据保留。

## 传统黄历：lunar-go 离线数据

宜忌、冲煞、彭祖百忌和时辰条目接入 [6tail/lunar-go](https://github.com/6tail/lunar-go) 的 **v1.4.6**，固定提交 [`dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649`](https://github.com/6tail/lunar-go/tree/dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649)。原项目采用 [MIT License](https://github.com/6tail/lunar-go/blob/dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649/LICENSE)，版权为 Copyright (c) 2020 6tail；生成工具保留上游源码和许可，应用资源也保留来源与许可信息。

这部分是该开源项目定义的**传统民俗黄历口径**，不是天文台、国务院或其他机构发布的官方标准，也不代表对吉凶预测的科学验证。宜忌之间可能存在不同流派的口径差异；应用按固定上游版本原样展示，不使用随机规则补造内容。上游返回的“无”等值按原文保留。

- 离线覆盖公历 **1901-01-01 至 2099-12-31**。`Sources/LunarCore/Resources/LunarGo/` 按年保存 LZFSE 压缩 JSON；`LunarGoAlmanacProvider` 按选中的 `SolarDate` 查询，不通过设备当前时区改变黄历日期。
- 时辰源数据按所选公历日的 UTC+8 中国历法解释，界面换算至应用时区，跨日或跨年注明日期。每一天保留 **13 个源时段**：`00:00–00:59` 子时、`01:00–02:59` 丑时，依次到 `21:00–22:59` 亥时，再到 `23:00–23:59` 子时。两个子时属于当日不同位置，可能有不同干支和宜忌，不能合并成一条 `23:00–00:59`。转换只影响显示，不改源数据或吉凶条目。
- 每个时段包含干支、天神、吉凶、宜忌、冲与煞；年/月/日干支和彭祖百忌使用同一上游记录。年柱采用 `GetYearInGanZhiByLiChun`（立春日期边界），月柱采用 `GetMonthInGanZhi`，日宜忌采用上游默认 `GetDayYiBySect(1)` / `GetDayJiBySect(1)`。冲、煞添加中文显示前缀，其余活动文字及顺序保留。界面把这些黄历字段与原有历法字段区分，不反向覆盖原有农历、生肖、节气计算。
- 非法日期、覆盖范围外日期、缺失或损坏资源明确返回不可用，不改查相邻日期、不联网兜底，也不虚构内容。
- 资源随 SwiftPM 及 Xcode 应用打包，运行时只需 Swift/Foundation。**正常构建与运行不需要 Go**；Go 仅用于 `Tools/LunarGoExporter/` 中的离线数据再生成工具。

此接入只增加传统黄历提供者。原有 Foundation/ICU 农历、经独立核验的 Astronomy Engine 交节时刻，以及国务院正式假期数据继续使用原实现与来源。lunar-go 中的其他历法或节假日接口没有替换这些模块；其节气能力也不会扩大本应用已核验交节时刻的 2025–2027 年范围。

接入时曾使用上游固定宜忌样本检查导出与解码，另核验关键历法日期、两个子时、年度边界、缺损资源及并发查询。这些历史检查验证本应用与固定上游版本的数据一致性，不构成对民俗吉凶本身的实证认证；对应测试源码现已清理。

### 再生成与追溯

在 macOS 上安装 Go 1.22+ 和 Swift/Xcode Command Line Tools 后执行：

```sh
cd XinLi/Tools/LunarGoExporter
./regenerate.sh
```

脚本使用已入库的 `vendor/` 并禁止 Go 网络下载，重新生成全部 **199 年、72,684 天**数据。`source-lock.json` 固定模块来源和校验和；应用资源内 `manifest.json` 保存来源版本、每年记录数，以及压缩文件和原始 JSON 的 SHA-256。客户端在读取年份时校验两个哈希、逐日连续性和 13 时段结构，避免损坏文件显示为正常黄历。再生成流程不再执行测试或输出独立测试样本；完整字段映射与复现步骤见 [导出工具说明](Tools/LunarGoExporter/README.md)。

原 MIT 许可分别保留在 `Tools/LunarGoExporter/vendor/github.com/6tail/lunar-go/LICENSE` 和随应用打包的 `Sources/LunarCore/Resources/LunarGo/LICENSE-lunar-go`。
