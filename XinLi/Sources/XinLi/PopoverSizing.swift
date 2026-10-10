import AppKit
import SwiftUI

/// SwiftUI measures the scroll document, while this coordinator explicitly
/// resizes its AppKit container. Preferred content size alone does not keep an
/// already presented NSPopover in sync when the document becomes shorter.
@MainActor
final class PopoverSizingCoordinator: ObservableObject {
    @Published private(set) var viewportSize = CGSize(width: 580, height: 760)
    private(set) var measuredSize: CGSize = .zero
    private(set) var maximumHeight: CGFloat = 850
    private weak var popover: NSPopover?
    private var pendingSize: CGSize?
    private var updateScheduled = false

    func attach(to popover: NSPopover) {
        self.popover = popover
        popover.contentSize = viewportSize
    }

    func setMaximumHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        maximumHeight = height
        enqueue(pendingSize ?? (measuredSize == .zero ? viewportSize : measuredSize))
    }

    func measure(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        enqueue(size)
    }

    private func enqueue(_ size: CGSize) {
        pendingSize = size
        guard !updateScheduled else { return }
        updateScheduled = true
        // Leave SwiftUI's layout pass before publishing state or
        // changing the native window. Keep the most recent measurement only.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            guard let size = self.pendingSize else { return }
            self.pendingSize = nil
            self.measuredSize = size
            let target = CGSize(width: ceil(size.width), height: min(ceil(size.height), self.maximumHeight))
            // Page transitions animate their contents, not the measured
            // viewport. AppKit otherwise animates contentSize too, allowing
            // its window and SwiftUI's scroll view to move at different rates.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if self.viewportSize != target { self.viewportSize = target }
                if let popover = self.popover, popover.contentSize != target {
                    let animates = popover.animates
                    popover.animates = false
                    popover.contentSize = target
                    popover.animates = animates
                }
            }
        }
    }
}

@MainActor
struct AdaptivePopoverContent<Content: View>: View {
    @ObservedObject var sizing: PopoverSizingCoordinator
    @ObservedObject var preferences: AppPreferences = .shared
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, size in
                        sizing.measure(size)
                    }
                })
        }
        .scrollIndicators(preferences.showsScrollIndicators ? .automatic : .hidden)
        .frame(width: width, height: sizing.viewportSize.height, alignment: .top)
        .background(.regularMaterial)
    }
}
