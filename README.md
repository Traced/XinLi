# 心历 · XinLi

原生 macOS 状态栏日历，集成中国农历、节气、黄历、日程与任务。

公众号：**随心记事**。

## 功能

- 菜单栏日期时间自由组合，全应用统一时区，中文星期显示为“周几”。
- 风景、迷你和极简模式，毛玻璃卡片、多套配色、自定义字体与字号。
- 月历支持鼠标横向滑动和切换动画，浮窗高度随内容调整。
- 农历闰月、干支生肖、节气、节日与已载入年份的法定假期。
- lunar-go 1901–2099 年离线黄历，包含宜忌、冲煞和完整时辰。
- 本地日程、重复事件与任务；可选连接系统 Apple 日历，支持提醒通知。
- 内置风景、本地图片和可选 Bing 风景；日历及黄历不依赖联网。

## 开始开发

推荐使用 Xcode 26.1.1（Swift 6.2.1），与本机已验证和 GitHub Actions 固定的工具链保持一致。Xcode 16.4 的 Swift 6.1.2 在 Release 编译时存在编译器崩溃，暂不支持该工具链。应用最低运行版本仍为 macOS 14。

1. 克隆或完整下载这个仓库，保留目录结构。
2. 打开 `XinLi/XinLi.xcodeproj`。
3. 选择 `XinLi` scheme 和 `My Mac`，按 ⌘R。
4. 应用出现在顶部菜单栏，点击日期打开浮窗，右键打开设置。

命令行构建：

```sh
cd XinLi
./scripts/build-app.sh universal
```

输出在 `XinLi/build/`，包括 `心历.app` 和同版本 ZIP、DMG。可用 `arm64` 或 `x86_64` 替换 `universal`，仅编译相应架构。

本地构建默认采用临时签名。当前自动构建流程未配置 Developer ID 签名或 Apple 公证；本机编译成功不代表下载后的应用能通过另一台 Mac 的安全检查。正式分发需使用自己的 Developer ID 签名并完成公证。

## 工程结构

```text
XinLi/
  XinLi.xcodeproj/         Xcode 工程与共享 scheme
  Package.swift           Swift Package 配置
  Sources/XinLi/           状态栏、界面、设置、日程与任务
  Sources/LunarCore/       历法引擎与离线黄历资源
  Resources/              图标、权限、节气资源和安装说明
  scripts/                构建、打包与资源生成工具
  Tools/LunarGoExporter/   固定版本 lunar-go 源码及数据导出工具
docs/data/holidays.json    法定假期与调休数据
LICENSE                   项目许可
```

`docs/data/holidays.json` 和 `LICENSE` 是构建依赖，必须与 `XinLi/` 保持上述相对位置。普通构建无需安装 Go，黄历资源已包含在源码中。

## 数据与许可

本项目基于 [zfdang/chinese-lunar-calendar-for-mac](https://github.com/zfdang/chinese-lunar-calendar-for-mac) 的 Swift 实现升级，保留根目录 [MIT LICENSE](LICENSE) 及原版权声明。黄历使用 [6tail/lunar-go](https://github.com/6tail/lunar-go) 的固定版本数据，相关源码和 MIT 许可随仓库保留。

- [完整功能、设置和权限说明](XinLi/README.md)
- [数据来源及覆盖范围](XinLi/DATA-SOURCES.md)
- [图片、图标及第三方资源许可](XinLi/ASSET-LICENSES.md)
- [历史验证记录与未完成验收项](XinLi/VALIDATION.md)

黄历宜忌属于民俗参考。法定假期仅展示已载入的年份安排；不会根据节日名称推算调休。Bing 下载图片保存在用户本地缓存，不随源码分发。

## 协作与构建

通过分支和 Pull Request 协作。源代码仓库不包含安装包、构建缓存、Xcode 个人配置或用户日程数据。

GitHub Actions 在推送 `main` 或相关 Pull Request 时构建，也可手动运行；推送 `v1`、`v1.2.3` 等数字版本标签可生成 ZIP、DMG 并发布 GitHub Release。自动构建不包含开发者签名、公证或已移除的正式测试套件。

`scripts/publish-website.sh` 是原仓库的网站维护工具，依赖原网站文件及 GitHub 配置，不属于当前独立仓库的应用构建流程。
