/// Where the selected built-in, Bing, or local image appears in the popover.
enum BackgroundImageScope: String, CaseIterable, Identifiable, Sendable {
    case header, content, window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .header: "仅顶部横幅"
        case .content: "内容区域"
        case .window: "整个浮窗"
        }
    }
}
