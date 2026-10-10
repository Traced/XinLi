import AppKit
import Combine
import Foundation

enum CalendarDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case scenic, compact, minimal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scenic: "风景主题"
        case .compact: "迷你简约"
        case .minimal: "极简"
        }
    }
    var isCompactLayout: Bool { self != .scenic }
    var popoverWidth: CGFloat { isCompactLayout ? 392 : 580 }
}

/// The single persisted source of presentation and scheduling preferences.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    static let didChange = Notification.Name("ChronoCalPreferencesDidChange")
    private let defaults: UserDefaults
    private let persists: Bool
    private var isApplyingColorTheme = false
    private var timeZoneObserver: AnyCancellable?
    private var systemTimeZoneObserver: AnyCancellable?
    @Published var displayMode: CalendarDisplayMode { didSet { persist() } }
    @Published var showLunar: Bool { didSet { persist() } }
    @Published var showSolarTerms: Bool { didSet { persist() } }
    @Published var showHolidays: Bool { didSet { persist() } }
    @Published var showFestivals: Bool { didSet { persist() } }
    @Published var showGanZhi: Bool { didSet { persist() } }
    @Published var showAlmanac: Bool { didSet { persist() } }
    @Published var firstWeekday: Int { didSet { persist() } }
    @Published var animationsEnabled: Bool { didSet { persist() } }
    @Published var interfaceOpacity: Double {
        didSet {
            let normalized = CalendarColorTheme.normalizedOpacity(interfaceOpacity, fallback: 0.94)
            if interfaceOpacity != normalized {
                interfaceOpacity = normalized
                return
            }
            persist()
        }
    }
    @Published var colorTheme: CalendarColorTheme { didSet { persist() } }
    @Published var cardStyle: CalendarCardStyle { didSet { persist() } }
    @Published var layoutDensity: CalendarLayoutDensity { didSet { persist() } }
    @Published var showsScrollIndicators: Bool { didSet { persist() } }
    /// Hover previews redraw observed panels but never enter persistent preferences.
    @Published private(set) var previewFontFamily: String? = nil
    @Published var fontFamily: String {
        didSet {
            let normalized = CalendarTypography.normalizedFamily(fontFamily)
            if fontFamily != normalized {
                fontFamily = normalized
                return
            }
            clearFontPreview()
            persist()
        }
    }
    @Published var textScale: Double {
        didSet {
            let normalized = CalendarTypography.normalizedScale(textScale)
            if textScale != normalized {
                textScale = normalized
                return
            }
            persist()
        }
    }
    @Published var customBackgroundHex: String {
        didSet {
            let normalized = CalendarColorTheme.normalizedHex(customBackgroundHex, fallback: "#EAF0F8")
            if customBackgroundHex != normalized {
                customBackgroundHex = normalized
                return
            }
            persist()
        }
    }
    @Published var customCardHex: String {
        didSet {
            let normalized = CalendarColorTheme.normalizedHex(customCardHex, fallback: "#FFFFFF")
            if customCardHex != normalized {
                customCardHex = normalized
                return
            }
            persist()
        }
    }
    @Published var cardOpacity: Double {
        didSet {
            let normalized = CalendarColorTheme.normalizedOpacity(cardOpacity, fallback: 0.72)
            if cardOpacity != normalized {
                cardOpacity = normalized
                return
            }
            persist()
        }
    }
    @Published var accentHex: String {
        didSet {
            let normalized = CalendarColorTheme.normalizedHex(accentHex, fallback: colorTheme.accentHex)
            if accentHex != normalized {
                accentHex = normalized
                return
            }
            persist()
        }
    }
    @Published var backgroundChoice: String { didSet { persist() } }
    @Published var customBackgroundPath: String { didSet { persist() } }
    @Published var backgroundImageScope: BackgroundImageScope { didSet { persist() } }
    @Published var backgroundImageOpacity: Double {
        didSet {
            let normalized = CalendarColorTheme.normalizedOpacity(backgroundImageOpacity, fallback: 0.55)
            if backgroundImageOpacity != normalized {
                backgroundImageOpacity = normalized
                return
            }
            persist()
        }
    }
    @Published var headerOverlayOpacity: Double {
        didSet {
            let normalized = CalendarColorTheme.normalizedOpacity(headerOverlayOpacity, fallback: 0.45)
            if headerOverlayOpacity != normalized {
                headerOverlayOpacity = normalized
                return
            }
            persist()
        }
    }
    /// One setting for every displayed date/time. Empty follows the system zone.
    @Published var timeZoneIdentifier: String { didSet { if timeZoneIdentifier != oldValue { persistTimeZone() } } }
    // Compatibility aliases intentionally cannot diverge.
    var calendarTimeZoneIdentifier: String {
        get { timeZoneIdentifier }
        set { timeZoneIdentifier = newValue == "statusBar" ? timeZoneIdentifier : newValue }
    }
    var agendaTimeZoneIdentifier: String {
        get { timeZoneIdentifier }
        set { timeZoneIdentifier = newValue }
    }
    @Published var defaultReminderMinutes: Int { didSet { persist() } }
    @Published var showCompletedTasks: Bool { didSet { persist() } }
    @Published var agendaRangeDays: Int { didSet { persist() } }
    @Published var notificationsEnabled: Bool { didSet { persist() } }
    @Published var use24HourTime: Bool { didSet { persist() } }
    @Published var eventColorHex: String { didSet { persist() } }
    @Published var showStatusIcon: Bool { didSet { persist() } }
    @Published var showStatusLunar: Bool { didSet { persist() } }
    @Published var showStatusSolarTerm: Bool { didSet { persist() } }
    @Published var showStatusAgendaCount: Bool { didSet { persist() } }
    @Published var customDatePattern: String { didSet { persist() } }
    @Published var keyboardShortcutEnabled: Bool { didSet { persist() } }
    init(defaults: UserDefaults = .standard, persists: Bool = true) {
        self.persists = persists
        self.defaults = defaults
        displayMode = CalendarDisplayMode(rawValue: defaults.string(forKey: "chrono.displayMode") ?? "") ?? .scenic
        showLunar = defaults.object(forKey: "chrono.showLunar") as? Bool ?? true
        showSolarTerms = defaults.object(forKey: "chrono.showSolarTerms") as? Bool ?? true
        showHolidays = defaults.object(forKey: "chrono.showHolidays") as? Bool ?? true
        showFestivals = defaults.object(forKey: "chrono.showFestivals") as? Bool ?? true
        showGanZhi = defaults.object(forKey: "chrono.showGanZhi") as? Bool ?? true
        showAlmanac = defaults.object(forKey: "chrono.showAlmanac") as? Bool ?? true
        firstWeekday = defaults.object(forKey: "chrono.firstWeekday") as? Int ?? 2
        animationsEnabled = defaults.object(forKey: "chrono.animationsEnabled") as? Bool ?? true
        interfaceOpacity = CalendarColorTheme.normalizedOpacity(defaults.object(forKey: "chrono.interfaceOpacity") as? Double ?? 0.94, fallback: 0.94)
        let initialColorTheme = CalendarColorTheme(rawValue: defaults.string(forKey: "chrono.colorTheme") ?? "") ?? .frost
        colorTheme = initialColorTheme
        cardStyle = CalendarCardStyle(rawValue: defaults.string(forKey: "chrono.cardStyle") ?? "") ?? .glass
        layoutDensity = CalendarLayoutDensity(rawValue: defaults.string(forKey: "chrono.layoutDensity") ?? "") ?? .standard
        showsScrollIndicators = defaults.object(forKey: "chrono.showsScrollIndicators") as? Bool ?? false
        fontFamily = CalendarTypography.normalizedFamily(defaults.string(forKey: "chrono.fontFamily") ?? "system")
        let savedTextScale = defaults.object(forKey: "chrono.textScale") as? Double
        let normalizedTextScale = CalendarTypography.normalizedScale(savedTextScale ?? 1)
        textScale = normalizedTextScale
        if persists, let savedTextScale, savedTextScale != normalizedTextScale {
            // Migrate the former 125%/130% choices into the supported range,
            // without inventing a saved value for a default-only installation.
            defaults.set(normalizedTextScale, forKey: "chrono.textScale")
        }
        customBackgroundHex = CalendarColorTheme.normalizedHex(defaults.string(forKey: "chrono.customBackgroundHex") ?? "#EAF0F8", fallback: "#EAF0F8")
        customCardHex = CalendarColorTheme.normalizedHex(defaults.string(forKey: "chrono.customCardHex") ?? "#FFFFFF", fallback: "#FFFFFF")
        cardOpacity = CalendarColorTheme.normalizedOpacity(defaults.object(forKey: "chrono.cardOpacity") as? Double ?? 0.72, fallback: 0.72)
        // An older user's chosen accent survives the introduction of preset themes.
        accentHex = CalendarColorTheme.normalizedHex(defaults.string(forKey: "chrono.accentHex") ?? initialColorTheme.accentHex, fallback: initialColorTheme.accentHex)
        backgroundChoice = defaults.object(forKey: "chrono.backgroundChoice") as? String ?? "snow-sunset"
        customBackgroundPath = defaults.object(forKey: "chrono.customBackgroundPath") as? String ?? ""
        backgroundImageScope = BackgroundImageScope(rawValue: defaults.string(forKey: "chrono.backgroundImageScope") ?? "") ?? .header
        backgroundImageOpacity = CalendarColorTheme.normalizedOpacity(defaults.object(forKey: "chrono.backgroundImageOpacity") as? Double ?? 0.55, fallback: 0.55)
        headerOverlayOpacity = CalendarColorTheme.normalizedOpacity(defaults.object(forKey: "chrono.headerOverlayOpacity") as? Double ?? 0.45, fallback: 0.45)
        timeZoneIdentifier = Self.initialTimeZoneIdentifier(defaults: defaults)
        defaultReminderMinutes = defaults.object(forKey: "chrono.defaultReminderMinutes") as? Int ?? 15
        showCompletedTasks = defaults.object(forKey: "chrono.showCompletedTasks") as? Bool ?? false
        agendaRangeDays = defaults.object(forKey: "chrono.agendaRangeDays") as? Int ?? 7
        notificationsEnabled = defaults.object(forKey: "chrono.notificationsEnabled") as? Bool ?? false
        use24HourTime = defaults.object(forKey: "chrono.use24HourTime") as? Bool ?? true
        eventColorHex = defaults.object(forKey: "chrono.eventColorHex") as? String ?? "#3B82F6"
        showStatusIcon = defaults.object(forKey: "chrono.showStatusIcon") as? Bool ?? false
        showStatusLunar = defaults.object(forKey: "chrono.showStatusLunar") as? Bool ?? false
        showStatusSolarTerm = defaults.object(forKey: "chrono.showStatusSolarTerm") as? Bool ?? false
        showStatusAgendaCount = defaults.object(forKey: "chrono.showStatusAgendaCount") as? Bool ?? false
        customDatePattern = defaults.object(forKey: "chrono.customDatePattern") as? String ?? ""
        keyboardShortcutEnabled = defaults.object(forKey: "chrono.keyboardShortcutEnabled") as? Bool ?? true
        if persists {
            // Preserve the existing status-bar selection (including an explicit system setting).
            // Only migrate old standalone calendar/agenda settings when no status preference exists.
            var display = StatusBarDisplay.load(from: defaults)
            display.timeZoneIdentifier = timeZoneIdentifier.isEmpty ? nil : timeZoneIdentifier
            if defaults.data(forKey: "statusBarDisplay") == nil || display != StatusBarDisplay.load(from: defaults) {
                display.save(to: defaults)
            }
            defaults.removeObject(forKey: "chrono.calendarTimeZoneIdentifier")
            defaults.removeObject(forKey: "chrono.agendaTimeZoneIdentifier")
            timeZoneObserver = NotificationCenter.default.publisher(for: StatusBarDisplay.didChange).sink { [weak self] _ in
                guard let self else { return }
                let identifier = Self.validTimeZoneIdentifier(StatusBarDisplay.load(from: self.defaults).timeZoneIdentifier ?? "")
                if self.timeZoneIdentifier != identifier { self.timeZoneIdentifier = identifier }
            }
        }
        systemTimeZoneObserver = NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.timeZoneIdentifier.isEmpty else { return }
                self.objectWillChange.send()
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
    }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent }
    var calendarTimeZone: TimeZone { timeZone }
    var agendaTimeZone: TimeZone { timeZone }
    var effectiveFontFamily: String { previewFontFamily ?? fontFamily }

    func previewFont(_ family: String) {
        let normalized = CalendarTypography.normalizedFamily(family)
        let preview = normalized == fontFamily ? nil : normalized
        guard previewFontFamily != preview else { return }
        previewFontFamily = preview
    }

    func clearFontPreview() {
        guard previewFontFamily != nil else { return }
        previewFontFamily = nil
    }

    /// Apply a coordinated preset without overwriting the saved custom palette,
    /// backdrop choice, or calendar settings. Observers receive one final update.
    func applyColorTheme(_ theme: CalendarColorTheme) {
        isApplyingColorTheme = true
        colorTheme = theme
        if theme != .custom { accentHex = theme.accentHex }
        isApplyingColorTheme = false
        persist()
    }

    private static func validTimeZoneIdentifier(_ value: String) -> String {
        TimeZone(identifier: value) == nil ? "" : value
    }
    private static func initialTimeZoneIdentifier(defaults: UserDefaults) -> String {
        if defaults.data(forKey: "statusBarDisplay") != nil {
            return validTimeZoneIdentifier(StatusBarDisplay.load(from: defaults).timeZoneIdentifier ?? "")
        }
        for key in ["chrono.calendarTimeZoneIdentifier", "chrono.agendaTimeZoneIdentifier"] {
            if let value = defaults.string(forKey: key), !value.isEmpty, value != "statusBar", TimeZone(identifier: value) != nil {
                return value
            }
        }
        return ""
    }
    private func persistTimeZone() {
        let normalized = Self.validTimeZoneIdentifier(timeZoneIdentifier)
        if normalized != timeZoneIdentifier {
            timeZoneIdentifier = normalized
            return
        }
        if persists {
            var display = StatusBarDisplay.load(from: defaults)
            let identifier = timeZoneIdentifier.isEmpty ? nil : timeZoneIdentifier
            if display.timeZoneIdentifier != identifier {
                display.timeZoneIdentifier = identifier
                display.save(to: defaults)
            }
            defaults.removeObject(forKey: "chrono.calendarTimeZoneIdentifier")
            defaults.removeObject(forKey: "chrono.agendaTimeZoneIdentifier")
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
    private func persist() {
        guard !isApplyingColorTheme else { return }
        guard persists else { NotificationCenter.default.post(name: Self.didChange, object: self); return }
        defaults.set(displayMode.rawValue, forKey: "chrono.displayMode")
        defaults.set(showLunar, forKey: "chrono.showLunar")
        defaults.set(showSolarTerms, forKey: "chrono.showSolarTerms")
        defaults.set(showHolidays, forKey: "chrono.showHolidays")
        defaults.set(showFestivals, forKey: "chrono.showFestivals")
        defaults.set(showGanZhi, forKey: "chrono.showGanZhi")
        defaults.set(showAlmanac, forKey: "chrono.showAlmanac")
        defaults.set(firstWeekday, forKey: "chrono.firstWeekday")
        defaults.set(animationsEnabled, forKey: "chrono.animationsEnabled")
        defaults.set(interfaceOpacity, forKey: "chrono.interfaceOpacity")
        defaults.set(colorTheme.rawValue, forKey: "chrono.colorTheme")
        defaults.set(cardStyle.rawValue, forKey: "chrono.cardStyle")
        defaults.set(layoutDensity.rawValue, forKey: "chrono.layoutDensity")
        defaults.set(showsScrollIndicators, forKey: "chrono.showsScrollIndicators")
        defaults.set(fontFamily, forKey: "chrono.fontFamily")
        defaults.set(textScale, forKey: "chrono.textScale")
        defaults.set(customBackgroundHex, forKey: "chrono.customBackgroundHex")
        defaults.set(customCardHex, forKey: "chrono.customCardHex")
        defaults.set(cardOpacity, forKey: "chrono.cardOpacity")
        defaults.set(accentHex, forKey: "chrono.accentHex")
        defaults.set(backgroundChoice, forKey: "chrono.backgroundChoice")
        defaults.set(customBackgroundPath, forKey: "chrono.customBackgroundPath")
        defaults.set(backgroundImageScope.rawValue, forKey: "chrono.backgroundImageScope")
        defaults.set(backgroundImageOpacity, forKey: "chrono.backgroundImageOpacity")
        defaults.set(headerOverlayOpacity, forKey: "chrono.headerOverlayOpacity")
        defaults.set(defaultReminderMinutes, forKey: "chrono.defaultReminderMinutes")
        defaults.set(showCompletedTasks, forKey: "chrono.showCompletedTasks")
        defaults.set(agendaRangeDays, forKey: "chrono.agendaRangeDays")
        defaults.set(notificationsEnabled, forKey: "chrono.notificationsEnabled")
        defaults.set(use24HourTime, forKey: "chrono.use24HourTime")
        defaults.set(eventColorHex, forKey: "chrono.eventColorHex")
        defaults.set(showStatusIcon, forKey: "chrono.showStatusIcon")
        defaults.set(showStatusLunar, forKey: "chrono.showStatusLunar")
        defaults.set(showStatusSolarTerm, forKey: "chrono.showStatusSolarTerm")
        defaults.set(showStatusAgendaCount, forKey: "chrono.showStatusAgendaCount")
        defaults.set(customDatePattern, forKey: "chrono.customDatePattern")
        defaults.set(keyboardShortcutEnabled, forKey: "chrono.keyboardShortcutEnabled")
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published private(set) var backgroundImage: NSImage?
    @Published private(set) var isRefreshingBackground = false
    @Published private(set) var backgroundError: String?
    @Published private(set) var bingCopyright: String?
    @Published private(set) var bingCopyrightURL: URL?
    @Published private(set) var bingTitle: String?
    private let preferences: AppPreferences
    private let bingService: BingBackgroundService
    private let allowNetwork: Bool
    private var observer: AnyCancellable?
    private var loadedPath = ""
    private var cachedBing: BingCachedBackground?
    private var hasCheckedBingCache = false
    private var isCheckingBingCache = false
    private var cacheGeneration = 0
    private var didAttemptAutomaticRefresh = false
    private var selectionGeneration = 0
    private var previousSelection: String

    init(preferences: AppPreferences = .shared, bingService: BingBackgroundService = BingBackgroundService(),
         allowNetwork: Bool = true) {
        self.preferences = preferences
        self.bingService = bingService
        self.allowNetwork = allowNetwork
        self.previousSelection = preferences.backgroundChoice + "|" + preferences.customBackgroundPath
        observer = NotificationCenter.default.publisher(for: AppPreferences.didChange).sink { [weak self] notification in
            guard let self, notification.object as? AppPreferences === self.preferences else { return }
            let selection = self.preferences.backgroundChoice + "|" + self.preferences.customBackgroundPath
            if self.previousSelection != selection {
                self.previousSelection = selection
                self.selectionGeneration += 1
                self.didAttemptAutomaticRefresh = false
                self.backgroundError = nil
            }
            self.reload()
        }
        reload()
    }

    func clearCache() {
        loadedPath = ""
        cachedBing = nil
        hasCheckedBingCache = false
        cacheGeneration += 1
        reload()
    }

    func reload() {
        if preferences.backgroundChoice == "bing" {
            if let cachedBing {
                display(cachedBing)
            } else if !hasCheckedBingCache {
                // Keep the currently visible picture while validating the disk cache off-thread.
                if backgroundImage == nil { loadImage(at: builtInPath("snow-sunset")) }
                checkBingCache()
            } else {
                if backgroundImage == nil { loadImage(at: builtInPath("snow-sunset")) }
                requestInitialBingImageIfNeeded()
            }
            return
        }
        bingCopyright = nil
        bingCopyrightURL = nil
        bingTitle = nil
        let path = preferences.backgroundChoice == "custom" ? preferences.customBackgroundPath : builtInPath(preferences.backgroundChoice)
        loadImage(at: path)
    }

    /// Also works from a built-in/custom background. Only a successful refresh
    /// changes the source, and an intervening user selection always wins.
    func refreshBingBackground() async {
        guard !isRefreshingBackground else { return }
        guard allowNetwork else {
            backgroundError = "当前预览或测试模式未启用网络图片。"
            return
        }
        let generation = selectionGeneration
        isRefreshingBackground = true
        backgroundError = nil
        defer { isRefreshingBackground = false }
        let service = bingService
        let request = Task.detached(priority: .userInitiated) { try await service.refresh() }
        do {
            let cached = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: { request.cancel() }
            // The service atomically replaced the disk cache, including removal of
            // the old file. Always retain its new location even when this request
            // has become stale for the currently selected background.
            cacheGeneration += 1
            cachedBing = cached
            hasCheckedBingCache = true
            guard !Task.isCancelled, generation == selectionGeneration else {
                if preferences.backgroundChoice == "bing" { display(cached) }
                return
            }
            loadedPath = ""
            if preferences.backgroundChoice != "bing" { preferences.backgroundChoice = "bing" }
            else { display(cached) }
        } catch {
            guard generation == selectionGeneration, !(error is CancellationError) else { return }
            backgroundError = "无法更新 Bing 风景：" + error.localizedDescription
        }
    }

    private func checkBingCache() {
        guard !isCheckingBingCache else { return }
        isCheckingBingCache = true
        let generation = cacheGeneration
        let service = bingService
        Task { @MainActor [weak self] in
            let cached = await Task.detached(priority: .userInitiated) { service.cachedBackground() }.value
            guard let self else { return }
            self.isCheckingBingCache = false
            guard generation == self.cacheGeneration else {
                if self.preferences.backgroundChoice == "bing" { self.reload() }
                return
            }
            self.cachedBing = cached
            self.hasCheckedBingCache = true
            if self.preferences.backgroundChoice == "bing" { self.reload() }
        }
    }

    private func requestInitialBingImageIfNeeded() {
        guard !didAttemptAutomaticRefresh, !isRefreshingBackground else { return }
        didAttemptAutomaticRefresh = true
        Task { @MainActor [weak self] in
            guard let self, self.preferences.backgroundChoice == "bing" else { return }
            await self.refreshBingBackground()
        }
    }

    private func display(_ cached: BingCachedBackground) {
        guard loadImage(at: cached.imageFileURL.path) else {
            // A cache can be removed while the app is open. Keep the visible
            // image and its attribution together rather than labelling it as
            // the Bing file that failed to load.
            cachedBing = nil
            hasCheckedBingCache = true
            backgroundError = "Bing 背景缓存无法读取，已保留原图。"
            requestInitialBingImageIfNeeded()
            return
        }
        bingCopyright = cached.metadata.copyright
        bingCopyrightURL = cached.metadata.copyrightURL
        bingTitle = cached.metadata.title
    }

    @discardableResult
    private func loadImage(at path: String) -> Bool {
        guard loadedPath != path else { return backgroundImage != nil }
        // A failed download/decoding attempt must not replace a visible picture with nil.
        guard let image = NSImage(contentsOfFile: path) else { return false }
        loadedPath = path
        backgroundImage = image
        return true
    }

    private func builtInPath(_ name: String) -> String {
        #if SWIFT_PACKAGE
        // Distributed SwiftPM applications keep their resource bundle inside Resources.
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            let url = Bundle.main.resourceURL?.appendingPathComponent("XinLi_XinLi.bundle")
            bundle = url.flatMap(Bundle.init(url:)) ?? Bundle.main
        } else { bundle = Bundle.module }
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: name, withExtension: "jpg")?.path ?? ""
    }

    func selectCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url, let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ChronoCal")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("custom-background.jpg")
            try jpeg.write(to: destination, options: .atomic)
            // The destination path stays the same when another local picture is selected.
            // Explicitly invalidate pending Bing results even if the preference strings do not change.
            selectionGeneration += 1
            backgroundError = nil
            loadedPath = ""
            preferences.customBackgroundPath = destination.path
            preferences.backgroundChoice = "custom"
        } catch {
            let alert = NSAlert(); alert.messageText = "无法保存背景图片"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
}
