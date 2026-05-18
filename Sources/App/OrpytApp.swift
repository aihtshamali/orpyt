import AppKit
import Combine
import CoreLocation
import EventKit
#if canImport(EventKitUI)
import EventKitUI
#endif
import Security
import ServiceManagement
import StoreKit
import SwiftUI
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
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private let subscriptionStore = SubscriptionStore.shared
    private let reviewStore = ReviewPromptStore.shared
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
        let shouldOpenSettingsOnLaunch = settings.performInitialSetupIfNeeded()
        _ = LaunchAtLoginManager.shared
        calendarStore.prepareForLaunch(using: settings)
        var controller: StatusBarController?
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            subscriptionStore: subscriptionStore,
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
            onTestReviewPrompt: { controller?.presentReviewPromptForDebugTesting() },
            onWindowClosed: { controller?.considerReviewPromptAfterCalmTransition() }
        )
        controller = StatusBarController(
            settings: settings,
            weatherStore: weatherStore,
            calendarStore: calendarStore,
            subscriptionStore: subscriptionStore,
            reviewStore: reviewStore,
            settingsWindowController: settingsWindowController
        )
        statusController = controller

        // Set accessory policy after status item is created so the menu bar button
        // is fully allocated before the app hides its Dock icon (macOS 26 beta compat).
        NSApp.setActivationPolicy(.accessory)

        if shouldOpenSettingsOnLaunch {
            DispatchQueue.main.async {
                settingsWindowController.show()
            }
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
    private let reviewStore: ReviewPromptStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let meetingTitlePopover = NSPopover()
    private let popoverHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    nonisolated(unsafe) private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastWeatherRefreshDate = Date.distantPast
    private var lastCalendarRefreshDate = Date.distantPast
    private var lastMeasuredPopoverHeight: CGFloat = 0
    nonisolated(unsafe) private var localEventMonitor: Any?
    nonisolated(unsafe) private var globalEventMonitor: Any?
    nonisolated(unsafe) private var globalMouseMoveMonitor: Any?
    private var activeMeetingAlert: MeetingAlertSnapshot?
    private var activeMeetingIndicatorHitWidth: CGFloat = 0
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
        reviewStore: ReviewPromptStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.subscriptionStore = subscriptionStore
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

        let buttonVisible = statusItem.button?.window != nil
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
                debugAlert.informativeText = "This direct-download debug build can show the feedback pre-prompt, but the App Store rating sheet only appears in App Store builds."
                debugAlert.addButton(withTitle: "OK")
                debugAlert.runModal()
                return
            }
            #endif
            SKStoreReviewController.requestReview()
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

        let baseClockTitle = ClockFormatter.menuBarAttributedTitle(
            for: now,
            settings: settings,
            weatherStore: weatherStore
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

        let displayTitle: NSAttributedString
        if let activeMeetingAlert {
            switch style {
            case .off:
                displayTitle = baseClockTitle
            case .fullReplace:
                displayTitle = NSAttributedString(
                    string: ClockFormatter.meetingFullReplaceTitle(for: activeMeetingAlert),
                    attributes: textAttributes
                )
            case .tinyBadge, .imminentPill:
                displayTitle = baseClockTitle
            }
        } else {
            displayTitle = baseClockTitle
            isHoveringMeetingIndicator = false
            meetingTitlePopover.performClose(nil)
        }

        let finalTitle = NSMutableAttributedString()
        if let indicatorRender {
            finalTitle.append(indicatorRender.prefix)
            finalTitle.append(NSAttributedString(string: " ", attributes: textAttributes))
        }
        finalTitle.append(displayTitle)

        statusItem.button?.attributedTitle = finalTitle
        statusItem.button?.toolTip = {
            guard let activeMeetingAlert else { return baseClockTooltip }
            guard !isHoveringMeetingIndicator else { return nil }
            let timeZoneID = settings.primaryTimeZoneID
            return ClockFormatter.meetingTooltipLine(for: activeMeetingAlert, timeZoneID: timeZoneID) + "\n" + baseClockTooltip
        }()
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
    }

    private func updateMeetingIndicatorHoverState() {
        guard activeMeetingAlert != nil, activeMeetingIndicatorHitWidth > 0 else {
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
        let isHoveringIndicator = isInsideButton && mouseInButton.x <= activeMeetingIndicatorHitWidth + 6

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
              let event = NSApp.currentEvent,
              event.type == .leftMouseUp else {
            return false
        }

        let pointInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(pointInButton) && pointInButton.x <= activeMeetingIndicatorHitWidth + 6
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
        let indicatorWidth = max(4, min(activeMeetingIndicatorHitWidth, button.bounds.width))
        let anchorX = max(0, indicatorWidth - 4)
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
            appearanceMode: settings.effectiveAppearanceMode,
            onOpenSettings: { [weak self] pane in self?.openSettings(pane: pane) },
            onSwapTimeZones: { [weak self, weak settings] in
                settings?.swapTimeZones()
                self?.weatherStore.swapClockStates()
            },
            onCreateMeeting: { [weak self] in self?.presentNewMeetingEditor() },
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
    private let subscriptionStore: SubscriptionStore
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
        onCheckForUpdates: @escaping () -> Void,
        onTestReviewPrompt: @escaping () -> Void,
        onWindowClosed: @escaping () -> Void
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.subscriptionStore = subscriptionStore
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
