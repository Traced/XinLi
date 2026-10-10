import Foundation

/// 与 AppKit 无关的月份滑动判定。位移使用屏幕方向：向左为负，向右为正。
struct MonthSwipeTracker {
    enum Phase {
        case began, changed, ended, cancelled, unphased
    }

    private enum Axis {
        case horizontal, vertical
    }

    private static let threshold = 60.0
    private static let axisThreshold = 12.0
    private static let axisRatio = 1.5
    private static let wheelIdleInterval = 0.3

    private var horizontal = 0.0
    private var vertical = 0.0
    private var axis: Axis?
    private var triggered = false
    private var trackingPhasedGesture = false
    private var lastWheelTimestamp: TimeInterval?

    var isHorizontal: Bool { axis == .horizontal }

    mutating func reset() {
        self = Self()
    }

    /// 一次物理手势最多返回一个月份增量；忽略释放手指后的惯性滚动。
    mutating func scroll(horizontal dx: Double, vertical dy: Double, phase: Phase,
                         isMomentum: Bool, timestamp: TimeInterval) -> Int? {
        guard !isMomentum else { return nil }

        switch phase {
        case .began:
            reset()
            trackingPhasedGesture = true
        case .changed, .ended:
            // 不接管从日历区域外开始的手势。
            guard trackingPhasedGesture else { return nil }
        case .cancelled:
            reset()
            return nil
        case .unphased:
            // 传统鼠标不提供阶段信息，以事件间隔区分独立的滚动动作。
            if trackingPhasedGesture || lastWheelTimestamp.map({
                timestamp - $0 > Self.wheelIdleInterval || timestamp < $0
            }) ?? true {
                reset()
            }
            lastWheelTimestamp = timestamp
        }

        defer {
            if phase == .ended { reset() }
        }

        horizontal += dx
        vertical += dy
        if axis == nil {
            if abs(horizontal) >= Self.axisThreshold && abs(horizontal) > abs(vertical) * Self.axisRatio {
                axis = .horizontal
            } else if abs(vertical) >= Self.axisThreshold && abs(vertical) > abs(horizontal) * Self.axisRatio {
                axis = .vertical
            }
        }

        guard !triggered, axis == .horizontal,
              let delta = Self.monthDelta(horizontal: horizontal, vertical: vertical) else { return nil }
        triggered = true
        return delta
    }

    /// 鼠标拖动在松开时判定，轻点、短距离移动和竖向拖动不会翻月。
    static func monthDelta(horizontal: Double, vertical: Double) -> Int? {
        guard abs(horizontal) >= threshold, abs(horizontal) > abs(vertical) * axisRatio else { return nil }
        return horizontal < 0 ? 1 : -1
    }
}
