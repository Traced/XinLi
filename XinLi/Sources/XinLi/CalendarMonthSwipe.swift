import AppKit
import SwiftUI

/// 同时支持普通鼠标按住拖动、Magic Mouse 与触控板横向滑动。
struct CalendarMonthSwipeModifier: ViewModifier {
    let onMove: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if let delta = MonthSwipeTracker.monthDelta(
                            horizontal: Double(value.translation.width),
                            vertical: Double(value.translation.height)
                        ) {
                            onMove(delta)
                        }
                    }
            )
            .background(CalendarScrollMonitor(onMove: onMove))
    }
}

private struct CalendarScrollMonitor: NSViewRepresentable {
    var onMove: (Int) -> Void

    func makeNSView(context: Context) -> ScrollMonitorView {
        let view = ScrollMonitorView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: ScrollMonitorView, context: Context) {
        view.onMove = onMove
    }

    static func dismantleNSView(_ view: ScrollMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class ScrollMonitorView: NSView {
    var onMove: ((Int) -> Void)?
    private var monitor: Any?
    private var tracker = MonthSwipeTracker()

    // 这里只观察滚动，不挡住 SwiftUI 日期格的点击或拖动。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        tracker.reset()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, window.isVisible,
              !isHiddenOrHasHiddenAncestor,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            tracker.reset()
            return event
        }

        let phase: MonthSwipeTracker.Phase
        if event.phase.contains(.cancelled) {
            phase = .cancelled
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) {
            phase = .ended
        } else if event.phase.isEmpty {
            phase = .unphased
        } else {
            phase = .changed
        }

        // 还原手指的移动方向，使“左滑下月”不受系统自然滚动选项影响。
        let direction = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        let wasHorizontal = tracker.isHorizontal
        let delta = tracker.scroll(
            horizontal: Double(event.scrollingDeltaX) * direction * scale,
            vertical: Double(event.scrollingDeltaY) * direction * scale,
            phase: phase,
            isMomentum: !event.momentumPhase.isEmpty,
            timestamp: event.timestamp
        )
        if let delta { onMove?(delta) }
        return wasHorizontal || tracker.isHorizontal || delta != nil ? nil : event
    }
}
