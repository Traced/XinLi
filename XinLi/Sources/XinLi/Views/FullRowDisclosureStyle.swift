import SwiftUI

/// Only the header row toggles expansion; links and text in the content keep
/// their own interactions, including when disclosure groups are nested.
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    var animationsEnabled = true
    @Environment(\.chronoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(animationsEnabled: Bool = true) {
        self.animationsEnabled = animationsEnabled
    }

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(animationsEnabled && !reduceMotion ? .easeInOut(duration: 0.16) : nil) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(theme.font(size: 10, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    configuration.label
                        .foregroundStyle(theme.primary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
            .accessibilityHint(configuration.isExpanded ? "收起内容" : "展开内容")

            if configuration.isExpanded {
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 19)
                    .transition(.opacity)
            }
        }
    }
}
