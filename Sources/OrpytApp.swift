import AppKit
import Combine
import CoreLocation
import SwiftUI
import WeatherKit

@main
struct OrpytApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let logoImage = AppAssetLoader.logoImage() {
            NSApp.applicationIconImage = logoImage
            NSWorkspace.shared.setIcon(logoImage, forFile: Bundle.main.bundlePath, options: [])
        }

        let settings = ClockSettingsStore.shared
        let weatherStore = WeatherStore.shared
        let settingsWindowController = SettingsWindowController(settings: settings, weatherStore: weatherStore)
        statusController = StatusBarController(
            settings: settings,
            weatherStore: weatherStore,
            settingsWindowController: settingsWindowController
        )
    }
}

@MainActor
private final class StatusBarController: NSObject, NSPopoverDelegate {
    private let settings: ClockSettingsStore
    private let weatherStore: WeatherStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastWeatherRefreshDate = Date.distantPast
    private var lastMeasuredPopoverHeight: CGFloat = 0
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.settingsWindowController = settingsWindowController
        super.init()
        configureStatusItem()
        configurePopover()
        installOutsideClickMonitors()
        observeSettings()
        observeWeatherSettings()
        observeWeather()
        startTimer()
        refreshWeather(force: true)
        updateDisplay()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Orpyt"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 452, height: 360)
        popover.delegate = self
        popover.contentViewController = popoverHostingController
        refreshPopoverContent()
    }

    private func observeSettings() {
        let displayPublishers: [AnyPublisher<Void, Never>] = [
            settings.$primaryTimeZoneID.map { _ in }.eraseToAnyPublisher(),
            settings.$secondaryTimeZoneID.map { _ in }.eraseToAnyPublisher(),
            settings.$primaryCustomLabel.map { _ in }.eraseToAnyPublisher(),
            settings.$secondaryCustomLabel.map { _ in }.eraseToAnyPublisher(),
            settings.$showPrimaryClock.map { _ in }.eraseToAnyPublisher(),
            settings.$showSecondaryClock.map { _ in }.eraseToAnyPublisher(),
            settings.$use24HourClock.map { _ in }.eraseToAnyPublisher(),
            settings.$showSeconds.map { _ in }.eraseToAnyPublisher(),
            settings.$showWeekday.map { _ in }.eraseToAnyPublisher(),
            settings.$showDate.map { _ in }.eraseToAnyPublisher(),
            settings.$showTimeZoneAbbreviation.map { _ in }.eraseToAnyPublisher(),
            settings.$showGMTOffset.map { _ in }.eraseToAnyPublisher(),
            settings.$showZoneLabelInMenuBar.map { _ in }.eraseToAnyPublisher(),
            settings.$showStatusIcon.map { _ in }.eraseToAnyPublisher(),
            settings.$enableWeather.map { _ in }.eraseToAnyPublisher(),
            settings.$showWeatherInMenuBar.map { _ in }.eraseToAnyPublisher(),
            settings.$showWeatherLocation.map { _ in }.eraseToAnyPublisher(),
            settings.$showFeelsLikeTemperature.map { _ in }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(displayPublishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        settings.$showSeconds
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.startTimer()
            }
            .store(in: &cancellables)

        settings.$appearanceModeRawValue
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPopoverContent()
            }
            .store(in: &cancellables)
    }

    private func observeWeatherSettings() {
        Publishers.CombineLatest4(
            settings.$enableWeather,
            settings.$showPrimaryClock,
            settings.$showSecondaryClock,
            Publishers.CombineLatest4(
                settings.$primaryTimeZoneID,
                settings.$secondaryTimeZoneID,
                settings.$primaryWeatherLocation,
                settings.$secondaryWeatherLocation
            )
        )
        .map { enableWeather, showPrimaryClock, showSecondaryClock, config in
            [
                enableWeather ? "1" : "0",
                showPrimaryClock ? "1" : "0",
                showSecondaryClock ? "1" : "0",
                config.0,
                config.1,
                config.2,
                config.3,
            ].joined(separator: "|")
        }
        .removeDuplicates()
        .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshWeather(force: true)
        }
        .store(in: &cancellables)
    }

    private func observeWeather() {
        weatherStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: settings.showSeconds ? 1 : 60,
            target: self,
            selector: #selector(handleTimerTick),
            userInfo: nil,
            repeats: true
        )

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func handleTimerTick() {
        updateDisplay()
        refreshWeather(force: false)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func installOutsideClickMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            guard let popoverWindow = self.popover.contentViewController?.view.window else { return event }

            if event.window !== popoverWindow && event.window !== self.statusItem.button?.window {
                self.popover.performClose(nil)
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func updateDisplay() {
        let now = Date()
        statusItem.button?.attributedTitle = ClockFormatter.menuBarAttributedTitle(
            for: now,
            settings: settings,
            weatherStore: weatherStore
        )
        statusItem.button?.toolTip = ClockFormatter.menuBarTooltip(
            for: now,
            settings: settings,
            weatherStore: weatherStore
        )
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
    }

    private func openSettings() {
        popover.performClose(nil)
        settingsWindowController.show()
    }

    private func refreshPopoverContent() {
        switch settings.appearanceMode {
        case .system:
            popover.appearance = nil
        case .light:
            popover.appearance = NSAppearance(named: .aqua)
        case .dark:
            popover.appearance = NSAppearance(named: .darkAqua)
        }

        let baseView = StatusPopoverView(
            settings: settings,
            weatherStore: weatherStore,
            appearanceMode: settings.appearanceMode,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onSwapTimeZones: { [weak self, weak settings] in
                settings?.swapTimeZones()
                self?.weatherStore.swapClockStates()
            },
            onQuit: { NSApplication.shared.terminate(nil) },
            onContentHeightChange: { [weak self] height in
                self?.updatePopoverSize(for: height)
            }
        )

        switch settings.appearanceMode {
        case .system:
            popoverHostingController.rootView = AnyView(baseView)
        case .light, .dark:
            popoverHostingController.rootView = AnyView(
                baseView.preferredColorScheme(settings.preferredColorScheme)
            )
        }

        popoverHostingController.view.appearance = popover.appearance
    }

    private func updatePopoverSize(for measuredHeight: CGFloat) {
        let targetHeight = min(max((measuredHeight + 28).rounded(.up), 320), 760)
        guard abs(targetHeight - lastMeasuredPopoverHeight) > 8 else { return }

        lastMeasuredPopoverHeight = targetHeight
        popover.contentSize = NSSize(width: 452, height: targetHeight)
    }

    private func refreshWeather(force: Bool) {
        guard settings.enableWeather else {
            weatherStore.disable()
            return
        }

        let refreshInterval: TimeInterval = 15 * 60
        let now = Date()

        guard force || now.timeIntervalSince(lastWeatherRefreshDate) >= refreshInterval else {
            return
        }

        lastWeatherRefreshDate = now
        weatherStore.refresh(for: settings)
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var didCenterWindow = false
    private let settings: ClockSettingsStore
    private let weatherStore: WeatherStore
    private let hostingController: NSHostingController<AnyView>

    init(settings: ClockSettingsStore, weatherStore: WeatherStore) {
        self.settings = settings
        self.weatherStore = weatherStore
        hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        let window = OrpytSettingsWindow(contentViewController: hostingController)

        window.title = "Orpyt Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 900, height: 660)
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        hostingController.rootView = AnyView(SettingsView(settings: settings, weatherStore: weatherStore))
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        if !didCenterWindow {
            window.center()
            didCenterWindow = true
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        showWindow(nil)
        window.orderFrontRegardless()
        window.makeKey()
        window.makeMain()
    }

    func refreshAppearance() {
        window?.appearance = nil
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
private final class ClockSettingsStore: ObservableObject {
    static let shared = ClockSettingsStore()

    @Published var primaryTimeZoneID: String { didSet { save() } }
    @Published var secondaryTimeZoneID: String { didSet { save() } }
    @Published var primaryCustomLabel: String { didSet { save() } }
    @Published var secondaryCustomLabel: String { didSet { save() } }
    @Published var showPrimaryClock: Bool {
        didSet {
            if !showPrimaryClock && !showSecondaryClock {
                showSecondaryClock = true
            }
            save()
        }
    }
    @Published var showSecondaryClock: Bool {
        didSet {
            if !showPrimaryClock && !showSecondaryClock {
                showPrimaryClock = true
            }
            save()
        }
    }
    @Published var use24HourClock: Bool { didSet { save() } }
    @Published var showSeconds: Bool { didSet { save() } }
    @Published var showWeekday: Bool { didSet { save() } }
    @Published var showDate: Bool { didSet { save() } }
    @Published var showTimeZoneAbbreviation: Bool { didSet { save() } }
    @Published var showGMTOffset: Bool { didSet { save() } }
    @Published var showZoneLabelInMenuBar: Bool { didSet { save() } }
    @Published var showStatusIcon: Bool {
        didSet {
            if showStatusIcon {
                showWeatherInMenuBar = false
            } else if !showWeatherInMenuBar {
                showStatusIcon = true
                return
            }
            save()
        }
    }
    @Published var enableWeather: Bool {
        didSet {
            if !enableWeather {
                showStatusIcon = true
            }
            save()
        }
    }
    @Published var showWeatherInMenuBar: Bool {
        didSet {
            if showWeatherInMenuBar {
                showStatusIcon = false
            } else if !showStatusIcon {
                showStatusIcon = true
                return
            }
            save()
        }
    }
    @Published var showWeatherLocation: Bool { didSet { save() } }
    @Published var showFeelsLikeTemperature: Bool { didSet { save() } }
    @Published var primaryWeatherLocation: String { didSet { save() } }
    @Published var secondaryWeatherLocation: String { didSet { save() } }
    @Published var appearanceModeRawValue: String { didSet { save() } }

    private let defaults = UserDefaults.standard

    private init() {
        let savedPrimary = defaults.string(forKey: SettingsKeys.primaryTimeZoneID) ?? TimeZoneCatalog.defaultPrimaryID
        let savedSecondary = defaults.string(forKey: SettingsKeys.secondaryTimeZoneID) ?? TimeZoneCatalog.defaultSecondaryID

        primaryTimeZoneID = TimeZoneCatalog.option(for: savedPrimary)?.id ?? TimeZoneCatalog.defaultPrimaryID
        secondaryTimeZoneID = TimeZoneCatalog.option(for: savedSecondary)?.id ?? TimeZoneCatalog.defaultSecondaryID
        primaryCustomLabel = defaults.string(forKey: SettingsKeys.primaryCustomLabel) ?? ""
        secondaryCustomLabel = defaults.string(forKey: SettingsKeys.secondaryCustomLabel) ?? ""
        showPrimaryClock = defaults.object(forKey: SettingsKeys.showPrimaryClock) as? Bool ?? true
        showSecondaryClock = defaults.object(forKey: SettingsKeys.showSecondaryClock) as? Bool ?? true
        use24HourClock = defaults.object(forKey: SettingsKeys.use24HourClock) as? Bool ?? false
        showSeconds = defaults.object(forKey: SettingsKeys.showSeconds) as? Bool ?? false
        showWeekday = defaults.object(forKey: SettingsKeys.showWeekday) as? Bool ?? true
        showDate = defaults.object(forKey: SettingsKeys.showDate) as? Bool ?? true
        showTimeZoneAbbreviation = defaults.object(forKey: SettingsKeys.showTimeZoneAbbreviation) as? Bool ?? true
        showGMTOffset = defaults.object(forKey: SettingsKeys.showGMTOffset) as? Bool ?? false
        showZoneLabelInMenuBar = defaults.object(forKey: SettingsKeys.showZoneLabelInMenuBar) as? Bool ?? true
        showStatusIcon = defaults.object(forKey: SettingsKeys.showStatusIcon) as? Bool ?? true
        enableWeather = defaults.object(forKey: SettingsKeys.enableWeather) as? Bool ?? false
        showWeatherInMenuBar = defaults.object(forKey: SettingsKeys.showWeatherInMenuBar) as? Bool ?? true
        showWeatherLocation = defaults.object(forKey: SettingsKeys.showWeatherLocation) as? Bool ?? true
        showFeelsLikeTemperature = defaults.object(forKey: SettingsKeys.showFeelsLikeTemperature) as? Bool ?? true
        primaryWeatherLocation = defaults.string(forKey: SettingsKeys.primaryWeatherLocation) ?? ""
        secondaryWeatherLocation = defaults.string(forKey: SettingsKeys.secondaryWeatherLocation) ?? ""
        appearanceModeRawValue = defaults.string(forKey: SettingsKeys.appearanceModeRawValue) ?? AppearanceMode.system.rawValue
    }

    func swapTimeZones() {
        let originalPrimaryZone = primaryTimeZoneID
        let originalPrimaryLabel = primaryCustomLabel
        primaryTimeZoneID = secondaryTimeZoneID
        primaryCustomLabel = secondaryCustomLabel
        secondaryTimeZoneID = originalPrimaryZone
        secondaryCustomLabel = originalPrimaryLabel
    }

    func displayLabel(for timeZoneID: String, customLabel: String) -> String {
        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return TimeZoneCatalog.option(for: timeZoneID)?.shortLabel ?? "TZ"
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRawValue) ?? .system }
        set { appearanceModeRawValue = newValue.rawValue }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func save() {
        defaults.set(primaryTimeZoneID, forKey: SettingsKeys.primaryTimeZoneID)
        defaults.set(secondaryTimeZoneID, forKey: SettingsKeys.secondaryTimeZoneID)
        defaults.set(primaryCustomLabel, forKey: SettingsKeys.primaryCustomLabel)
        defaults.set(secondaryCustomLabel, forKey: SettingsKeys.secondaryCustomLabel)
        defaults.set(showPrimaryClock, forKey: SettingsKeys.showPrimaryClock)
        defaults.set(showSecondaryClock, forKey: SettingsKeys.showSecondaryClock)
        defaults.set(use24HourClock, forKey: SettingsKeys.use24HourClock)
        defaults.set(showSeconds, forKey: SettingsKeys.showSeconds)
        defaults.set(showWeekday, forKey: SettingsKeys.showWeekday)
        defaults.set(showDate, forKey: SettingsKeys.showDate)
        defaults.set(showTimeZoneAbbreviation, forKey: SettingsKeys.showTimeZoneAbbreviation)
        defaults.set(showGMTOffset, forKey: SettingsKeys.showGMTOffset)
        defaults.set(showZoneLabelInMenuBar, forKey: SettingsKeys.showZoneLabelInMenuBar)
        defaults.set(showStatusIcon, forKey: SettingsKeys.showStatusIcon)
        defaults.set(enableWeather, forKey: SettingsKeys.enableWeather)
        defaults.set(showWeatherInMenuBar, forKey: SettingsKeys.showWeatherInMenuBar)
        defaults.set(showWeatherLocation, forKey: SettingsKeys.showWeatherLocation)
        defaults.set(showFeelsLikeTemperature, forKey: SettingsKeys.showFeelsLikeTemperature)
        defaults.set(primaryWeatherLocation, forKey: SettingsKeys.primaryWeatherLocation)
        defaults.set(secondaryWeatherLocation, forKey: SettingsKeys.secondaryWeatherLocation)
        defaults.set(appearanceModeRawValue, forKey: SettingsKeys.appearanceModeRawValue)
    }
}

private enum SettingsKeys {
    static let primaryTimeZoneID = "primaryTimeZoneID"
    static let secondaryTimeZoneID = "secondaryTimeZoneID"
    static let primaryCustomLabel = "primaryCustomLabel"
    static let secondaryCustomLabel = "secondaryCustomLabel"
    static let showPrimaryClock = "showPrimaryClock"
    static let showSecondaryClock = "showSecondaryClock"
    static let use24HourClock = "use24HourClock"
    static let showSeconds = "showSeconds"
    static let showWeekday = "showWeekday"
    static let showDate = "showDate"
    static let showTimeZoneAbbreviation = "showTimeZoneAbbreviation"
    static let showGMTOffset = "showGMTOffset"
    static let showZoneLabelInMenuBar = "showZoneLabelInMenuBar"
    static let showStatusIcon = "showStatusIcon"
    static let enableWeather = "enableWeather"
    static let showWeatherInMenuBar = "showWeatherInMenuBar"
    static let showWeatherLocation = "showWeatherLocation"
    static let showFeelsLikeTemperature = "showFeelsLikeTemperature"
    static let primaryWeatherLocation = "primaryWeatherLocation"
    static let secondaryWeatherLocation = "secondaryWeatherLocation"
    static let appearanceModeRawValue = "appearanceModeRawValue"
}

private enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "Follow System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

private enum ClockSlot {
    case primary
    case secondary
}

private struct WeatherSnapshot {
    let symbolName: String
    let temperatureText: String
    let conditionText: String
    let feelsLikeText: String
    let resolvedLocationName: String
}

private struct WeatherAttributionSnapshot {
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
    let legalPageURL: URL
}

private enum WeatherState {
    case idle
    case loading
    case loaded(WeatherSnapshot)
    case failed(String)
}

private struct WeatherRefreshConfiguration {
    let enableWeather: Bool
    let showPrimaryClock: Bool
    let showSecondaryClock: Bool
    let primaryTimeZoneID: String
    let secondaryTimeZoneID: String
    let primaryQuery: String
    let secondaryQuery: String

    @MainActor
    init(settings: ClockSettingsStore) {
        enableWeather = settings.enableWeather
        showPrimaryClock = settings.showPrimaryClock
        showSecondaryClock = settings.showSecondaryClock
        primaryTimeZoneID = settings.primaryTimeZoneID
        secondaryTimeZoneID = settings.secondaryTimeZoneID
        primaryQuery = ""
        secondaryQuery = ""
    }
}

@MainActor
private final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    @Published private(set) var primaryState: WeatherState = .idle
    @Published private(set) var secondaryState: WeatherState = .idle
    @Published private(set) var attribution: WeatherAttributionSnapshot?

    private let weatherService = WeatherService()
    private let urlSession = URLSession(configuration: .ephemeral)
    private var refreshTask: Task<Void, Never>?
    private var geocodeCache: [String: CLLocation] = [:]

    func refresh(for settings: ClockSettingsStore) {
        let configuration = WeatherRefreshConfiguration(settings: settings)
        refreshTask?.cancel()

        guard configuration.enableWeather else {
            disable()
            return
        }

        if configuration.showPrimaryClock {
            primaryState = .loading
        } else {
            primaryState = .idle
        }

        if configuration.showSecondaryClock {
            secondaryState = .loading
        } else {
            secondaryState = .idle
        }

        refreshTask = Task {
            let primaryResult = configuration.showPrimaryClock
                ? await fetchWeather(
                    query: configuration.primaryQuery,
                    fallbackTimeZoneID: configuration.primaryTimeZoneID
                )
                : .idle

            let secondaryResult = configuration.showSecondaryClock
                ? await fetchWeather(
                    query: configuration.secondaryQuery,
                    fallbackTimeZoneID: configuration.secondaryTimeZoneID
                )
                : .idle

            let attribution = await fetchAttribution()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.primaryState = primaryResult
                self.secondaryState = secondaryResult
                self.attribution = attribution
            }
        }
    }

    func disable() {
        refreshTask?.cancel()
        primaryState = .idle
        secondaryState = .idle
        attribution = nil
    }

    func state(for slot: ClockSlot) -> WeatherState {
        switch slot {
        case .primary:
            return primaryState
        case .secondary:
            return secondaryState
        }
    }

    func swapClockStates() {
        let originalPrimary = primaryState
        primaryState = secondaryState
        secondaryState = originalPrimary
    }

    private func fetchWeather(query: String, fallbackTimeZoneID: String) async -> WeatherState {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFallbackCityName = TimeZoneCatalog.option(for: fallbackTimeZoneID)?.cityName ?? fallbackCityName(for: fallbackTimeZoneID)

        if trimmedQuery.isEmpty,
           let representativeLocation = TimeZoneCatalog.representativeLocation(for: fallbackTimeZoneID) {
            return await fetchCurrentWeather(
                at: representativeLocation,
                resolvedLocationName: resolvedFallbackCityName
            )
        }

        let resolvedQuery = trimmedQuery.isEmpty
            ? TimeZoneCatalog.weatherLookupName(for: fallbackTimeZoneID)
            : trimmedQuery
        let cacheKey = resolvedQuery.lowercased()

        if let cachedLocation = geocodeCache[cacheKey] {
            return await fetchCurrentWeather(at: cachedLocation, resolvedLocationName: resolvedQuery)
        }

        if let openMeteoLocation = try? await fetchOpenMeteoLocation(for: resolvedQuery) {
            geocodeCache[cacheKey] = openMeteoLocation.location
            return await fetchCurrentWeather(
                at: openMeteoLocation.location,
                resolvedLocationName: openMeteoLocation.displayName
            )
        }

        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.geocodeAddressString(resolvedQuery)

            guard let placemark = placemarks.first, let location = placemark.location else {
                return .failed("Location not found")
            }

            geocodeCache[cacheKey] = location

            return await fetchCurrentWeather(
                at: location,
                resolvedLocationName: placemark.locality ?? placemark.name ?? resolvedQuery
            )
        } catch {
            if trimmedQuery.isEmpty,
               let representativeLocation = TimeZoneCatalog.representativeLocation(for: fallbackTimeZoneID) {
                return await fetchCurrentWeather(
                    at: representativeLocation,
                    resolvedLocationName: resolvedFallbackCityName
                )
            }
            return .failed(userFacingMessage(for: error))
        }
    }

    private func fetchCurrentWeather(at location: CLLocation, resolvedLocationName: String) async -> WeatherState {
        do {
            let currentWeather = try await weatherService.weather(for: location, including: .current)

            let temperatureFormatter = MeasurementFormatter()
            temperatureFormatter.unitOptions = .providedUnit
            temperatureFormatter.numberFormatter.maximumFractionDigits = 0

            return .loaded(
                WeatherSnapshot(
                    symbolName: currentWeather.symbolName,
                    temperatureText: temperatureFormatter.string(from: currentWeather.temperature),
                    conditionText: currentWeather.condition.description,
                    feelsLikeText: temperatureFormatter.string(from: currentWeather.apparentTemperature),
                    resolvedLocationName: resolvedLocationName
                )
            )
        } catch {
            if let fallbackSnapshot = try? await fetchOpenMeteoWeather(at: location, resolvedLocationName: resolvedLocationName) {
                return .loaded(fallbackSnapshot)
            }

            return .failed(userFacingMessage(for: error))
        }
    }

    private func fetchOpenMeteoLocation(for query: String) async throws -> OpenMeteoGeocodeResult {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]

        let (data, _) = try await urlSession.data(from: components.url!)
        let response = try JSONDecoder().decode(OpenMeteoGeocodeResponse.self, from: data)

        guard let result = response.results?.first else {
            throw NSError(domain: "OpenMeteoGeocoding", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Location not found",
            ])
        }

        return result
    }

    private func fetchOpenMeteoWeather(at location: CLLocation, resolvedLocationName: String) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,is_day,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]

        let (data, _) = try await urlSession.data(from: components.url!)
        let response = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)

        guard let current = response.current,
              let temperature = current.temperature2m,
              let apparentTemperature = current.apparentTemperature,
              let weatherCode = current.weatherCode else {
            throw NSError(domain: "OpenMeteoForecast", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Weather unavailable",
            ])
        }

        let isDay = (current.isDay ?? 1) == 1
        let condition = OpenMeteoWeatherCatalog.condition(for: weatherCode, isDay: isDay)

        return WeatherSnapshot(
            symbolName: condition.symbolName,
            temperatureText: String(format: "%.0f°C", temperature),
            conditionText: condition.description,
            feelsLikeText: String(format: "%.0f°C", apparentTemperature),
            resolvedLocationName: resolvedLocationName
        )
    }

    private func fetchAttribution() async -> WeatherAttributionSnapshot? {
        do {
            let attribution = try await weatherService.attribution
            return WeatherAttributionSnapshot(
                combinedMarkLightURL: attribution.combinedMarkLightURL,
                combinedMarkDarkURL: attribution.combinedMarkDarkURL,
                legalPageURL: attribution.legalPageURL
            )
        } catch {
            return nil
        }
    }

    private func fallbackCityName(for timeZoneID: String) -> String {
        timeZoneID.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? timeZoneID
    }

    private func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == kCLErrorDomain {
            return "Location lookup failed"
        }

        if nsError.domain.localizedCaseInsensitiveContains("weather") {
            return "Weather unavailable right now"
        }

        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Weather unavailable"
        }

        return message
    }
}

private struct OpenMeteoGeocodeResponse: Decodable {
    let results: [OpenMeteoGeocodeResult]?
}

private struct OpenMeteoGeocodeResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        [name, admin1, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let current: OpenMeteoCurrentWeather?
}

private struct OpenMeteoCurrentWeather: Decodable {
    let temperature2m: Double?
    let apparentTemperature: Double?
    let isDay: Int?
    let weatherCode: Int?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case isDay = "is_day"
        case weatherCode = "weather_code"
    }
}

private enum OpenMeteoWeatherCatalog {
    static func condition(for code: Int, isDay: Bool) -> (description: String, symbolName: String) {
        switch code {
        case 0:
            return (isDay ? "Clear" : "Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1, 2:
            return (isDay ? "Partly cloudy" : "Partly cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3:
            return ("Overcast", "cloud.fill")
        case 45, 48:
            return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57:
            return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86:
            return ("Snow", "snowflake")
        case 95, 96, 99:
            return ("Thunderstorm", "cloud.bolt.rain.fill")
        default:
            return ("Weather", "cloud.fill")
        }
    }
}

private struct StatusPopoverView: View {
    @ObservedObject var settings: ClockSettingsStore
    @ObservedObject var weatherStore: WeatherStore
    let appearanceMode: AppearanceMode
    let onOpenSettings: () -> Void
    let onSwapTimeZones: () -> Void
    let onQuit: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    @State private var activeEditorSlot: ClockSlot?
    @State private var primarySearchText = ""
    @State private var secondarySearchText = ""
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PopoverPalette {
        PopoverPalette.make(for: appearanceMode, systemColorScheme: colorScheme)
    }

    private var preferredPopoverHeight: CGFloat {
        var height: CGFloat = settings.showPrimaryClock && settings.showSecondaryClock ? 455 : 420

        if activeEditorSlot != nil {
            height += 250
        }

        if settings.enableWeather {
            height += 36
        }

        if settings.enableWeather, weatherStore.attribution != nil {
            height += 18
        }

        return height
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: settings.showSeconds ? 1 : 60)) { context in
            ZStack(alignment: .topLeading) {
                PopoverBackdrop(palette: palette)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Orpyt")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Synced across cities, weather, and work.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            CompactGlassButton(symbol: "arrow.left.arrow.right", palette: palette, action: onSwapTimeZones)
                                .help("Swap clocks")
                            CompactGlassButton(symbol: "slider.horizontal.3", palette: palette, action: onOpenSettings)
                                .help("Open settings")
                            CompactGlassButton(symbol: "power", palette: palette) {
                                onQuit()
                            }
                            .help("Quit Orpyt")
                        }
                    }

                    HStack(spacing: 12) {
                        if settings.showPrimaryClock {
                            Button {
                                toggleEditor(.primary)
                            } label: {
                                ClockCardView(
                                    slot: .primary,
                                    title: "Primary",
                                    label: settings.displayLabel(
                                        for: settings.primaryTimeZoneID,
                                        customLabel: settings.primaryCustomLabel
                                    ),
                                    timeZoneID: settings.primaryTimeZoneID,
                                    settings: settings,
                                    weatherState: weatherStore.state(for: .primary),
                                    date: context.date,
                                    isEditing: activeEditorSlot == .primary,
                                    palette: palette
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if settings.showSecondaryClock {
                            Button {
                                toggleEditor(.secondary)
                            } label: {
                                ClockCardView(
                                    slot: .secondary,
                                    title: "Secondary",
                                    label: settings.displayLabel(
                                        for: settings.secondaryTimeZoneID,
                                        customLabel: settings.secondaryCustomLabel
                                    ),
                                    timeZoneID: settings.secondaryTimeZoneID,
                                    settings: settings,
                                    weatherState: weatherStore.state(for: .secondary),
                                    date: context.date,
                                    isEditing: activeEditorSlot == .secondary,
                                    palette: palette
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let activeEditorSlot {
                        InlineTimeZoneEditorView(
                            title: activeEditorSlot == .primary ? "Edit Primary Clock" : "Edit Secondary Clock",
                            selectedTimeZoneID: selectedTimeZoneBinding(for: activeEditorSlot),
                            customLabel: customLabelBinding(for: activeEditorSlot),
                            searchText: searchBinding(for: activeEditorSlot),
                            onDone: { self.activeEditorSlot = nil }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ], spacing: 10) {
                        QuickSettingChip(
                            title: settings.use24HourClock ? "24h" : "12h",
                            subtitle: "Clock mode",
                            isOn: $settings.use24HourClock,
                            palette: palette
                        )

                        QuickSettingChip(
                            title: settings.showSeconds ? "Seconds On" : "Seconds Off",
                            subtitle: "Precision",
                            isOn: $settings.showSeconds,
                            palette: palette
                        )

                        if settings.enableWeather {
                            QuickSettingChip(
                                title: settings.showWeatherInMenuBar ? "Weather Icons" : "Ambient Icons",
                                subtitle: "Menu bar",
                                isOn: $settings.showWeatherInMenuBar,
                                palette: palette
                            )
                        }
                    }

                    if settings.enableWeather, let attribution = weatherStore.attribution {
                        WeatherAttributionFooterView(attribution: attribution)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(width: 452)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 30, x: 0, y: 18)
            .onAppear {
                onContentHeightChange(preferredPopoverHeight)
            }
            .onChange(of: preferredPopoverHeight) { newValue in
                onContentHeightChange(newValue)
            }
        }
    }

    private func toggleEditor(_ slot: ClockSlot) {
        activeEditorSlot = activeEditorSlot == slot ? nil : slot
    }

    private func selectedTimeZoneBinding(for slot: ClockSlot) -> Binding<String> {
        switch slot {
        case .primary:
            return $settings.primaryTimeZoneID
        case .secondary:
            return $settings.secondaryTimeZoneID
        }
    }

    private func customLabelBinding(for slot: ClockSlot) -> Binding<String> {
        switch slot {
        case .primary:
            return $settings.primaryCustomLabel
        case .secondary:
            return $settings.secondaryCustomLabel
        }
    }

    private func searchBinding(for slot: ClockSlot) -> Binding<String> {
        switch slot {
        case .primary:
            return $primarySearchText
        case .secondary:
            return $secondarySearchText
        }
    }
}

private struct PopoverPalette {
    let backgroundColors: [Color]
    let orbPrimary: Color
    let orbSecondary: Color
    let cardFill: Color
    let cardStroke: Color
    let chipOffFill: Color
    let chipOnFill: Color
    let chromeFill: Color
    let chromeStroke: Color
    let badgeFill: Color
    let badgeStroke: Color

    static func make(for appearanceMode: AppearanceMode, systemColorScheme: ColorScheme) -> PopoverPalette {
        let colorScheme: ColorScheme
        switch appearanceMode {
        case .system:
            colorScheme = systemColorScheme
        case .light:
            colorScheme = .light
        case .dark:
            colorScheme = .dark
        }

        switch colorScheme {
        case .dark:
            return PopoverPalette(
                backgroundColors: [
                    Color(red: 0.14, green: 0.17, blue: 0.22),
                    Color(red: 0.12, green: 0.18, blue: 0.30),
                    Color(red: 0.17, green: 0.15, blue: 0.24),
                ],
                orbPrimary: Color.white.opacity(0.08),
                orbSecondary: Color.blue.opacity(0.16),
                cardFill: Color.white.opacity(0.08),
                cardStroke: Color.white.opacity(0.12),
                chipOffFill: Color.white.opacity(0.07),
                chipOnFill: Color.white.opacity(0.12),
                chromeFill: Color.white.opacity(0.08),
                chromeStroke: Color.white.opacity(0.14),
                badgeFill: Color.white.opacity(0.08),
                badgeStroke: Color.white.opacity(0.12)
            )
        default:
            return PopoverPalette(
                backgroundColors: [
                    Color.white.opacity(0.76),
                    Color(red: 0.84, green: 0.90, blue: 0.98).opacity(0.78),
                    Color(red: 0.95, green: 0.93, blue: 1).opacity(0.72),
                ],
                orbPrimary: Color.white.opacity(0.32),
                orbSecondary: Color.blue.opacity(0.14),
                cardFill: Color.white.opacity(0.24),
                cardStroke: Color.white.opacity(0.26),
                chipOffFill: Color.white.opacity(0.18),
                chipOnFill: Color.white.opacity(0.34),
                chromeFill: Color.white.opacity(0.20),
                chromeStroke: Color.white.opacity(0.22),
                badgeFill: Color.white.opacity(0.16),
                badgeStroke: Color.white.opacity(0.18)
            )
        }
    }
}

private struct PopoverBackdrop: View {
    let palette: PopoverPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.orbPrimary)
                .frame(width: 220, height: 220)
                .offset(x: -120, y: -110)
                .blur(radius: 20)

            Circle()
                .fill(palette.orbSecondary)
                .frame(width: 240, height: 240)
                .offset(x: 120, y: 70)
                .blur(radius: 24)
        }
        .background(.ultraThinMaterial)
    }
}

private struct CompactGlassButton: View {
    let symbol: String
    let palette: PopoverPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.chromeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.chromeStroke, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickSettingChip: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let palette: PopoverPalette

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? palette.chipOnFill : palette.chipOffFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.chromeStroke.opacity(isOn ? 1 : 0.7), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ClockCardView: View {
    let slot: ClockSlot
    let title: String
    let label: String
    let timeZoneID: String
    @ObservedObject var settings: ClockSettingsStore
    let weatherState: WeatherState
    let date: Date
    let isEditing: Bool
    let palette: PopoverPalette

    private var timeFontSize: CGFloat {
        if settings.showSeconds {
            return settings.use24HourClock ? 46 : 40
        }

        return settings.use24HourClock ? 54 : 50
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: ClockFormatter.cardIconName(for: date, timeZoneID: timeZoneID, weatherState: weatherState))
                        .font(.system(size: 15, weight: .semibold))
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(.primary.opacity(0.86))

                Spacer()

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(ClockFormatter.timeText(for: date, timeZoneID: timeZoneID, settings: settings))
                .font(.system(size: timeFontSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)

            Text(ClockFormatter.dateText(for: date, timeZoneID: timeZoneID, settings: settings))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                let metaText = ClockFormatter.metaText(for: date, timeZoneID: timeZoneID, settings: settings)
                if !metaText.isEmpty {
                    CapsuleInfoBadge(text: metaText, palette: palette)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            WeatherSummaryView(
                slot: slot,
                settings: settings,
                weatherState: weatherState
            )
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)

            Text(isEditing ? "Editing from popover" : "Click to change city")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            minHeight: settings.enableWeather ? 270 : 220,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isEditing ? palette.chipOnFill : palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isEditing ? Color.accentColor.opacity(0.35) : palette.cardStroke, lineWidth: 1)
        )
    }
}

private struct InlineTimeZoneEditorView: View {
    let title: String
    @Binding var selectedTimeZoneID: String
    @Binding var customLabel: String
    @Binding var searchText: String
    let onDone: () -> Void
    @State private var useCustomLabel: Bool

    init(
        title: String,
        selectedTimeZoneID: Binding<String>,
        customLabel: Binding<String>,
        searchText: Binding<String>,
        onDone: @escaping () -> Void
    ) {
        self.title = title
        _selectedTimeZoneID = selectedTimeZoneID
        _customLabel = customLabel
        _searchText = searchText
        self.onDone = onDone
        _useCustomLabel = State(
            initialValue: !customLabel.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var filteredOptions: [TimeZoneOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return suggestedOptions
        }

        return Array(
            TimeZoneCatalog.options
                .filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
                .prefix(8)
        )
    }

    private var suggestedOptions: [TimeZoneOption] {
        let preferredIDs = [
            selectedTimeZoneID,
            TimeZone.current.identifier,
            "America/Chicago",
            "America/New_York",
            "Europe/London",
            "Asia/Karachi",
            "Asia/Dubai",
            "Asia/Singapore",
        ]

        var seen = Set<String>()
        return preferredIDs.compactMap { identifier in
            guard seen.insert(identifier).inserted else { return nil }
            return TimeZoneCatalog.option(for: identifier)
        }
    }

    private var selectedOption: TimeZoneOption? {
        TimeZoneCatalog.option(for: selectedTimeZoneID)
    }

    private func useCurrentTimeZone() {
        selectedTimeZoneID = TimeZone.current.identifier
        searchText = ""
        onDone()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: useCurrentTimeZone) {
                    Image(systemName: "location.fill")
                }
                .buttonStyle(SecondaryGlassButtonStyle())
                .help("Use current time zone")
                Button("Done", action: onDone)
                    .buttonStyle(SecondaryGlassButtonStyle())
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedOption?.cityName ?? selectedTimeZoneID)
                        .font(.system(size: 13, weight: .semibold))
                    Text(selectedOption?.id ?? selectedTimeZoneID)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Custom Name", isOn: $useCustomLabel)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if useCustomLabel {
                TextField("Custom label", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Search time zone", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Start typing to search, or pick from the suggested cities below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(filteredOptions) { option in
                    Button {
                        selectedTimeZoneID = option.id
                        onDone()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(option.id)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTimeZoneID == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                }
            }
            .listStyle(.inset)
            .frame(height: 170)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onChange(of: useCustomLabel) { isEnabled in
            if !isEnabled {
                customLabel = ""
            }
        }
        .onChange(of: selectedTimeZoneID) { _ in
            if !useCustomLabel {
                customLabel = ""
            }
        }
    }
}

private struct CapsuleInfoBadge: View {
    let text: String
    let palette: PopoverPalette

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(palette.badgeFill)
            )
            .overlay(
                Capsule()
                    .stroke(palette.badgeStroke, lineWidth: 0.8)
            )
    }
}

private struct WeatherSummaryView: View {
    let slot: ClockSlot
    @ObservedObject var settings: ClockSettingsStore
    let weatherState: WeatherState

    var body: some View {
        if settings.enableWeather {
            Group {
                switch weatherState {
                case .idle:
                    EmptyView()
                case .loading:
                    Label("Loading weather", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                case let .loaded(snapshot):
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: snapshot.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(snapshot.temperatureText) • \(snapshot.conditionText)")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            if settings.showWeatherLocation || settings.showFeelsLikeTemperature {
                                Text(detailText(for: snapshot))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case let .failed(message):
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.top, 2)
        }
    }

    private func detailText(for snapshot: WeatherSnapshot) -> String {
        var parts: [String] = []

        if settings.showWeatherLocation {
            parts.append(snapshot.resolvedLocationName)
        }

        if settings.showFeelsLikeTemperature {
            parts.append("Feels like \(snapshot.feelsLikeText)")
        }

        return parts.joined(separator: " • ")
    }
}

private struct WeatherAttributionFooterView: View {
    let attribution: WeatherAttributionSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 14)
                default:
                    Text("Apple Weather")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Link("Legal", destination: attribution.legalPageURL)
                .font(.system(size: 10))
        }
        .padding(.top, 4)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: ClockSettingsStore
    @ObservedObject var weatherStore: WeatherStore
    @State private var primarySearchText = ""
    @State private var secondarySearchText = ""
    @State private var selectedPane: SettingsPane? = .overview

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                SettingsSidebarRow(pane: pane)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 215, ideal: 235)
            .listStyle(.sidebar)
        } detail: {
            if selectedPane == .overview {
                SettingsOverviewPane(settings: settings, weatherStore: weatherStore)
            } else if let selectedPane {
                SettingsPaneContainer(pane: selectedPane) {
                    detailView(for: selectedPane)
                }
            } else {
                SettingsOverviewPane(settings: settings, weatherStore: weatherStore)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .overview:
            SettingsOverviewPane(settings: settings, weatherStore: weatherStore)
        case .timeZones:
            TimeZonesPane(
                settings: settings,
                primarySearchText: $primarySearchText,
                secondarySearchText: $secondarySearchText
            )
        case .menuBar:
            MenuBarPane(settings: settings)
        case .details:
            DetailsPane(settings: settings)
        case .weather:
            WeatherPane(settings: settings)
        case .appearance:
            AppearancePane(settings: settings)
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case timeZones = "Time Zones"
    case menuBar = "Menu Bar"
    case details = "Clock Details"
    case weather = "Weather"
    case appearance = "Appearance"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .timeZones: return "globe.americas"
        case .menuBar: return "menubar.rectangle"
        case .details: return "list.bullet.rectangle.portrait"
        case .weather: return "cloud.sun"
        case .appearance: return "square.3.layers.3d.top.filled"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Live preview and app summary"
        case .timeZones: return "Cities, labels, and ordering"
        case .menuBar: return "Compact top bar behavior"
        case .details: return "Metadata and badges"
        case .weather: return "Weather synced with each clock"
        case .appearance: return "Popover mood and polish"
        }
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(pane.rawValue, systemImage: pane.icon)
                .font(.system(size: 13, weight: .semibold))
            Text(pane.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 25)
        }
        .padding(.vertical, 3)
    }
}

private struct SettingsPaneContainer<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.rawValue)
                        .font(.system(size: 28, weight: .semibold))
                    Text(pane.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsOverviewPane: View {
    @ObservedObject var settings: ClockSettingsStore
    @ObservedObject var weatherStore: WeatherStore

    private let metricColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
                overviewContent(now: context.date)
                    .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func overviewContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            OverviewHeroHeader(settings: settings, now: now)

            HStack(alignment: .top, spacing: 18) {
                OverviewWeatherCard(
                    title: "Primary",
                    timeZoneID: settings.primaryTimeZoneID,
                    label: settings.displayLabel(
                        for: settings.primaryTimeZoneID,
                        customLabel: settings.primaryCustomLabel
                    ),
                    isVisible: settings.showPrimaryClock,
                    now: now,
                    settings: settings,
                    weatherState: weatherStore.state(for: .primary)
                )

                OverviewWeatherCard(
                    title: "Secondary",
                    timeZoneID: settings.secondaryTimeZoneID,
                    label: settings.displayLabel(
                        for: settings.secondaryTimeZoneID,
                        customLabel: settings.secondaryCustomLabel
                    ),
                    isVisible: settings.showSecondaryClock,
                    now: now,
                    settings: settings,
                    weatherState: weatherStore.state(for: .secondary)
                )
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                ForEach(metrics(now: now)) { metric in
                    OverviewMetricTile(metric: metric)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metrics(now: Date) -> [OverviewMetricDescriptor] {
        let liveWeatherCount = [weatherStore.state(for: .primary), weatherStore.state(for: .secondary)]
            .reduce(0) { partialResult, state in
                if case .loaded = state {
                    return partialResult + 1
                }
                return partialResult
            }
        let systemZone = TimeZone.current.identifier.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? "Local"

        return [
            OverviewMetricDescriptor(
                icon: "menubar.rectangle",
                title: "Menu Bar",
                value: ClockFormatter.menuBarTitle(for: now, settings: settings),
                caption: settings.showWeatherInMenuBar ? "Weather icons" : "Ambient icons"
            ),
            OverviewMetricDescriptor(
                icon: settings.enableWeather ? "cloud.sun.fill" : "cloud.slash",
                title: "Weather",
                value: settings.enableWeather ? "\(liveWeatherCount)/2 Live" : "Off",
                caption: settings.enableWeather ? "Graceful fallback enabled" : "Chronos-only mode"
            ),
            OverviewMetricDescriptor(
                icon: "clock.arrow.circlepath",
                title: "Clock Mode",
                value: settings.use24HourClock ? "24h" : "12h",
                caption: settings.showSeconds ? "Seconds live" : "Minute precision"
            ),
            OverviewMetricDescriptor(
                icon: "location.circle",
                title: "System Zone",
                value: systemZone,
                caption: TimeZone.current.identifier
            ),
        ]
    }
}

private struct OverviewHeroHeader: View {
    @ObservedObject var settings: ClockSettingsStore
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsAppIconView(size: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text("Orpyt")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("A live overview for your active clocks.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    OverviewInlineTag(title: "Menu Bar", value: ClockFormatter.menuBarTitle(for: now, settings: settings))
                    OverviewInlineTag(title: "Mode", value: settings.use24HourClock ? "24h" : "12h")
                    OverviewInlineTag(title: "Weather", value: settings.enableWeather ? "On" : "Off")
                }
            }

            Spacer()

            OverviewInlineTag(title: "Appearance", value: settings.appearanceMode.title)
        }
    }
}

private struct OverviewInlineTag: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct OverviewMetricDescriptor: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let caption: String
}

private struct OverviewMetricTile: View {
    let metric: OverviewMetricDescriptor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: metric.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(metric.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(metric.value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(metric.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Color.accentColor.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 0.8)
        )
    }
}

private struct OverviewWeatherCard: View {
    let title: String
    let timeZoneID: String
    let label: String
    let isVisible: Bool
    let now: Date
    @ObservedObject var settings: ClockSettingsStore
    let weatherState: WeatherState

    private var theme: OverviewCardTheme {
        OverviewCardTheme(date: now, timeZoneID: timeZoneID, weatherState: weatherState)
    }

    private var cityName: String {
        TimeZoneCatalog.option(for: timeZoneID)?.cityName ?? timeZoneID
    }

    private var cardIconName: String {
        ClockFormatter.cardIconName(for: now, timeZoneID: timeZoneID, weatherState: weatherState)
    }

    private var weatherSummary: String {
        switch weatherState {
        case let .loaded(snapshot):
            return "\(snapshot.conditionText) • \(snapshot.temperatureText)"
        case .loading:
            return "Refreshing live conditions"
        case let .failed(message):
            return settings.enableWeather ? message : ambientSummary
        case .idle:
            return ambientSummary
        }
    }

    private var ambientSummary: String {
        let hour = Calendar.current.dateComponents(in: TimeZone(identifier: timeZoneID) ?? .current, from: now).hour ?? 12
        switch hour {
        case 6..<11:
            return "Morning light"
        case 11..<17:
            return "Daylight active"
        case 17..<21:
            return "Evening transition"
        default:
            return "Night cycle"
        }
    }

    private var footerItems: [(String, String)] {
        let offset = OverviewCardTheme.gmtOffsetText(for: timeZoneID, date: now)
        let status = isVisible ? "Active" : "Hidden"
        return [
            ("globe", offset),
            (isVisible ? "eye" : "eye.slash", status),
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(theme.background)

            OverviewAnimatedSky(theme: theme)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(theme.stroke, lineWidth: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cityName)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        Image(systemName: cardIconName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.accent)

                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                Spacer(minLength: 34)

                Text(ClockFormatter.timeText(for: now, timeZoneID: timeZoneID, settings: settings))
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text(weatherSummary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 14)

                Spacer()

                Rectangle()
                    .fill(theme.stroke.opacity(0.7))
                    .frame(height: 1)
                    .padding(.bottom, 12)

                HStack(spacing: 14) {
                    ForEach(Array(footerItems.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Image(systemName: item.0)
                                .font(.system(size: 10, weight: .semibold))
                            Text(item.1)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 348, alignment: .topLeading)
        .shadow(color: theme.shadow, radius: 24, x: 0, y: 14)
        .opacity(isVisible ? 1 : 0.82)
    }
}

@MainActor
private struct OverviewCardTheme {
    enum Kind {
        case daylight
        case cloud
        case rain
        case snow
        case night
        case storm
    }

    let kind: Kind
    let background: LinearGradient
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let stroke: Color
    let shadow: Color

    init(date: Date, timeZoneID: String, weatherState: WeatherState) {
        let kind = Self.kind(for: date, timeZoneID: timeZoneID, weatherState: weatherState)
        self.kind = kind

        switch kind {
        case .daylight:
            background = LinearGradient(
                colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.86, green: 0.91, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = Color(red: 0.10, green: 0.16, blue: 0.24)
            secondaryText = Color(red: 0.25, green: 0.35, blue: 0.48)
            accent = Color(red: 0.18, green: 0.50, blue: 1.0)
            stroke = Color.white.opacity(0.65)
            shadow = Color.blue.opacity(0.10)
        case .cloud:
            background = LinearGradient(
                colors: [Color(red: 0.92, green: 0.95, blue: 0.99), Color(red: 0.82, green: 0.87, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = Color(red: 0.12, green: 0.16, blue: 0.22)
            secondaryText = Color(red: 0.32, green: 0.38, blue: 0.48)
            accent = Color(red: 0.32, green: 0.47, blue: 0.70)
            stroke = Color.white.opacity(0.60)
            shadow = Color.black.opacity(0.08)
        case .rain:
            background = LinearGradient(
                colors: [Color(red: 0.28, green: 0.32, blue: 0.40), Color(red: 0.18, green: 0.21, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = .white
            secondaryText = Color.white.opacity(0.78)
            accent = Color(red: 0.69, green: 0.84, blue: 1.0)
            stroke = Color.white.opacity(0.12)
            shadow = Color.black.opacity(0.18)
        case .snow:
            background = LinearGradient(
                colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.88, green: 0.92, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = Color(red: 0.12, green: 0.18, blue: 0.28)
            secondaryText = Color(red: 0.38, green: 0.46, blue: 0.58)
            accent = Color(red: 0.24, green: 0.50, blue: 1.0)
            stroke = Color.white.opacity(0.72)
            shadow = Color.blue.opacity(0.10)
        case .night:
            background = LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.15), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = .white
            secondaryText = Color.white.opacity(0.74)
            accent = Color(red: 0.64, green: 0.67, blue: 1.0)
            stroke = Color.white.opacity(0.10)
            shadow = Color.black.opacity(0.25)
        case .storm:
            background = LinearGradient(
                colors: [Color(red: 0.15, green: 0.18, blue: 0.29), Color(red: 0.08, green: 0.08, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = .white
            secondaryText = Color.white.opacity(0.78)
            accent = Color(red: 0.68, green: 0.79, blue: 1.0)
            stroke = Color.white.opacity(0.10)
            shadow = Color.black.opacity(0.24)
        }
    }

    private static func kind(for date: Date, timeZoneID: String, weatherState: WeatherState) -> Kind {
        let descriptor: String

        switch weatherState {
        case let .loaded(snapshot):
            descriptor = "\(snapshot.symbolName) \(snapshot.conditionText)".lowercased()
        default:
            descriptor = ClockFormatter.cardIconName(for: date, timeZoneID: timeZoneID, weatherState: weatherState).lowercased()
        }

        if descriptor.contains("bolt") || descriptor.contains("thunder") {
            return .storm
        }
        if descriptor.contains("snow") {
            return .snow
        }
        if descriptor.contains("rain") || descriptor.contains("drizzle") {
            return .rain
        }
        if descriptor.contains("moon") || descriptor.contains("night") || descriptor.contains("stars") {
            return .night
        }
        if descriptor.contains("cloud") || descriptor.contains("fog") || descriptor.contains("overcast") {
            return .cloud
        }
        return .daylight
    }

    static func gmtOffsetText(for timeZoneID: String, date: Date) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return "GMT"
        }

        let seconds = timeZone.secondsFromGMT(for: date)
        let hours = seconds / 3600
        let minutes = abs((seconds / 60) % 60)
        return String(format: "GMT%+.2d:%02d", hours, minutes)
    }
}

private struct OverviewAnimatedSky: View {
    let theme: OverviewCardTheme

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 18.0)) { context in
            GeometryReader { geometry in
                let phase = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    driftingOrbs(size: geometry.size, phase: phase)
                    animatedLayer(size: geometry.size, phase: phase)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
    }

    private func driftingOrbs(size: CGSize, phase: Double) -> some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(theme.kind == .night ? 0.10 : 0.12))
                .frame(width: size.width * 0.60, height: size.width * 0.60)
                .blur(radius: 10)
                .offset(
                    x: CGFloat(cos(phase * 0.3) * 18),
                    y: CGFloat(sin(phase * 0.25) * 16) - 52
                )

            Circle()
                .fill(Color.white.opacity(theme.kind == .night ? 0.04 : 0.10))
                .frame(width: size.width * 0.36, height: size.width * 0.36)
                .blur(radius: 8)
                .offset(
                    x: size.width * 0.22 + CGFloat(sin(phase * 0.34) * 14),
                    y: -size.height * 0.20 + CGFloat(cos(phase * 0.28) * 10)
                )
        }
    }

    @ViewBuilder
    private func animatedLayer(size: CGSize, phase: Double) -> some View {
        switch theme.kind {
        case .daylight:
            sunlightLayer(size: size, phase: phase)
        case .cloud:
            cloudLayer(size: size, phase: phase)
        case .rain:
            ZStack {
                cloudLayer(size: size, phase: phase)
                rainLayer(size: size, phase: phase, intensity: 10)
            }
        case .snow:
            ZStack {
                cloudLayer(size: size, phase: phase)
                snowLayer(size: size, phase: phase)
            }
        case .night:
            starsLayer(size: size, phase: phase)
        case .storm:
            ZStack {
                cloudLayer(size: size, phase: phase)
                rainLayer(size: size, phase: phase, intensity: 13)
                stormPulse(size: size, phase: phase)
            }
        }
    }

    private func sunlightLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(0.22))
                .frame(width: size.width * 0.28, height: size.width * 0.28)
                .blur(radius: 4)
                .offset(x: size.width * 0.22, y: -size.height * 0.18)
                .scaleEffect(1 + CGFloat(sin(phase * 1.5)) * 0.05)

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: size.width * 0.40, height: size.width * 0.40)
                .offset(x: size.width * 0.22, y: -size.height * 0.18)
                .scaleEffect(1 + CGFloat(cos(phase * 1.2)) * 0.04)
        }
    }

    private func cloudLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(theme.kind == .rain || theme.kind == .storm ? 0.10 : 0.16))
                    .frame(width: size.width * 0.28, height: size.height * 0.10)
                    .blur(radius: 6)
                    .offset(
                        x: CGFloat(-20 + index * 48) + CGFloat(sin(phase * 0.32 + Double(index)) * 16),
                        y: CGFloat(-92 + index * 8)
                    )
            }
        }
    }

    private func rainLayer(size: CGSize, phase: Double, intensity: Int) -> some View {
        ZStack {
            ForEach(0..<intensity, id: \.self) { index in
                Capsule()
                    .fill(theme.accent.opacity(0.35))
                    .frame(width: 2, height: CGFloat(22 + (index % 3) * 6))
                    .rotationEffect(.degrees(18))
                    .offset(
                        x: CGFloat(
                            (phase * 84 + Double(index * 37))
                                .truncatingRemainder(dividingBy: Double(size.width + 110))
                        ) - size.width * 0.55,
                        y: CGFloat(
                            (phase * 160 + Double(index * 53))
                                .truncatingRemainder(dividingBy: Double(size.height + 150))
                        ) - size.height * 0.55
                    )
            }
        }
    }

    private func snowLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: CGFloat(4 + (index % 3)), height: CGFloat(4 + (index % 3)))
                    .offset(
                        x: CGFloat(
                            (phase * 26 + Double(index * 41) + sin(phase + Double(index)) * 18)
                                .truncatingRemainder(dividingBy: Double(size.width + 100))
                        ) - size.width * 0.52,
                        y: CGFloat(
                            (phase * 72 + Double(index * 29))
                                .truncatingRemainder(dividingBy: Double(size.height + 130))
                        ) - size.height * 0.52
                    )
            }
        }
    }

    private func starsLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.7 + 0.25 * sin(phase * 1.4 + Double(index))))
                    .frame(width: CGFloat(index % 3 == 0 ? 3.5 : 2.4), height: CGFloat(index % 3 == 0 ? 3.5 : 2.4))
                    .offset(
                        x: CGFloat((index * 31) % Int(max(size.width - 40, 1))) - size.width / 2 + 20,
                        y: CGFloat((index * 27) % Int(max(size.height * 0.55, 1))) - size.height / 2 + 28
                    )
            }
        }
    }

    private func stormPulse(size: CGSize, phase: Double) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.10 + max(0, sin(phase * 3.8)) * 0.22))
            .frame(width: size.width * 0.18, height: 14)
            .blur(radius: 6)
            .rotationEffect(.degrees(-22))
            .offset(x: size.width * 0.12, y: -size.height * 0.06)
    }
}

private struct SettingsAppIconView: View {
    let size: CGFloat

    var body: some View {
        iconContent
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var iconContent: some View {
        if let logoImage = AppAssetLoader.logoImage() {
            Image(nsImage: logoImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else if let appIcon = NSApplication.shared.applicationIconImage, appIcon.size.width > 0 {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Image(systemName: "clock.badge.checkmark.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.22)
                .foregroundStyle(.tint)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private enum AppAssetLoader {
    static func logoImage() -> NSImage? {
        for fileName in ["logo.png", "orpyt-logo.png", "Orpyt.icns"] {
            if let url = Bundle.main.resourceURL?.appendingPathComponent(fileName),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}

private struct TimeZonesPane: View {
    @ObservedObject var settings: ClockSettingsStore
    @Binding var primarySearchText: String
    @Binding var secondarySearchText: String
    @State private var selectedSlot: ClockSlot = .primary

    var body: some View {
        Group {
            SettingsSection(title: "Clock") {
                Picker("Clock", selection: $selectedSlot) {
                    Text("Primary").tag(ClockSlot.primary)
                    Text("Secondary").tag(ClockSlot.secondary)
                }
                .pickerStyle(.segmented)
            }

            SettingsSection(title: "Location") {
                TimeZonePickerCard(
                    title: selectedSlot == .primary ? "Primary Clock" : "Secondary Clock",
                    customLabel: selectedSlot == .primary ? $settings.primaryCustomLabel : $settings.secondaryCustomLabel,
                    selectedTimeZoneID: selectedSlot == .primary ? $settings.primaryTimeZoneID : $settings.secondaryTimeZoneID,
                    searchText: selectedSlot == .primary ? $primarySearchText : $secondarySearchText
                )
            }

            SettingsSection(title: "Actions") {
                HStack {
                    Spacer()
                    Button("Swap Primary and Secondary") {
                        settings.swapTimeZones()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct MenuBarPane: View {
    @ObservedObject var settings: ClockSettingsStore

    var body: some View {
        SettingsSection(title: "Displayed in Menu Bar") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(title: "Show primary clock", subtitle: "Keep the first city visible in the menu bar.", isOn: $settings.showPrimaryClock)
                SettingsToggleRow(title: "Show secondary clock", subtitle: "Keep the second city visible in the menu bar.", isOn: $settings.showSecondaryClock)
                SettingsToggleRow(title: "Show zone labels", subtitle: "Display short city labels beside the time.", isOn: $settings.showZoneLabelInMenuBar)
                SettingsToggleRow(title: "Show ambient icon", subtitle: "Use day or night iconography in the menu bar.", isOn: $settings.showStatusIcon)
                SettingsToggleRow(title: "Use 24-hour time", subtitle: "Switch between 12-hour and 24-hour formats.", isOn: $settings.use24HourClock)
                SettingsToggleRow(title: "Show seconds", subtitle: "Update the top bar every second.", isOn: $settings.showSeconds)
            }
        }
    }
}

private struct DetailsPane: View {
    @ObservedObject var settings: ClockSettingsStore

    var body: some View {
        SettingsSection(title: "Metadata") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(title: "Show weekday", subtitle: "Include weekday in the detailed card.", isOn: $settings.showWeekday)
                SettingsToggleRow(title: "Show date", subtitle: "Include day and month in the detail view.", isOn: $settings.showDate)
                SettingsToggleRow(title: "Show time zone abbreviation", subtitle: "Display labels like EDT or BST.", isOn: $settings.showTimeZoneAbbreviation)
                SettingsToggleRow(title: "Show GMT offset", subtitle: "Show numeric GMT offset badges.", isOn: $settings.showGMTOffset)
            }
        }
    }
}

private struct WeatherPane: View {
    @ObservedObject var settings: ClockSettingsStore

    var body: some View {
        SettingsSection(title: "Weather") {
            VStack(alignment: .leading, spacing: 14) {
                SettingsToggleRow(title: "Enable live weather", subtitle: "Attach live weather to each clock.", isOn: $settings.enableWeather)
                SettingsToggleRow(title: "Use weather icons", subtitle: "Switch the menu bar icon mode from ambient to weather.", isOn: $settings.showWeatherInMenuBar)
                    .opacity(settings.enableWeather ? 1 : 0.55)
                SettingsToggleRow(title: "Show location in cards", subtitle: "Display the resolved city below the condition.", isOn: $settings.showWeatherLocation)
                    .opacity(settings.enableWeather ? 1 : 0.55)
                SettingsToggleRow(title: "Show feels like temperature", subtitle: "Include apparent temperature in the card details.", isOn: $settings.showFeelsLikeTemperature)
                    .opacity(settings.enableWeather ? 1 : 0.55)

                Text("Weather follows each selected clock city automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject var settings: ClockSettingsStore

    var body: some View {
        SettingsSection(title: "Popover Appearance") {
            Picker("Appearance", selection: Binding(
                get: { settings.appearanceMode },
                set: { settings.appearanceMode = $0 }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("This changes the menu bar popover only. Settings always follow macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.regular)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor),
                                Color.accentColor.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
            )
            .padding(.vertical, 4)
        } header: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

private final class OrpytSettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct GlossyInputGroup<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimeZonePickerCard: View {
    let title: String
    @Binding var customLabel: String
    @Binding var selectedTimeZoneID: String
    @Binding var searchText: String
    @State private var useCustomLabel: Bool

    init(
        title: String,
        customLabel: Binding<String>,
        selectedTimeZoneID: Binding<String>,
        searchText: Binding<String>
    ) {
        self.title = title
        _customLabel = customLabel
        _selectedTimeZoneID = selectedTimeZoneID
        _searchText = searchText
        _useCustomLabel = State(
            initialValue: !customLabel.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var filteredOptions: [TimeZoneOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return suggestedOptions
        }

        return Array(
            TimeZoneCatalog.options.filter { option in
                option.searchableText.localizedCaseInsensitiveContains(query)
            }
            .prefix(80)
        )
    }

    private var suggestedOptions: [TimeZoneOption] {
        let preferredIDs = [
            selectedTimeZoneID,
            TimeZone.current.identifier,
            "America/New_York",
            "America/Los_Angeles",
            "Europe/London",
            "Europe/Paris",
            "Asia/Dubai",
            "Asia/Karachi",
            "Asia/Kolkata",
            "Asia/Singapore",
            "Asia/Tokyo",
            "Australia/Sydney",
        ]

        var seen = Set<String>()
        return preferredIDs.compactMap { identifier in
            guard seen.insert(identifier).inserted else { return nil }
            return TimeZoneCatalog.option(for: identifier)
        }
    }

    private var selectedOption: TimeZoneOption? {
        TimeZoneCatalog.option(for: selectedTimeZoneID)
    }

    private func useCurrentTimeZone() {
        selectedTimeZoneID = TimeZone.current.identifier
        searchText = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Use Current Time Zone", action: useCurrentTimeZone)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedOption?.cityName ?? selectedTimeZoneID)
                        .font(.system(size: 13, weight: .semibold))
                    Text(selectedOption?.id ?? selectedTimeZoneID)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Custom Name", isOn: $useCustomLabel)
                    .controlSize(.small)
            }

            if useCustomLabel {
                TextField("Custom label", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Search time zone", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Suggested cities are shown first. Start typing to search the full time zone list.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(filteredOptions) { option in
                    Button {
                        selectedTimeZoneID = option.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(option.id)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedTimeZoneID == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                }
            }
            .listStyle(.inset)
            .frame(height: 280)
        }
        .padding(.top, 2)
        .onChange(of: useCustomLabel) { isEnabled in
            if !isEnabled {
                customLabel = ""
            }
        }
        .onChange(of: selectedTimeZoneID) { _ in
            if !useCustomLabel {
                customLabel = ""
            }
        }
    }
}

private struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 0.92))
            )
            .foregroundStyle(.white)
    }
}

private struct SecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.26 : 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            )
    }
}

@MainActor
private enum ClockFormatter {
    private static var formatterCache: [String: DateFormatter] = [:]

    static func menuBarAttributedTitle(
        for date: Date,
        settings: ClockSettingsStore,
        weatherStore: WeatherStore
    ) -> NSAttributedString {
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let titleColor = NSColor.labelColor
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
        ]

        let segments = visibleClockDescriptors(for: settings).map { descriptor in
            (
                label: settings.displayLabel(for: descriptor.timeZoneID, customLabel: descriptor.customLabel),
                timeZoneID: descriptor.timeZoneID,
                slot: descriptor.slot
            )
        }

        guard !segments.isEmpty else {
            return NSAttributedString(string: "Orpyt", attributes: textAttributes)
        }

        let result = NSMutableAttributedString()

        for (index, segment) in segments.enumerated() {
            let weatherState = weatherStore.state(for: segment.slot)

            if let attachment = statusAttachment(
                for: date,
                timeZoneID: segment.timeZoneID,
                weatherState: weatherState,
                settings: settings,
                font: titleFont
            ) {
                result.append(attachment)
                result.append(NSAttributedString(string: " ", attributes: textAttributes))
            }

            result.append(
                NSAttributedString(
                    string: menuBarSegment(
                        for: date,
                        timeZoneID: segment.timeZoneID,
                        label: segment.label,
                        settings: settings
                    ),
                    attributes: textAttributes
                )
            )

            if index < segments.count - 1 {
                result.append(NSAttributedString(string: " | ", attributes: textAttributes))
            }
        }

        return result
    }

    static func menuBarTitle(for date: Date, settings: ClockSettingsStore) -> String {
        let segments = visibleSegments(for: date, settings: settings)
        return segments.isEmpty ? "Orpyt" : segments.joined(separator: " | ")
    }

    static func menuBarTooltip(for date: Date, settings: ClockSettingsStore, weatherStore: WeatherStore) -> String {
        let lines = visibleDetailLines(for: date, settings: settings, weatherStore: weatherStore)
        return lines.isEmpty ? "Orpyt" : lines.joined(separator: "\n")
    }

    static func timeText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
        let format = settings.use24HourClock
            ? (settings.showSeconds ? "HH:mm:ss" : "HH:mm")
            : (settings.showSeconds ? "h:mm:ss a" : "h:mm a")
        let formatter = formatter(for: timeZoneID, format: format)
        return formatter.string(from: date)
    }

    static func dateText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
        var formatParts: [String] = []
        if settings.showWeekday {
            formatParts.append("EEE")
        }
        if settings.showDate {
            formatParts.append("d MMM")
        }

        if formatParts.isEmpty {
            return ""
        }

        let formatter = formatter(for: timeZoneID, format: formatParts.joined(separator: ", "))
        return formatter.string(from: date)
    }

    static func metaText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
        var parts: [String] = []

        if settings.showTimeZoneAbbreviation, let abbreviation = TimeZone(identifier: timeZoneID)?.abbreviation(for: date) {
            parts.append(abbreviation)
        }

        if settings.showGMTOffset, let timeZone = TimeZone(identifier: timeZoneID) {
            parts.append(gmtOffsetText(for: timeZone, date: date))
        }

        return parts.joined(separator: "  ")
    }

    static func detailLine(
        for date: Date,
        timeZoneID: String,
        label: String,
        settings: ClockSettingsStore,
        weatherState: WeatherState
    ) -> String {
        var parts = [
            "\(label): \(timeText(for: date, timeZoneID: timeZoneID, settings: settings))",
        ]

        let date = dateText(for: date, timeZoneID: timeZoneID, settings: settings)
        if !date.isEmpty {
            parts.append(date)
        }

        if settings.enableWeather {
            switch weatherState {
            case let .loaded(snapshot):
                parts.append("\(snapshot.temperatureText), \(snapshot.conditionText)")
            case let .failed(message):
                parts.append(message)
            default:
                break
            }
        }

        return parts.joined(separator: " | ")
    }

    static func cardIconName(for date: Date, timeZoneID: String, weatherState: WeatherState) -> String {
        if case let .loaded(snapshot) = weatherState {
            return snapshot.symbolName
        }

        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return "clock"
        }

        let hour = Calendar.current.dateComponents(in: timeZone, from: date).hour ?? 12

        switch hour {
        case 6..<10:
            return "sunrise.fill"
        case 10..<17:
            return "sun.max.fill"
        case 17..<20:
            return "sunset.fill"
        default:
            return "moon.stars.fill"
        }
    }

    private static func menuBarSegment(for date: Date, timeZoneID: String, label: String, settings: ClockSettingsStore) -> String {
        let time = timeText(for: date, timeZoneID: timeZoneID, settings: settings)
        if settings.showZoneLabelInMenuBar {
            return "\(label) \(time)"
        }
        return time
    }

    private static func relativeDayText(for date: Date, timeZoneID: String) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return "" }

        var zoneCalendar = Calendar(identifier: .gregorian)
        zoneCalendar.timeZone = timeZone

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current

        let zoneDayStart = zoneCalendar.startOfDay(for: date)
        let localDayStart = localCalendar.startOfDay(for: date)

        let zoneDayInUTC = zoneDayStart.timeIntervalSince1970
        let localDayInUTC = localDayStart.timeIntervalSince1970
        let dayDifference = Int((zoneDayInUTC - localDayInUTC) / 86_400)

        switch dayDifference {
        case let diff where diff < 0:
            return "Yesterday"
        case 0:
            return "Today"
        case let diff where diff > 0:
            return "Tomorrow"
        default:
            return "Today"
        }
    }

    private static func gmtOffsetText(for timeZone: TimeZone, date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let hours = seconds / 3600
        let minutes = abs((seconds / 60) % 60)
        return String(format: "GMT%+.2d:%02d", hours, minutes)
    }

    private static func visibleSegments(for date: Date, settings: ClockSettingsStore) -> [String] {
        visibleClockDescriptors(for: settings).map { descriptor in
            menuBarSegment(
                for: date,
                timeZoneID: descriptor.timeZoneID,
                label: settings.displayLabel(
                    for: descriptor.timeZoneID,
                    customLabel: descriptor.customLabel
                ),
                settings: settings
            )
        }
    }

    private static func visibleDetailLines(for date: Date, settings: ClockSettingsStore, weatherStore: WeatherStore) -> [String] {
        visibleClockDescriptors(for: settings).map { descriptor in
            detailLine(
                for: date,
                timeZoneID: descriptor.timeZoneID,
                label: settings.displayLabel(
                    for: descriptor.timeZoneID,
                    customLabel: descriptor.customLabel
                ),
                settings: settings
                ,
                weatherState: weatherStore.state(for: descriptor.slot)
            )
        }
    }

    private static func visibleClockDescriptors(
        for settings: ClockSettingsStore
    ) -> [(slot: ClockSlot, timeZoneID: String, customLabel: String)] {
        var descriptors: [(slot: ClockSlot, timeZoneID: String, customLabel: String)] = []

        if settings.showPrimaryClock {
            descriptors.append(
                (slot: .primary, timeZoneID: settings.primaryTimeZoneID, customLabel: settings.primaryCustomLabel)
            )
        }

        if settings.showSecondaryClock {
            descriptors.append(
                (slot: .secondary, timeZoneID: settings.secondaryTimeZoneID, customLabel: settings.secondaryCustomLabel)
            )
        }

        return descriptors
    }

    private static func statusAttachment(
        for date: Date,
        timeZoneID: String,
        weatherState: WeatherState,
        settings: ClockSettingsStore,
        font: NSFont
    ) -> NSAttributedString? {
        let shouldShowWeatherIcon = settings.enableWeather && settings.showWeatherInMenuBar
        let shouldShowAmbientIcon = settings.showStatusIcon

        guard shouldShowWeatherIcon || shouldShowAmbientIcon else {
            return nil
        }

        let imageName: String

        if shouldShowWeatherIcon {
            imageName = cardIconName(for: date, timeZoneID: timeZoneID, weatherState: weatherState)
        } else {
            imageName = ambientIconName(for: date, timeZoneID: timeZoneID)
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 1, weight: .medium)

        guard let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Time status")?
            .withSymbolConfiguration(configuration) else {
            return nil
        }

        image.isTemplate = true

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: font.pointSize, height: font.pointSize)
        return NSAttributedString(attachment: attachment)
    }

    private static func ambientIconName(for date: Date, timeZoneID: String) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return "clock"
        }

        let hour = Calendar.current.dateComponents(in: timeZone, from: date).hour ?? 12

        switch hour {
        case 6..<10:
            return "sunrise.fill"
        case 10..<17:
            return "sun.max.fill"
        case 17..<20:
            return "sunset.fill"
        default:
            return "moon.stars.fill"
        }
    }

    private static func formatter(for timeZoneID: String, format: String) -> DateFormatter {
        let cacheKey = "\(timeZoneID)|\(format)"
        if let formatter = formatterCache[cacheKey] {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = format
        formatterCache[cacheKey] = formatter
        return formatter
    }
}

private enum TimeZoneCatalog {
    static let defaultPrimaryID = TimeZone.current.identifier
    static let defaultSecondaryID = "Europe/London"

    static let options: [TimeZoneOption] = {
        TimeZone.knownTimeZoneIdentifiers
            .compactMap { identifier -> TimeZoneOption? in
                guard let timeZone = TimeZone(identifier: identifier) else { return nil }
                let cityName = identifier.split(separator: "/").last?
                    .replacingOccurrences(of: "_", with: " ") ?? identifier
                let shortLabel = shortLabel(for: identifier, fallback: cityName)
                let offset = offsetText(for: timeZone)
                let displayName = "\(cityName) (\(offset))"
                return TimeZoneOption(
                    id: identifier,
                    shortLabel: shortLabel,
                    cityName: cityName,
                    displayName: displayName,
                    searchableText: "\(cityName) \(identifier) \(shortLabel) \(offset)"
                )
            }
            .sorted {
                if $0.utcOffsetSeconds == $1.utcOffsetSeconds {
                    return $0.displayName < $1.displayName
                }
                return $0.utcOffsetSeconds < $1.utcOffsetSeconds
            }
    }()

    static func option(for id: String) -> TimeZoneOption? {
        options.first(where: { $0.id == id })
    }

    static func weatherLookupName(for id: String) -> String {
        let overrides: [String: String] = [
            "America/Chicago": "Chicago, Illinois, USA",
            "America/Los_Angeles": "Los Angeles, California, USA",
            "America/New_York": "New York, New York, USA",
            "America/Toronto": "Toronto, Ontario, Canada",
            "Europe/London": "London, United Kingdom",
            "Europe/Paris": "Paris, France",
            "Europe/Berlin": "Berlin, Germany",
            "Asia/Dubai": "Dubai, United Arab Emirates",
            "Asia/Karachi": "Karachi, Pakistan",
            "Asia/Kolkata": "Kolkata, India",
            "Asia/Singapore": "Singapore",
            "Asia/Tokyo": "Tokyo, Japan",
            "Australia/Sydney": "Sydney, Australia",
        ]

        if let override = overrides[id] {
            return override
        }

        return option(for: id)?.cityName ?? id
    }

    static func representativeLocation(for id: String) -> CLLocation? {
        let coordinates: [String: (Double, Double)] = [
            "America/Chicago": (41.8781, -87.6298),
            "America/Los_Angeles": (34.0522, -118.2437),
            "America/New_York": (40.7128, -74.0060),
            "America/Toronto": (43.6532, -79.3832),
            "Europe/London": (51.5072, -0.1276),
            "Europe/Paris": (48.8566, 2.3522),
            "Europe/Berlin": (52.5200, 13.4050),
            "Asia/Dubai": (25.2048, 55.2708),
            "Asia/Karachi": (24.8607, 67.0011),
            "Asia/Kolkata": (22.5726, 88.3639),
            "Asia/Singapore": (1.3521, 103.8198),
            "Asia/Tokyo": (35.6762, 139.6503),
            "Australia/Sydney": (-33.8688, 151.2093),
        ]

        guard let coordinate = coordinates[id] else {
            return nil
        }

        return CLLocation(latitude: coordinate.0, longitude: coordinate.1)
    }

    private static func shortLabel(for identifier: String, fallback: String) -> String {
        let overrides: [String: String] = [
            "America/Los_Angeles": "LA",
            "America/New_York": "NYC",
            "Europe/London": "LON",
            "Asia/Karachi": "KHI",
            "Asia/Singapore": "SIN",
            "Asia/Tokyo": "TYO",
        ]

        if let override = overrides[identifier] {
            return override
        }

        return String(fallback.prefix(3)).uppercased()
    }

    private static func offsetText(for timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs((seconds / 60) % 60)
        return String(format: "GMT%+.2d:%02d", hours, minutes)
    }
}

private struct TimeZoneOption: Identifiable, Hashable {
    let id: String
    let shortLabel: String
    let cityName: String
    let displayName: String
    let searchableText: String

    var utcOffsetSeconds: Int {
        TimeZone(identifier: id)?.secondsFromGMT() ?? 0
    }
}
