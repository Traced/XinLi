# 心历资源说明

## 应用代码许可

源码仓库根目录 `LICENSE` 原文随 SwiftPM / Xcode 构建复制到 `Contents/Resources/LICENSE`，保留 MIT 条款及上游版权记录。应用的公开联系信息为「公众号：随心记事」。

## 内置风景

这两幅原创合成风景于本次开发中通过 OpenAI 内置 imagegen 工具生成，没有下载或描摹指定摄影师的作品，不声称是某一真实地点的实拍照片。输出作为本项目的离线资源分发；代码仓库 MIT License 的权利授予仅限项目方实际拥有的权利，不对 AI 输出的独占版权作保证。

- `Sources/XinLi/Resources/snow-sunset.jpg`
- `Sources/XinLi/Resources/forest-lake.jpg`

使用内置工具而非 API/CLI fallback。PNG 原始输出转为 JPEG 打包，没有运行时网络依赖。

### 雪山日落的完整提示词

> Use case: photorealistic-natural. Asset type: offline scenic header background for a refined native macOS calendar app. Generate an original wide panoramic photograph-style landscape of majestic snow-covered alpine mountains above a still lake at sunset. Soft peach sunlight on the peaks, quiet slate blue shadows, pale warm sky, clean natural detail, calm spacious composition. A high-quality photographic landscape only, no UI, no text, no logos, no watermark. Wide 3:1 composition suitable for a 580 by 165 point header. Save the generated image as an asset.

### 晨雾森林的完整提示词

> Use case: photorealistic-natural. Asset type: offline scenic header for native macOS calendar. Original wide panorama photograph-style of a serene forest lake at early morning: layered pine forest, soft mist over still teal water, distant mountains, gentle warm sunrise filtering through pale sky. Refined quiet natural colors, realistic detail. 3:1 wide composition, no text, no UI, no logo, no watermark.

## 可选 Bing 在线风景

选择 Bing 来源或点击换图时，应用从 Bing 首页图片档案读取近期图片；只选择 `wp: true` 的可下载条目，并保留接口提供的版权文字与来源链接。图片原版权属于相应摄影师或授权方，不适用本项目的 MIT 许可。下载的图片仅保存在用户的运行时缓存中，不作为应用资源分发。

微软说明每日图片的下载与授权可能因图片而异：[Explore the Bing homepage](https://support.microsoft.com/en-us/bing/explore-the-homepage)。内置离线风景和用户自选本地图片均可独立使用。

## 图标

「心历」图标由 `scripts/generate-icon.swift` 使用原创 AppKit 路径与渐变生成：浅色日历页、珊瑚红心形与淡蓝紫底色。没有使用第三方位图、图标或字体。保留可编辑生成脚本、1024 像素预览 `Resources/HeartCalendarIcon.png`，及完整多尺寸资源 `Resources/ChronoCalIcon.icns`（内部资源名为兼容旧工程而保留）。旧项目 AppIcon 仍保留，新增图标随项目 MIT 许可使用。

界面功能图标使用 macOS SF Symbols 系统 API，没有打包第三方图标字体。

## 历法数据

见 [DATA-SOURCES.md](DATA-SOURCES.md)。Astronomy Engine 的 MIT 许可全文随 `Resources/Calendar/ASTRONOMY-ENGINE-LICENSE.txt` 保留。

传统黄历资源由 [6tail/lunar-go v1.4.6](https://github.com/6tail/lunar-go/tree/v1.4.6) 生成，固定提交 `dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649`，原项目版权为 Copyright (c) 2020 6tail，采用 [MIT License](https://github.com/6tail/lunar-go/blob/dd82a5bc13f4e08417cb78b58f7a7fd90c1fd649/LICENSE)。上游源码及许可在 `Tools/LunarGoExporter/` 保留；`Sources/LunarCore/Resources/LunarGo/` 中的 1901–2099 年压缩黄历数据和许可随应用离线分发。该许可说明软件与数据的复用来源，不表示其中民俗宜忌属于官方标准。
