import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

#if canImport(OrpytCore)
import OrpytCore
#endif

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

    func applicationDidBecomeActive(_ notification: Notification) {
        statusController?.reCheckCalendarIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let appIconImage = AppAssetLoader.appIconImage() {
            NSApp.applicationIconImage = appIconImage
            NSWorkspace.shared.setIcon(appIconImage, forFile: Bundle.main.bundlePath, options: [])
        }

        let settings = ClockSettingsStore.shared
        let weatherStore = WeatherStore.shared
        let calendarStore = CalendarStore.shared
        let shouldOpenSettingsOnLaunch = settings.performInitialSetupIfNeeded()
        _ = LaunchAtLoginManager.shared
        calendarStore.prepareForLaunch(using: settings)
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore
        )
        statusController = StatusBarController(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            settingsWindowController: settingsWindowController
        )

        if shouldOpenSettingsOnLaunch {
            DispatchQueue.main.async {
                settingsWindowController.show()
            }
        }
    }
}

@MainActor
private final class StatusBarController: NSObject, NSPopoverDelegate {
    private let settings: ClockSettingsStore
    private let weatherStore: WeatherStore
    private let calendarStore: CalendarStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    nonisolated(unsafe) private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastWeatherRefreshDate = Date.distantPast
    private var lastCalendarRefreshDate = Date.distantPast
    private var lastMeasuredPopoverHeight: CGFloat = 0
    nonisolated(unsafe) private var localEventMonitor: Any?
    nonisolated(unsafe) private var globalEventMonitor: Any?

    init(
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        calendarStore: CalendarStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.settingsWindowController = settingsWindowController
        super.init()
        configureStatusItem()
        configurePopover()
        installOutsideClickMonitors()
        observeSettings()
        observeWeatherSettings()
        observeCalendarSettings()
        observeWeather()
        startTimer()
        refreshWeather(force: true)
        refreshCalendar(force: true)
        updateDisplay()
    }

    deinit {
        if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
    }

    private enum Metrics {
        static let popoverWidth: CGFloat = 452
        static let popoverDefaultHeight: CGFloat = 360
        static let popoverMinHeight: CGFloat = 320
        static let popoverMaxHeight: CGFloat = 760
        static let popoverHeightPadding: CGFloat = 28
        static let weatherRefreshInterval: TimeInterval = 15 * 60
        static let calendarRefreshInterval: TimeInterval = 5 * 60
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
        popover.contentSize = NSSize(width: Metrics.popoverWidth, height: Metrics.popoverDefaultHeight)
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
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        settings.$showSeconds
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.startTimer()
            }
            .store(in: &cancellables)

        settings.$appearanceMode
            .dropFirst()
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
        .dropFirst()
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
        refreshCalendar(force: false)
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
            calendarStore: calendarStore,
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
        let targetHeight = min(
            max((measuredHeight + Metrics.popoverHeightPadding).rounded(.up), Metrics.popoverMinHeight),
            maximumPopoverHeight()
        )
        guard abs(targetHeight - lastMeasuredPopoverHeight) > 8 else { return }

        lastMeasuredPopoverHeight = targetHeight
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.popover.contentSize = NSSize(width: Metrics.popoverWidth, height: targetHeight)
        }
    }

    private func maximumPopoverHeight() -> CGFloat {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window,
            let screen = buttonWindow.screen
        else {
            return Metrics.popoverMaxHeight
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        let visibleFrame = screen.visibleFrame
        let availableBelowButton = buttonFrameOnScreen.minY - visibleFrame.minY - 16

        return min(
            Metrics.popoverMaxHeight,
            max(Metrics.popoverMinHeight, availableBelowButton)
        )
    }

    private func refreshWeather(force: Bool) {
        guard settings.enableWeather else {
            weatherStore.disable()
            return
        }

        let refreshInterval: TimeInterval = Metrics.weatherRefreshInterval
        let now = Date()

        guard force || now.timeIntervalSince(lastWeatherRefreshDate) >= refreshInterval else {
            return
        }

        lastWeatherRefreshDate = now
        weatherStore.refresh(for: settings)
    }

    private func observeCalendarSettings() {
        settings.$showCalendarEvents
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    Task { await self.calendarStore.enable(using: self.settings) }
                } else {
                    self.calendarStore.disable()
                }
            }
            .store(in: &cancellables)
    }

    func reCheckCalendarIfNeeded() {
        guard settings.showCalendarEvents else { return }
        Task { await calendarStore.enable(using: settings) }
    }

    private func refreshCalendar(force: Bool) {
        guard settings.showCalendarEvents else {
            calendarStore.disable()
            return
        }

        let refreshInterval: TimeInterval = Metrics.calendarRefreshInterval
        let now = Date()

        guard force || now.timeIntervalSince(lastCalendarRefreshDate) >= refreshInterval else {
            return
        }

        lastCalendarRefreshDate = now
        Task {
            await calendarStore.refresh(using: settings)
        }
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var didCenterWindow = false
    private let settings: ClockSettingsStore
    private let weatherStore: WeatherStore
    private let calendarStore: CalendarStore
    private let hostingController: NSHostingController<AnyView>

    init(settings: ClockSettingsStore, weatherStore: WeatherStore, calendarStore: CalendarStore) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
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
        hostingController.rootView = AnyView(
            SettingsView(settings: settings, weatherStore: weatherStore, calendarStore: calendarStore)
        )
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
