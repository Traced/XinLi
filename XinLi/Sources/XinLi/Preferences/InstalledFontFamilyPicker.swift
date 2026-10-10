import SwiftUI

@MainActor
struct InstalledFontFamilyPicker: View {
    @Binding var family: String
    var showsScrollIndicators = false
    var onPreview: (String?) -> Void = { _ in }
    @State private var isPresented = false
    @State private var families: [String] = []

    var body: some View {
        Button {
            onPreview(nil)
            // Refresh only when opening: newly installed fonts become available
            // without polling or loading font files ourselves.
            families = CalendarTypography.installedFamilies
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Text(family == "system" ? "系统默认" : family).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
            }
        }
        .accessibilityLabel("选择字体")
        .accessibilityValue(family == "system" ? "系统默认" : family)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FontFamilySelection(family: $family, isPresented: $isPresented,
                                families: families, showsScrollIndicators: showsScrollIndicators,
                                onPreview: onPreview)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { onPreview(nil) }
        }
        .onDisappear { onPreview(nil) }
    }
}

@MainActor
struct FontFamilySelection: View {
    @Binding var family: String
    @Binding var isPresented: Bool
    let families: [String]
    let showsScrollIndicators: Bool
    var onPreview: (String?) -> Void = { _ in }
    @State private var search = ""
    @State private var previewedFamily: String?
    @State private var acceptsPreview = false
    @FocusState private var searchFocused: Bool

    private var matchingFamilies: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return families }
        return families.filter { $0.localizedStandardContains(query) }
    }

    private var displayedFamily: String { previewedFamily ?? family }

    private var sampleFont: Font {
        if let name = CalendarTypography.resolvedFontName(for: displayedFamily) {
            return .custom(name, fixedSize: 18)
        }
        return .system(size: 18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择已安装字体").font(.headline)
            TextField("搜索字体名称", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("搜索已安装字体")
            familyButton("system", title: "系统默认")
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if matchingFamilies.isEmpty {
                            Text("没有匹配的已安装字体")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        ForEach(matchingFamilies, id: \.self) { name in
                            familyButton(name, title: name).id(name)
                        }
                    }
                }
                .scrollIndicators(showsScrollIndicators ? .automatic : .hidden)
                .onAppear {
                    if families.contains(family) { reader.scrollTo(family, anchor: .center) }
                }
            }
            .frame(height: 270)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "textformat")
                    Text(previewedFamily == nil ? "当前字体" : "正在预览")
                    Text("·")
                    Text(displayedFamily == "system" ? "系统默认" : displayedFamily)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Text("心历 · 周五 10月9日 22:30 Aa")
                    .font(sampleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 30, alignment: .leading)
                    .accessibilityLabel("字体实时预览")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text("滑过字体即可预览，点击以应用。")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(matchingFamilies.count) 种可用字体；缺失的字符由系统补全。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            acceptsPreview = true
            searchFocused = true
        }
        .onChange(of: search) { _, _ in clearPreview() }
        .onDisappear {
            acceptsPreview = false
            clearPreview()
        }
        .onExitCommand {
            acceptsPreview = false
            clearPreview()
            isPresented = false
        }
    }

    private func familyButton(_ value: String, title: String) -> some View {
        Button {
            acceptsPreview = false
            family = value
            clearPreview()
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if family == value {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                } else if previewedFamily == value {
                    Image(systemName: "eye").foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(previewedFamily == value ? Color.accentColor.opacity(0.16)
                        : family == value ? Color.accentColor.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fontRowHover { hovering in
            // Retain the last preview between rows, so gaps and the sample area
            // don't flash back to the saved font. Only a click commits it.
            guard hovering, acceptsPreview, isPresented, previewedFamily != value else { return }
            previewedFamily = value
            onPreview(value)
        }
        .accessibilityLabel(title)
        .accessibilityValue(family == value ? "已选中" : "未选中")
    }

    private func clearPreview() {
        previewedFamily = nil
        onPreview(nil)
    }
}
