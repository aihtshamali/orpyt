import AppKit
import Combine
import CoreLocation
import EventKit
#if canImport(EventKitUI)
import EventKitUI
#endif
import Security
import ServiceManagement
import SwiftUI
@preconcurrency import UserNotifications
import WeatherKit

#if DIRECT_DISTRIBUTION
import Sparkle
#endif

import OrpytCore

@main
struct OrpytApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppSettingsSceneContent(
                onCheckForUpdates: { appDelegate.checkForUpdates() }
            )
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showSettingsFromAppMenu()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct AppSettingsSceneContent: View {
    @ObservedObject private var settings = ClockSettingsStore.shared
    @ObservedObject private var weatherStore = WeatherStore.shared
    @ObservedObject private var calendarStore = CalendarStore.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @ObservedObject private var agentStore = AgentActivityStore.shared
    @ObservedObject private var integrationManager = AgentIntegrationManager.shared
    @StateObject private var navigationStore = SettingsNavigationStore()
    let onCheckForUpdates: () -> Void

    var body: some View {
        SettingsView(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            subscriptionStore: subscriptionStore,
            agentStore: agentStore,
            integrationManager: integrationManager,
            navigationStore: navigationStore,
            onCheckForUpdates: onCheckForUpdates
        )
        .frame(minWidth: 900, minHeight: 660)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    private var statusController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private let subscriptionStore = SubscriptionStore.shared
    private let reviewStore = ReviewPromptStore.shared
    private let agentStore = AgentActivityStore.shared
    private var agentTransitionCancellable: AnyCancellable?
    #if DIRECT_DISTRIBUTION
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif

    func checkForUpdates() {
        #if DIRECT_DISTRIBUTION
        updaterController.checkForUpdates(nil)
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusController?.reCheckCalendarIfNeeded()
        WelcomePeriodStore.shared.refresh()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIconImage = AppAssetLoader.appIconImage() {
            NSApp.applicationIconImage = appIconImage
        }

        let settings = ClockSettingsStore.shared
        let weatherStore = WeatherStore.shared
        let calendarStore = CalendarStore.shared
        reviewStore.recordLaunch()
        subscriptionStore.prepareForLaunch()
        WelcomePeriodStore.shared.refresh()
        agentStore.prune()
        UNUserNotificationCenter.current().delegate = self
        observeAgentTransitions()
        let shouldOpenSettingsOnLaunch = settings.performInitialSetupIfNeeded()
        let shouldShowLaunchWindow = shouldShowSettingsWindowOnLaunch(initialSetupNeeded: shouldOpenSettingsOnLaunch)
        _ = LaunchAtLoginManager.shared
        calendarStore.prepareForLaunch(using: settings)
        var controller: StatusBarController?
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            subscriptionStore: subscriptionStore,
            agentStore: agentStore,
            integrationManager: AgentIntegrationManager.shared,
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
            onTestReviewPrompt: { controller?.presentReviewPromptForDebugTesting() },
            onWindowClosed: { controller?.considerReviewPromptAfterCalmTransition() }
        )
        self.settingsWindowController = settingsWindowController
        controller = StatusBarController(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            subscriptionStore: subscriptionStore,
            agentStore: agentStore,
            reviewStore: reviewStore,
            settingsWindowController: settingsWindowController
        )
        statusController = controller

        // Set accessory policy only when no launch window is needed. App Review
        // and updated installs must always get an obvious visible surface.
        NSApp.setActivationPolicy(shouldShowLaunchWindow ? .regular : .accessory)

        // Also patch the generated app-menu item as a fallback for OS versions
        // that still route through the default SwiftUI Settings action.
        redirectSettingsMenuItem(to: settingsWindowController)

        if shouldShowLaunchWindow {
            DispatchQueue.main.async {
                settingsWindowController.show()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard settingsWindowController.window?.isVisible != true else { return }
            controller?.ensureLaunchSurfaceIsVisible()
        }

        // Poll for menu bar overflow: if the status item is hidden (menu bar full),
        // surface a Dock icon so the user can still reach Orpyt.
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak statusController, weak settingsWindowController] _ in
            Task { @MainActor in
                guard settingsWindowController?.window?.isVisible != true else { return }
                statusController?.updateDockVisibilityForOverflow()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = try? agentStore.ingest(url: url)
        }
        AgentIntegrationManager.shared.refresh()
    }

    private func observeAgentTransitions() {
        agentTransitionCancellable = agentStore.$lastTransition
            .compactMap { $0 }
            .sink { [weak self] transition in
                self?.deliverNotification(for: transition)
            }
    }

    private func deliverNotification(for transition: AgentActivityTransition) {
        guard statusController?.isPopoverShown != true else { return }
        let shouldNotify: Bool
        switch transition.kind {
        case .attention, .failed:
            shouldNotify = agentStore.attentionNotificationsEnabled
        case .completed:
            shouldNotify = agentStore.completionNotificationsEnabled
        case .started, .resumed, .ended:
            shouldNotify = false
        }
        guard shouldNotify else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(transition.activity.sourceTitle) · \(transition.activity.state.title)"
            content.body = transition.activity.projectName
            content.sound = transition.kind == .attention || transition.kind == .failed ? .default : nil
            content.userInfo = ["activityID": transition.activity.id]
            center.add(UNNotificationRequest(
                identifier: "agent-pulse-\(transition.activity.id)-\(transition.activity.state.rawValue)",
                content: content,
                trigger: nil
            ))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(statusController?.isPopoverShown == true ? [] : [.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let id = response.notification.request.content.userInfo["activityID"] as? String,
           let activity = agentStore.activity(id: id) {
            StatusBarController.activate(activity: activity)
        }
        statusController?.showPopover()
        completionHandler()
    }

    func showSettingsFromAppMenu() {
        settingsWindowController?.show()
    }

    private func shouldShowSettingsWindowOnLaunch(initialSetupNeeded: Bool) -> Bool {
        if initialSetupNeeded { return true }

        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let key = "launchVisibility.lastSettingsBuild"
        let defaults = UserDefaults.standard

        guard defaults.string(forKey: key) != currentBuild else {
            return false
        }

        defaults.set(currentBuild, forKey: key)
        return true
    }

    /// Find any auto-generated "Settings…" menu item and point it at our real
    /// settings window so ⌘, and the app menu both keep working across macOS
    /// versions.
    private func redirectSettingsMenuItem(to settingsWindowController: SettingsWindowController) {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

        let settingsActions: [Selector] = [
            Selector(("showSettingsWindow:")),
            Selector(("showPreferencesWindow:")),
        ]

        for item in appMenu.items where item.action.map(settingsActions.contains) == true {
            item.target = settingsWindowController
            item.action = #selector(SettingsWindowController.showFromMenuItem)
        }
    }
}

#if canImport(EventKitUI)
@MainActor
private final class CalendarMeetingEditorPresenter: NSObject, EKEventEditViewDelegate {
    private weak var presentedController: EKEventEditViewController?
    private let eventStore = EKEventStore()

    func present(from presentingController: NSViewController?) -> Bool {
        guard let presentingController, isCalendarWritable else { return false }

        let event = EKEvent(eventStore: eventStore)
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let endDate = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 45, to: startDate) ?? startDate.addingTimeInterval(30 * 60)
        event.title = "New Meeting"
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = eventStore.defaultCalendarForNewEvents

        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = self
        presentedController = controller
        presentingController.presentAsSheet(controller)
        return true
    }

    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        controller.dismiss(nil)
        presentedController = nil
    }

    private var isCalendarWritable: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .authorized
        }
        return status == .authorized
    }
}
#endif

private struct MeetingTitleRevealView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 170, alignment: .leading)
    }
}

@MainActor
private final class StatusBarController: NSObject, NSPopoverDelegate {
    private let settings: ClockSettingsStore
    private let weatherStore: WeatherStore
    private let calendarStore: CalendarStore
    private let subscriptionStore: SubscriptionStore
    private let agentStore: AgentActivityStore
    private let reviewStore: ReviewPromptStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let meetingTitlePopover = NSPopover()
    private let popoverHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var agentAnimationTimer: Timer?
    private var agentAnimationFrame = 0
    private var cancellables = Set<AnyCancellable>()
    private var lastWeatherRefreshDate = Date.distantPast
    private var lastCalendarRefreshDate = Date.distantPast
    private var lastMeasuredPopoverHeight: CGFloat = 0
    nonisolated(unsafe) private var localEventMonitor: Any?
    nonisolated(unsafe) private var globalEventMonitor: Any?
    nonisolated(unsafe) private var globalMouseMoveMonitor: Any?
    private var activeMeetingAlert: MeetingAlertSnapshot?
    private var activeMeetingIndicatorHitWidth: CGFloat = 0
    private var activeMeetingIndicatorHitRange: ClosedRange<CGFloat>?
    private var isHoveringMeetingIndicator = false
    private var isPresentingReviewPrompt = false
    #if canImport(EventKitUI)
    private let meetingEditorPresenter = CalendarMeetingEditorPresenter()
    #endif

    init(
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        calendarStore: CalendarStore,
        subscriptionStore: SubscriptionStore,
        agentStore: AgentActivityStore,
        reviewStore: ReviewPromptStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.subscriptionStore = subscriptionStore
        self.agentStore = agentStore
        self.reviewStore = reviewStore
        self.settingsWindowController = settingsWindowController
        super.init()
        configureStatusItem()
        configurePopover()
        installOutsideClickMonitors()
        observeSettings()
        observeWeatherSettings()
        observeCalendarSettings()
        observeWeather()
        observeAgentActivity()
        startTimer()
        refreshWeather(force: true)
        refreshCalendar(force: true)
        recordVisibleClockValueMomentIfNeeded()
        updateDisplay()
    }

    deinit {
        if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMouseMoveMonitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
        agentAnimationTimer?.invalidate()
    }

    private enum Metrics {
        static let popoverWidth: CGFloat = 452
        static let popoverDefaultHeight: CGFloat = 360
        static let popoverMinHeight: CGFloat = 320
        static let popoverMaxHeight: CGFloat = 760
        static let popoverHeightPadding: CGFloat = 28
        static let weatherRefreshInterval: TimeInterval = 15 * 60
        static let calendarRefreshInterval: TimeInterval = 5 * 60
        static let titleRevealDuration: TimeInterval = 5
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "Orpyt"
        } else {
            // macOS 26 beta: button may be nil briefly; retry after run loop settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.configureStatusItem()
                self?.updateDisplay()
            }
        }
    }

    // Consecutive checks where button.window was nil — must reach threshold before
    // we conclude the menu bar is actually full (avoids transient false positives).
    private var overflowMissCount = 0
    private let overflowMissThreshold = 3

    /// Shows a Dock icon + menu when the menu bar item is hidden due to overflow,
    /// and hides it again once the item becomes visible.
    func updateDockVisibilityForOverflow() {
        // Don't touch activation policy while the popover is open
        guard !popover.isShown else { return }

        let buttonVisible = isStatusItemVisible
        let currentPolicy = NSApp.activationPolicy()

        if buttonVisible {
            overflowMissCount = 0
            settings.isMenuBarOverflowing = false
            if currentPolicy == .regular {
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            overflowMissCount += 1
            guard overflowMissCount >= overflowMissThreshold else { return }
            settings.isMenuBarOverflowing = true
            if currentPolicy == .accessory {
                NSApp.setActivationPolicy(.regular)
                let menu = NSMenu()
                menu.addItem(withTitle: "Open Orpyt", action: #selector(togglePopover(_:)), keyEquivalent: "")
                    .target = self
                menu.addItem(.separator())
                menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromDock), keyEquivalent: ",")
                    .target = self
                menu.addItem(.separator())
                menu.addItem(withTitle: "Quit Orpyt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
                NSApp.mainMenu = menu
            }
        }
    }

    func ensureLaunchSurfaceIsVisible() {
        guard !isStatusItemVisible else { return }

        overflowMissCount = overflowMissThreshold
        settings.isMenuBarOverflowing = true
        NSApp.setActivationPolicy(.regular)
        settingsWindowController.show()
        updateDockVisibilityForOverflow()
    }

    private var isStatusItemVisible: Bool {
        guard let button = statusItem.button else { return false }
        return button.window != nil && button.bounds.width > 1
    }

    @objc private func openSettingsFromDock() {
        settingsWindowController.show()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: Metrics.popoverWidth, height: Metrics.popoverDefaultHeight)
        popover.delegate = self
        popover.contentViewController = popoverHostingController
        meetingTitlePopover.behavior = .transient
        meetingTitlePopover.animates = true
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
            settings.$meetingIndicatorStyle.map { _ in }.eraseToAnyPublisher(),
            settings.$meetingWarningMode.map { _ in }.eraseToAnyPublisher(),
            settings.$meetingWarningPreset.map { _ in }.eraseToAnyPublisher(),
            settings.$meetingEarlyWarningMinutes.map { _ in }.eraseToAnyPublisher(),
            settings.$meetingCriticalWarningMinutes.map { _ in }.eraseToAnyPublisher(),
            settings.$meetingIndicatorHoverBehavior.map { _ in }.eraseToAnyPublisher(),
            settings.$meetingIndicatorClickAction.map { _ in }.eraseToAnyPublisher(),
            settings.$menuBarLayoutItems.map { _ in }.eraseToAnyPublisher(),
            settings.$primaryClockFormatOverride.map { _ in }.eraseToAnyPublisher(),
            settings.$secondaryClockFormatOverride.map { _ in }.eraseToAnyPublisher(),
            settings.$menuBarSeparatorStyle.map { _ in }.eraseToAnyPublisher(),
            settings.$menuBarSpacing.map { _ in }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(displayPublishers)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recordVisibleClockValueMomentIfNeeded()
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
                self?.settingsWindowController.refreshAppearance()
            }
            .store(in: &cancellables)
    }

    private func observeAgentActivity() {
        Publishers.CombineLatest(agentStore.$activities, agentStore.$isEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateAgentAnimationTimer()
                self?.updateDisplay()
                self?.refreshPopoverContent()
                if self?.agentStore.indicatorState == .completed {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.1) { [weak self] in
                        self?.updateDisplay()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func updateAgentAnimationTimer() {
        let shouldAnimate = agentStore.indicatorState == .running &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            agentAnimationTimer?.invalidate()
            agentAnimationTimer = nil
            agentAnimationFrame = 0
            return
        }
        guard agentAnimationTimer == nil else { return }
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.agentAnimationFrame = (self.agentAnimationFrame + 1) % 3
                self.updateDisplay()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        agentAnimationTimer = newTimer
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
                DispatchQueue.main.async {
                    self?.recordWeatherValueMomentIfNeeded()
                    self?.updateDisplay()
                }
            }
            .store(in: &cancellables)

        subscriptionStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
                self?.refreshPopoverContent()
                self?.refreshWeather(force: true)
                self?.refreshCalendar(force: true)
            }
            .store(in: &cancellables)

        calendarStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.recordCalendarValueMomentIfNeeded()
                    self?.updateDisplay()
                }
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

        if didClickMeetingIndicator(in: button) {
            openActiveMeeting()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        reCheckCalendarIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    var isPopoverShown: Bool { popover.isShown }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    static func activate(activity: AgentActivity) {
        if activity.originatesFromCodexDesktop {
            var components = URLComponents()
            components.scheme = "codex"
            components.host = "threads"
            components.path = "/\(activity.sessionID)"
            if let taskURL = components.url {
                NSWorkspace.shared.open(taskURL)
                return
            }
        }
        let knownBundleIdentifiers: [String: String] = [
            "Apple_Terminal": "com.apple.Terminal",
            "iTerm.app": "com.googlecode.iterm2",
            "vscode": "com.microsoft.VSCode",
            "WezTerm": "com.github.wez.wezterm",
            "WarpTerminal": "dev.warp.Warp-Stable",
        ]
        if let terminal = activity.terminalProgram,
           let bundleIdentifier = knownBundleIdentifiers[terminal],
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            return
        }
        let projectURL = URL(fileURLWithPath: activity.workingDirectory)
        if FileManager.default.fileExists(atPath: projectURL.path) {
            NSWorkspace.shared.open(projectURL)
        }
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

        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeetingIndicatorHoverState()
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if agentStore.showTaskDetailsInPopover {
            agentStore.markCompletedRead()
        }
        considerReviewPromptAfterCalmTransition()
    }

    func considerReviewPromptAfterCalmTransition() {
        updateDisplay()
        guard reviewStore.shouldPresentReviewPrompt(
            hasActiveFriction: hasActiveReviewPromptFriction,
            hasActiveMeetingAlert: activeMeetingAlert != nil
        ) else {
            return
        }
        presentReviewPrePrompt()
    }

    func presentReviewPromptForDebugTesting() {
        #if DEBUG
        presentReviewPrePrompt(isDebugTest: true)
        #endif
    }

    private var hasActiveReviewPromptFriction: Bool {
        if subscriptionStore.showProSheet { return true }
        if case .needsPermission = calendarStore.state { return true }
        if case .failed = calendarStore.state { return true }
        if weatherFailed(.primary) || weatherFailed(.secondary) { return true }
        return false
    }

    private func weatherFailed(_ slot: ClockSlot) -> Bool {
        if case .failed = weatherStore.state(for: slot) {
            return true
        }
        return false
    }

    private func presentReviewPrePrompt(isDebugTest: Bool = false) {
        guard !isPresentingReviewPrompt else { return }
        isPresentingReviewPrompt = true
        defer { isPresentingReviewPrompt = false }

        let alert = NSAlert()
        alert.messageText = "Enjoying Orpyt?"
        alert.informativeText = "Your valuable feedback helps motivate us to keep improving Orpyt and bring more thoughtful features for people working across time zones."
        alert.addButton(withTitle: "Rate on the App Store")
        alert.addButton(withTitle: "Not now")
        alert.addButton(withTitle: "Suggest a Feature")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            reviewStore.recordReviewPromptAttempt()
            #if DIRECT_DISTRIBUTION
            if isDebugTest {
                let debugAlert = NSAlert()
                debugAlert.messageText = "Review Action Recorded"
                debugAlert.informativeText = "This direct-download debug build can show the feedback pre-prompt, but the App Store rating page only opens in App Store builds."
                debugAlert.addButton(withTitle: "OK")
                debugAlert.runModal()
                return
            }
            #endif
            NSWorkspace.shared.open(ReviewPromptStore.appStoreReviewURL)
        case .alertThirdButtonReturn:
            reviewStore.recordPromptDismissal()
            NSWorkspace.shared.open(ReviewPromptStore.suggestionsURL)
        default:
            reviewStore.recordPromptDismissal()
        }
    }

    private func recordVisibleClockValueMomentIfNeeded() {
        guard settings.showPrimaryClock, settings.showSecondaryClock else { return }
        reviewStore.recordValueMoment(.twoClocksVisible)
    }

    private func recordWeatherValueMomentIfNeeded() {
        if case .loaded = weatherStore.state(for: .primary) {
            reviewStore.recordValueMoment(.weatherLoaded)
            return
        }

        if case .loaded = weatherStore.state(for: .secondary) {
            reviewStore.recordValueMoment(.weatherLoaded)
        }
    }

    private func recordCalendarValueMomentIfNeeded() {
        guard case let .loaded(snapshot) = calendarStore.state,
              snapshot?.nextMeeting != nil else {
            return
        }
        reviewStore.recordValueMoment(.calendarLoadedMeeting)
    }

    private func updateDisplay() {
        let now = Date()
        activeMeetingAlert = ClockFormatter.activeMeetingAlert(
            for: now,
            settings: settings,
            calendarState: calendarStore.state
        )

        let baseClockTooltip = ClockFormatter.menuBarTooltip(
            for: now,
            settings: settings,
            weatherStore: weatherStore
        )
        let menuBarFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: menuBarFont,
            .foregroundColor: NSColor.labelColor,
        ]

        let style = settings.effectiveMeetingIndicatorStyle
        let indicatorRender = activeMeetingAlert.flatMap {
            ClockFormatter.meetingIndicatorRender(for: $0, style: style, font: menuBarFont)
        }
        activeMeetingIndicatorHitWidth = indicatorRender?.hitWidth ?? 0
        activeMeetingIndicatorHitRange = nil

        let displayTitle: NSAttributedString
        if let activeMeetingAlert {
            switch style {
            case .off:
                displayTitle = menuBarLayoutTitle(for: now, indicatorRender: nil, textAttributes: textAttributes)
            case .fullReplace:
                displayTitle = NSAttributedString(
                    string: ClockFormatter.meetingFullReplaceTitle(for: activeMeetingAlert),
                    attributes: textAttributes
                )
            case .tinyBadge, .imminentPill:
                displayTitle = menuBarLayoutTitle(for: now, indicatorRender: indicatorRender, textAttributes: textAttributes)
            }
        } else {
            displayTitle = menuBarLayoutTitle(for: now, indicatorRender: nil, textAttributes: textAttributes)
            isHoveringMeetingIndicator = false
            meetingTitlePopover.performClose(nil)
        }

        let finalTitle = NSMutableAttributedString()
        if let indicatorRender, activeMeetingAlert != nil, style == .fullReplace {
            if let agentRender = agentIndicatorRender(font: menuBarFont) {
                finalTitle.append(agentRender)
                finalTitle.append(NSAttributedString(string: " ", attributes: textAttributes))
            }
            let indicatorStart = finalTitle.size().width
            finalTitle.append(indicatorRender.prefix)
            finalTitle.append(NSAttributedString(string: " ", attributes: textAttributes))
            activeMeetingIndicatorHitRange = indicatorStart...(indicatorStart + indicatorRender.hitWidth)
        }
        finalTitle.append(displayTitle)

        statusItem.button?.attributedTitle = finalTitle
        statusItem.button?.toolTip = {
            let agentLine: String? = switch agentStore.indicatorState {
            case .hidden: nil
            case .running: "AI task running"
            case .attention: "AI task needs attention"
            case .completed: "AI task completed"
            case .failed: "AI task failed"
            }
            let clockTooltip = agentLine.map { $0 + "\n" + baseClockTooltip } ?? baseClockTooltip
            guard let activeMeetingAlert else { return clockTooltip }
            guard !isHoveringMeetingIndicator else { return nil }
            return ClockFormatter.meetingTooltipLine(for: activeMeetingAlert, settings: settings) + "\n" + clockTooltip
        }()
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
    }

    private func menuBarLayoutTitle(
        for now: Date,
        indicatorRender: ClockFormatter.MenuBarMeetingIndicatorRender?,
        textAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let clockSegments = Dictionary(
            uniqueKeysWithValues: ClockFormatter.menuBarClockSegments(
                for: now,
                settings: settings,
                weatherStore: weatherStore,
                attributes: textAttributes,
                font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ).map { ($0.item, $0.attributedTitle) }
        )
        let separator = ClockFormatter.menuBarSeparator(settings: settings, attributes: textAttributes)
        var didAppendItem = false

        for item in settings.effectiveMenuBarLayoutItems {
            let nextSegment: NSAttributedString?
            switch item {
            case .agentIndicator:
                nextSegment = agentIndicatorRender(font: NSFont.systemFont(ofSize: 12, weight: .semibold))
            case .meetingIndicator:
                nextSegment = indicatorRender?.prefix
            case .primaryClock, .secondaryClock:
                nextSegment = clockSegments[item]
            }

            guard let nextSegment else { continue }

            if didAppendItem {
                title.append(separator)
            }

            if item == .meetingIndicator, let indicatorRender {
                let start = title.size().width
                activeMeetingIndicatorHitRange = start...(start + indicatorRender.hitWidth)
            }

            title.append(nextSegment)
            didAppendItem = true
        }

        return title.length == 0
            ? NSAttributedString(string: "Orpyt", attributes: textAttributes)
            : title
    }

    private func agentIndicatorRender(font: NSFont) -> NSAttributedString? {
        let imageName: String
        let color: NSColor
        let pointSize: CGFloat
        let appearanceStatus: AgentIndicatorAppearanceStatus
        switch agentStore.indicatorState {
        case .hidden:
            return nil
        case .running:
            appearanceStatus = .running
            imageName = agentStore.indicatorIcon(for: .running)
            let pulseColors: [NSColor] = [.systemPurple, .systemIndigo, .systemPink]
            color = pulseColors[agentAnimationFrame % pulseColors.count]
            pointSize = max(font.pointSize + 2.5, 14.5)
        case .attention:
            appearanceStatus = .attention
            imageName = agentStore.indicatorIcon(for: .attention)
            color = .systemOrange
            pointSize = max(font.pointSize + 2.5, 14.5)
        case .completed:
            appearanceStatus = .completed
            imageName = agentStore.indicatorIcon(for: .completed)
            color = .systemGreen
            pointSize = max(font.pointSize + 2.5, 14.5)
        case .failed:
            appearanceStatus = .failed
            imageName = agentStore.indicatorIcon(for: .failed)
            color = .systemRed
            pointSize = max(font.pointSize + 2.5, 14.5)
        }

        if let customImage = agentStore.customIndicatorImage(for: appearanceStatus) {
            let image = customImage.copy() as? NSImage ?? customImage
            image.isTemplate = false
            let pulseOffset: CGFloat = appearanceStatus == .running
                ? [0, 1.2, 0.4][agentAnimationFrame % 3]
                : 0
            let renderedSize = pointSize + 1 + pulseOffset
            image.size = NSSize(width: renderedSize, height: renderedSize)
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -2.5, width: renderedSize, height: renderedSize)
            return NSAttributedString(attachment: attachment)
        }

        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let palette = NSImage.SymbolConfiguration(hierarchicalColor: color)
        let fallbackName: String = switch agentStore.indicatorState {
        case .hidden, .running: AgentIndicatorAppearanceStatus.running.defaultIcon
        case .attention: AgentIndicatorAppearanceStatus.attention.defaultIcon
        case .completed: AgentIndicatorAppearanceStatus.completed.defaultIcon
        case .failed: AgentIndicatorAppearanceStatus.failed.defaultIcon
        }
        guard let symbol = NSImage(systemSymbolName: imageName, accessibilityDescription: "AI task status")
                ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: "AI task status"),
              let image = symbol.withSymbolConfiguration(base.applying(palette)) else { return nil }
        image.isTemplate = false
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2.5, width: pointSize + 1, height: pointSize + 1)
        return NSAttributedString(attachment: attachment)
    }

    private func updateMeetingIndicatorHoverState() {
        guard activeMeetingAlert != nil, activeMeetingIndicatorHitWidth > 0, activeMeetingIndicatorHitRange != nil else {
            if isHoveringMeetingIndicator {
                isHoveringMeetingIndicator = false
                updateDisplay()
            }
            return
        }

        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            return
        }

        let mouseOnScreen = NSEvent.mouseLocation
        let mouseInWindow = buttonWindow.convertPoint(fromScreen: mouseOnScreen)
        let mouseInButton = button.convert(mouseInWindow, from: nil)
        let isInsideButton = button.bounds.contains(mouseInButton)
        let isHoveringIndicator = isInsideButton && (activeMeetingIndicatorHitRange?.contains(mouseInButton.x) ?? false)

        guard isHoveringIndicator != isHoveringMeetingIndicator else { return }
        isHoveringMeetingIndicator = isHoveringIndicator
        if isHoveringIndicator {
            revealActiveMeetingTitle(autoClose: false)
        } else if !isHoveringIndicator {
            meetingTitlePopover.performClose(nil)
        }
        updateDisplay()
    }

    private func didClickMeetingIndicator(in button: NSStatusBarButton) -> Bool {
        guard activeMeetingAlert != nil, activeMeetingIndicatorHitWidth > 0,
              let activeMeetingIndicatorHitRange,
              let event = NSApp.currentEvent,
              event.type == .leftMouseUp else {
            return false
        }

        let pointInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(pointInButton) && activeMeetingIndicatorHitRange.contains(pointInButton.x)
    }

    private func openActiveMeeting() {
        guard let meeting = activeMeetingAlert?.meeting else { return }

        switch settings.meetingIndicatorClickAction {
        case .openMeeting:
            if let joinURL = meeting.joinURL {
                NSWorkspace.shared.open(joinURL)
            } else {
                openCalendarApp()
            }
        case .openCalendar:
            openCalendarApp()
        case .revealTitle:
            revealActiveMeetingTitle(autoClose: true)
        }
    }

    private func revealActiveMeetingTitle(autoClose: Bool) {
        guard let alert = activeMeetingAlert,
              let button = statusItem.button else { return }

        meetingTitlePopover.contentViewController = NSHostingController(
            rootView: MeetingTitleRevealView(
                title: alert.meeting.title,
                subtitle: ClockFormatter.meetingCountdownText(for: alert)
            )
        )
        meetingTitlePopover.contentSize = NSSize(width: 170, height: 48)
        meetingTitlePopover.show(relativeTo: meetingIndicatorAnchorRect(in: button), of: button, preferredEdge: .minY)

        guard autoClose else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.titleRevealDuration) { [weak self] in
            self?.meetingTitlePopover.performClose(nil)
        }
    }

    private func meetingIndicatorAnchorRect(in button: NSStatusBarButton) -> NSRect {
        let range = activeMeetingIndicatorHitRange ?? 0...activeMeetingIndicatorHitWidth
        let anchorX = max(0, min(range.upperBound - 4, button.bounds.width - 4))
        return NSRect(x: anchorX, y: 0, width: 4, height: button.bounds.height)
    }

    private func presentNewMeetingEditor() {
        #if canImport(EventKitUI)
        if meetingEditorPresenter.present(from: popoverHostingController) {
            return
        }
        #endif
        openCalendarApp()
    }

    private func openCalendarApp() {
        if let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: calendarURL, configuration: configuration)
        }
    }

    private func openSettings(pane: SettingsPane? = nil) {
        popover.performClose(nil)
        settingsWindowController.show(pane: pane)
    }

    private func refreshPopoverContent() {
        switch settings.effectiveAppearanceMode {
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
            subscriptionStore: subscriptionStore,
            agentStore: agentStore,
            appearanceMode: settings.effectiveAppearanceMode,
            onOpenSettings: { [weak self] pane in self?.openSettings(pane: pane) },
            onSwapTimeZones: { [weak self, weak settings] in
                settings?.swapTimeZones()
                self?.weatherStore.swapClockStates()
            },
            onCreateMeeting: { [weak self] in self?.presentNewMeetingEditor() },
            onOpenAgentActivity: { activity in Self.activate(activity: activity) },
            onQuit: { NSApplication.shared.terminate(nil) },
            onReviewValueMoment: { [weak self] moment in
                self?.reviewStore.recordValueMoment(moment)
            },
            onContentHeightChange: { [weak self] height in
                self?.updatePopoverSize(for: height)
            }
        )

        switch settings.effectiveAppearanceMode {
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

        guard subscriptionStore.hasAccess(to: .weather) else {
            weatherStore.disable()
            return
        }

        let refreshInterval = settings.refreshInterval(for: Metrics.weatherRefreshInterval)
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
                if isEnabled, self.subscriptionStore.hasAccess(to: .calendar) {
                    Task { await self.calendarStore.enable(using: self.settings) }
                } else {
                    self.calendarStore.disable()
                }
            }
            .store(in: &cancellables)
    }

    func reCheckCalendarIfNeeded() {
        guard settings.showCalendarEvents, subscriptionStore.hasAccess(to: .calendar) else { return }
        Task { await calendarStore.syncAuthorization(using: settings) }
    }

    private func refreshCalendar(force: Bool) {
        guard settings.showCalendarEvents else {
            calendarStore.disable()
            return
        }

        guard subscriptionStore.hasAccess(to: .calendar) else {
            calendarStore.disable()
            return
        }

        let refreshInterval = settings.refreshInterval(for: Metrics.calendarRefreshInterval)
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
    private let subscriptionStore: SubscriptionStore
    private let agentStore: AgentActivityStore
    private let integrationManager: AgentIntegrationManager
    private let navigationStore = SettingsNavigationStore()
    private let hostingController: NSHostingController<AnyView>
    private let onCheckForUpdates: () -> Void
    private let onTestReviewPrompt: () -> Void
    private let onWindowClosed: () -> Void

    init(
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        calendarStore: CalendarStore,
        subscriptionStore: SubscriptionStore,
        agentStore: AgentActivityStore,
        integrationManager: AgentIntegrationManager,
        onCheckForUpdates: @escaping () -> Void,
        onTestReviewPrompt: @escaping () -> Void,
        onWindowClosed: @escaping () -> Void
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.subscriptionStore = subscriptionStore
        self.agentStore = agentStore
        self.integrationManager = integrationManager
        self.onCheckForUpdates = onCheckForUpdates
        self.onTestReviewPrompt = onTestReviewPrompt
        self.onWindowClosed = onWindowClosed
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
        refreshSettingsView()
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func showFromMenuItem() {
        show()
    }

    func show(pane: SettingsPane? = nil) {
        guard let window else { return }

        if let pane {
            navigationStore.selectedPane = pane
        }

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
        switch settings.effectiveAppearanceMode {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
        refreshSettingsView()
    }

    private func refreshSettingsView() {
        let view = SettingsView(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            subscriptionStore: subscriptionStore,
            agentStore: agentStore,
            integrationManager: integrationManager,
            navigationStore: navigationStore,
            onCheckForUpdates: onCheckForUpdates,
            onTestReviewPrompt: onTestReviewPrompt
        )
        switch settings.effectiveAppearanceMode {
        case .system:
            hostingController.rootView = AnyView(view)
        case .light, .dark:
            hostingController.rootView = AnyView(view.preferredColorScheme(settings.preferredColorScheme))
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onWindowClosed()
    }
}
