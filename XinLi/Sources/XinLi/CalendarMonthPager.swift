import LunarCore
import SwiftUI

/// 保留前后两个月的网格，按翻月方向滑动；快速输入只合并尚未开始的翻页。
struct CalendarMonthPager<Content: View>: View {
    @ObservedObject var model: CalendarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let size: CGSize
    let animationsEnabled: Bool
    let content: (MonthGrid) -> Content

    @State private var displayed: MonthGrid
    @State private var outgoing: MonthGrid?
    @State private var pending: MonthGrid?
    @State private var progress: CGFloat = 1
    @State private var direction: CGFloat = 1
    @State private var animationTask: Task<Void, Never>?

    init(model: CalendarViewModel, size: CGSize, animationsEnabled: Bool = true,
         @ViewBuilder content: @escaping (MonthGrid) -> Content) {
        self.model = model
        self.size = size
        self.animationsEnabled = animationsEnabled
        self.content = content
        _displayed = State(initialValue: model.grid)
    }

    var body: some View {
        ZStack {
            if let outgoing {
                content(outgoing)
                    .offset(x: -direction * size.width * progress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content(displayed)
                .offset(x: direction * size.width * (1 - progress))
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(outgoing == nil)
        // grid 一次发布完整年月，跨年时也只触发一次翻页。
        .onReceive(model.$grid) { update($0) }
        .onAppear { reset() }
        .onChange(of: reduceMotion) { _, _ in reset() }
        .onChange(of: animationsEnabled) { _, _ in reset() }
        .onChange(of: size) { _, _ in reset() }
        .onDisappear { reset() }
    }

    private func update(_ grid: MonthGrid) {
        guard !reduceMotion && animationsEnabled else {
            reset(to: grid)
            return
        }
        if outgoing != nil {
            pending = grid
            return
        }
        let oldIndex = displayed.year * 12 + displayed.month
        let newIndex = grid.year * 12 + grid.month
        guard oldIndex != newIndex else {
            displayed = grid
            return
        }

        withoutAnimation {
            direction = newIndex > oldIndex ? 1 : -1
            outgoing = displayed
            displayed = grid
            progress = 0
        }
        animationTask = Task { @MainActor in
            // 先提交两页的起始位置，再开始动画，避免同一轮更新直接跳到终点。
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) { progress = 1 }
            do { try await Task.sleep(nanoseconds: 240_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            let next = pending
            withoutAnimation {
                outgoing = nil
                pending = nil
                animationTask = nil
            }
            if let next { update(next) }
        }
    }

    private func reset(to grid: MonthGrid? = nil) {
        animationTask?.cancel()
        withoutAnimation {
            animationTask = nil
            outgoing = nil
            pending = nil
            displayed = grid ?? model.grid
            progress = 1
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }
}
