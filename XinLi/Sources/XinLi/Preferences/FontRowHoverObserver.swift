import AppKit
import SwiftUI

/// A transparent row-sized observer. Native clip notifications also recompute
/// hover when scrolling moves a different row under a stationary pointer.
@MainActor
struct FontRowHoverObserver: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> FontRowHoverTrackingView {
        FontRowHoverTrackingView(onHover: onHover)
    }

    func updateNSView(_ view: FontRowHoverTrackingView, context: Context) {
        view.onHover = onHover
        view.scheduleHoverUpdate()
    }

    static func dismantleNSView(_ view: FontRowHoverTrackingView, coordinator: ()) {
        view.invalidate()
    }
}

extension View {
    func fontRowHover(_ onHover: @escaping (Bool) -> Void) -> some View {
        background(FontRowHoverObserver(onHover: onHover).accessibilityHidden(true))
    }
}

@MainActor
final class FontRowHoverTrackingView: NSView {
    var onHover: (Bool) -> Void
    private let pointerLocation: (NSWindow) -> NSPoint
    private var rowTrackingArea: NSTrackingArea?
    private var observedClips: [WeakClip] = []
    private weak var observedWindow: NSWindow?
    private var isObserving = false
    private var isHovered = false
    private var updateIsScheduled = false
    private var isInvalidated = false

    init(onHover: @escaping (Bool) -> Void,
         pointerLocation: @escaping (NSWindow) -> NSPoint = { $0.mouseLocationOutsideOfEventStream }) {
        self.onHover = onHover
        self.pointerLocation = pointerLocation
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("Created programmatically") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    // Tracking areas do not require taking the button's hit test. Returning nil
    // preserves both native button clicks and the enclosing scroll view's wheel.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        reconnectObserversIfNeeded()
        scheduleHoverUpdate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reconnectObserversIfNeeded()
        scheduleHoverUpdate()
    }

    override func layout() {
        super.layout()
        reconnectObserversIfNeeded()
        scheduleHoverUpdate()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowTrackingArea { removeTrackingArea(rowTrackingArea) }
        rowTrackingArea = nil
        guard !isInvalidated else { return }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        rowTrackingArea = area
        reconnectObserversIfNeeded()
        scheduleHoverUpdate()
    }

    override func mouseEntered(with event: NSEvent) { scheduleHoverUpdate() }
    override func mouseExited(with event: NSEvent) { scheduleHoverUpdate() }

    /// Exposed internally so native tests can validate real NSClipView clipping
    /// with an injected window point, without moving the user's global cursor.
    func containsVisiblePoint(_ pointInWindow: NSPoint) -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return false }
        let point = convert(pointInWindow, from: nil)
        return bounds.contains(point) && visibleRect.contains(point)
    }

    func scheduleHoverUpdate() {
        guard !isInvalidated, !updateIsScheduled else { return }
        updateIsScheduled = true
        // Geometry callbacks can occur during a SwiftUI update. Coalescing onto
        // the next main-loop turn avoids mutating preview state during layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateIsScheduled = false
            guard !self.isInvalidated else { return }
            self.reconnectObserversIfNeeded()
            let inside: Bool
            if let window = self.window, window.isVisible, NSApplication.shared.isActive {
                // Deliberately do not require isKeyWindow: accessory popovers
                // and nonactivating panels can still receive hover while active.
                inside = self.containsVisiblePoint(self.pointerLocation(window))
            } else {
                inside = false
            }
            guard inside != self.isHovered else { return }
            self.isHovered = inside
            self.onHover(inside)
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        NotificationCenter.default.removeObserver(self)
        observedClips = []
        observedWindow = nil
        isObserving = false
        if let rowTrackingArea { removeTrackingArea(rowTrackingArea) }
        rowTrackingArea = nil
        if isHovered {
            isHovered = false
            let callback = onHover
            DispatchQueue.main.async { callback(false) }
        }
        onHover = { _ in }
    }

    private func reconnectObserversIfNeeded() {
        guard !isInvalidated else { return }
        var clips: [NSClipView] = []
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView { clips.append(clip) }
            ancestor = view.superview
        }
        let previous = observedClips.compactMap(\.view).map(ObjectIdentifier.init)
        guard !isObserving || observedWindow !== window || previous != clips.map(ObjectIdentifier.init) else { return }
        let center = NotificationCenter.default
        center.removeObserver(self)
        observedClips = clips.map(WeakClip.init)
        observedWindow = window
        isObserving = window != nil
        guard let window else { return }
        for clip in clips {
            clip.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(observedGeometryChanged),
                               name: NSView.boundsDidChangeNotification, object: clip)
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(observedGeometryChanged), name: name, object: window)
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            center.addObserver(self, selector: #selector(observedGeometryChanged), name: name, object: nil)
        }
    }

    @objc private func observedGeometryChanged(_ notification: Notification) { scheduleHoverUpdate() }

    private final class WeakClip {
        weak var view: NSClipView?
        init(_ view: NSClipView) { self.view = view }
    }
}
