import LunarCore
import SwiftUI

/// Cached dates render in the same layout pass as the selection. When a new
/// year must be decoded, retain the previous section's space without showing
/// the previous date's record under the new date heading.
@MainActor
struct AlmanacRecordContent<Content: View>: View {
    @Environment(\.chronoTheme) private var theme
    let date: SolarDate
    var minimumLoadingHeight: CGFloat = 50
    @ViewBuilder let content: (AlmanacAvailability) -> Content

    @State private var loadedDate: SolarDate?
    @State private var loadedRecord: AlmanacAvailability?
    @State private var lastContentHeight: CGFloat = 0

    private var record: AlmanacAvailability? {
        if loadedDate == date, let loadedRecord { return loadedRecord }
        return LunarGoAlmanacProvider.shared.cachedRecord(for: date)
    }

    var body: some View {
        Group {
            if let record {
                content(record)
                    .background(GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                            if height > 0, abs(lastContentHeight - height) > 0.5 {
                                lastContentHeight = height
                            }
                        }
                    })
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取黄历…")
                        .font(theme.font(size: 12))
                        .foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: max(minimumLoadingHeight, lastContentHeight), alignment: .topLeading)
            }
        }
        .task(id: date) { await load(for: date) }
    }

    private func load(for date: SolarDate) async {
        guard !Task.isCancelled, loadedDate != date else { return }
        let provider = LunarGoAlmanacProvider.shared
        let result: AlmanacAvailability
        if let cached = provider.cachedRecord(for: date) {
            result = cached
        } else {
            let lookup = Task.detached(priority: .userInitiated) { provider.record(for: date) }
            result = await withTaskCancellationHandler {
                await lookup.value
            } onCancel: {
                lookup.cancel()
            }
        }
        guard !Task.isCancelled else { return }
        loadedDate = date
        loadedRecord = result
    }
}
