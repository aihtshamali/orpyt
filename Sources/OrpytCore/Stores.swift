import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

@MainActor
public final class ClockSettingsStore: ObservableObject {
    public static let shared = ClockSettingsStore()

    @Published private(set) var hasCompletedFirstLaunch: Bool { didSet { scheduleSave() } }
    @Published public var primaryTimeZoneID: String { didSet { scheduleSave() } }
    @Published public var secondaryTimeZoneID: String { didSet { scheduleSave() } }
    @Published public var primaryCustomLabel: String { didSet { scheduleSave() } }
    @Published public var secondaryCustomLabel: String { didSet { scheduleSave() } }
    @Published public var showPrimaryClock: Bool {
        didSet {
            // Invariant: at least one clock must be visible
            if !showPrimaryClock && !showSecondaryClock { showSecondaryClock = true }
            scheduleSave()
        }
    }
    @Published public var showSecondaryClock: Bool {
        didSet {
            // Invariant: at least one clock must be visible
            if !showPrimaryClock && !showSecondaryClock { showPrimaryClock = true }
            scheduleSave()
        }
    }
    @Published public var use24HourClock: Bool { didSet { scheduleSave() } }
    @Published public var showSeconds: Bool { didSet { scheduleSave() } }
    @Published public var showWeekday: Bool { didSet { scheduleSave() } }
    @Published public var showDate: Bool { didSet { scheduleSave() } }
    @Published public var showTimeZoneAbbreviation: Bool { didSet { scheduleSave() } }
    @Published public var showGMTOffset: Bool { didSet { scheduleSave() } }
    @Published public var showZoneLabelInMenuBar: Bool { didSet { scheduleSave() } }
    @Published public var showStatusIcon: Bool {
        didSet {
            // Mutual exclusion: ambient icon and weather icon cannot both be on.
            if showStatusIcon && showWeatherInMenuBar { showWeatherInMenuBar = false }
            scheduleSave()
        }
    }
    @Published public var enableWeather: Bool { didSet { scheduleSave() } }
    @Published public var showWeatherInMenuBar: Bool {
        didSet {
            // Mutual exclusion: weather icon and ambient icon cannot both be on.
            if showWeatherInMenuBar && showStatusIcon { showStatusIcon = false }
            scheduleSave()
        }
    }
    @Published public var showWeatherLocation: Bool { didSet { scheduleSave() } }
    @Published public var showFeelsLikeTemperature: Bool { didSet { scheduleSave() } }
    @Published public var primaryWeatherLocation: String { didSet { scheduleSave() } }
    @Published public var secondaryWeatherLocation: String { didSet { scheduleSave() } }
    @Published public var showCalendarEvents: Bool { didSet { scheduleSave() } }
    @Published public var muteScrollerSound: Bool { didSet { scheduleSave() } }
    // Stored as the enum directly — avoids silent rawValue mismatch fallback to .system
    @Published public var appearanceMode: AppearanceMode { didSet { scheduleSave() } }
    /// Runtime-only: true when the status item is hidden due to menu bar overflow.
    @Published public var isMenuBarOverflowing: Bool = false

    private let defaults = UserDefaults.standard
    private var saveDebounceTask: Task<Void, Never>?

    private init() {
        hasCompletedFirstLaunch = defaults.object(forKey: SettingsKeys.hasCompletedFirstLaunch) as? Bool ?? false
        let savedPrimary = defaults.string(forKey: SettingsKeys.primaryTimeZoneID) ?? TimeZoneCatalog.defaultPrimaryID
        let savedSecondary = defaults.string(forKey: SettingsKeys.secondaryTimeZoneID)
            ?? TimeZoneCatalog.defaultSecondaryID(relativeTo: savedPrimary)

        primaryTimeZoneID = TimeZoneCatalog.option(for: savedPrimary)?.id ?? TimeZoneCatalog.defaultPrimaryID
        secondaryTimeZoneID = TimeZoneCatalog.option(for: savedSecondary)?.id
            ?? TimeZoneCatalog.defaultSecondaryID(relativeTo: savedPrimary)
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
        enableWeather = defaults.object(forKey: SettingsKeys.enableWeather) as? Bool ?? true
        showWeatherInMenuBar = defaults.object(forKey: SettingsKeys.showWeatherInMenuBar) as? Bool ?? true
        showWeatherLocation = defaults.object(forKey: SettingsKeys.showWeatherLocation) as? Bool ?? true
        showFeelsLikeTemperature = defaults.object(forKey: SettingsKeys.showFeelsLikeTemperature) as? Bool ?? true
        primaryWeatherLocation = defaults.string(forKey: SettingsKeys.primaryWeatherLocation) ?? ""
        secondaryWeatherLocation = defaults.string(forKey: SettingsKeys.secondaryWeatherLocation) ?? ""
        showCalendarEvents = defaults.object(forKey: SettingsKeys.showCalendarEvents) as? Bool ?? true
        muteScrollerSound = defaults.object(forKey: SettingsKeys.muteScrollerSound) as? Bool ?? false
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: SettingsKeys.appearanceModeRawValue) ?? "") ?? .system
    }

    public func performInitialSetupIfNeeded() -> Bool {
        guard !hasCompletedFirstLaunch else { return false }

        let primaryIdentifier = TimeZone.current.identifier
        let secondaryIdentifier = TimeZoneCatalog.defaultSecondaryID(relativeTo: primaryIdentifier)

        primaryTimeZoneID = TimeZoneCatalog.option(for: primaryIdentifier)?.id ?? primaryIdentifier
        secondaryTimeZoneID = TimeZoneCatalog.option(for: secondaryIdentifier)?.id ?? secondaryIdentifier
        primaryCustomLabel = ""
        secondaryCustomLabel = ""
        showPrimaryClock = true
        showSecondaryClock = true
        enableWeather = true
        showCalendarEvents = true
        hasCompletedFirstLaunch = true
        return true
    }

    public func swapTimeZones() {
        let originalPrimaryZone = primaryTimeZoneID
        let originalPrimaryLabel = primaryCustomLabel
        primaryTimeZoneID = secondaryTimeZoneID
        primaryCustomLabel = secondaryCustomLabel
        secondaryTimeZoneID = originalPrimaryZone
        secondaryCustomLabel = originalPrimaryLabel
    }

    public func displayLabel(for timeZoneID: String, customLabel: String) -> String {
        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return TimeZoneCatalog.option(for: timeZoneID)?.shortLabel ?? "TZ"
    }

    public var preferredColorScheme: ColorScheme? {
        switch effectiveAppearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    public var effectiveAppearanceMode: AppearanceMode {
        SubscriptionStore.shared.hasAccess(to: .appearance) ? appearanceMode : .system
    }

    public var effectiveWeatherEnabled: Bool {
        enableWeather && SubscriptionStore.shared.hasAccess(to: .weather)
    }

    public var effectiveCalendarEnabled: Bool {
        showCalendarEvents && SubscriptionStore.shared.hasAccess(to: .calendar)
    }

    /// Sets icon visibility with mutual exclusion: ambient and weather icons cannot both be on.
    /// Both can be off (no icon). If both are requested on, weather takes priority.
    public func setMenuBarVisibility(icon: Bool, weather: Bool) {
        // weather takes priority when both requested; didSet enforces mutual exclusion automatically
        showWeatherInMenuBar = weather
        if !weather {
            showStatusIcon = icon
        }
    }

    private func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        defaults.set(hasCompletedFirstLaunch, forKey: SettingsKeys.hasCompletedFirstLaunch)
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
        defaults.set(showCalendarEvents, forKey: SettingsKeys.showCalendarEvents)
        defaults.set(muteScrollerSound, forKey: SettingsKeys.muteScrollerSound)
        defaults.set(appearanceMode.rawValue, forKey: SettingsKeys.appearanceModeRawValue)
    }
}

public enum SettingsKeys {
    public static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
    public static let primaryTimeZoneID = "primaryTimeZoneID"
    public static let secondaryTimeZoneID = "secondaryTimeZoneID"
    public static let primaryCustomLabel = "primaryCustomLabel"
    public static let secondaryCustomLabel = "secondaryCustomLabel"
    public static let showPrimaryClock = "showPrimaryClock"
    public static let showSecondaryClock = "showSecondaryClock"
    public static let use24HourClock = "use24HourClock"
    public static let showSeconds = "showSeconds"
    public static let showWeekday = "showWeekday"
    public static let showDate = "showDate"
    public static let showTimeZoneAbbreviation = "showTimeZoneAbbreviation"
    public static let showGMTOffset = "showGMTOffset"
    public static let showZoneLabelInMenuBar = "showZoneLabelInMenuBar"
    public static let showStatusIcon = "showStatusIcon"
    public static let enableWeather = "enableWeather"
    public static let showWeatherInMenuBar = "showWeatherInMenuBar"
    public static let showWeatherLocation = "showWeatherLocation"
    public static let showFeelsLikeTemperature = "showFeelsLikeTemperature"
    public static let primaryWeatherLocation = "primaryWeatherLocation"
    public static let secondaryWeatherLocation = "secondaryWeatherLocation"
    public static let showCalendarEvents = "showCalendarEvents"
    public static let muteScrollerSound = "muteScrollerSound"
    public static let appearanceModeRawValue = "appearanceModeRawValue"
}

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = "Start Orpyt automatically when you sign in."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAvailable = true

    private init() {
        refresh()
    }

    public func refresh() {
        guard #available(macOS 13.0, *) else {
            isAvailable = false
            isEnabled = false
            statusMessage = "Launch at login requires a newer macOS release."
            return
        }

        isAvailable = true
        errorMessage = nil

        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = "Orpyt will open automatically after you sign in."
        case .requiresApproval:
            isEnabled = true
            statusMessage = "Enable Orpyt in Login Items to finish setup."
        case .notRegistered:
            isEnabled = false
            statusMessage = "Start Orpyt automatically when you sign in."
        case .notFound:
            isEnabled = false
            statusMessage = "Launch at login needs a signed app bundle."
        @unknown default:
            isEnabled = false
            statusMessage = "Launch at login status is unavailable right now."
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            refresh()
            return
        }

        errorMessage = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }
}

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
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

public enum ClockSlot: Hashable {
    case primary
    case secondary
}

@MainActor
public final class CalendarStore: ObservableObject {
    public static let shared = CalendarStore()

    @Published private(set) var state: CalendarState = .disabled

    private var eventStore = EKEventStore()
    private var refreshTask: Task<Void, Never>?

    public func prepareForLaunch(using settings: ClockSettingsStore) {
        guard settings.showCalendarEvents else {
            state = .disabled
            return
        }

        Task { await syncAuthorization(using: settings) }
    }

    public func syncAuthorization(using settings: ClockSettingsStore) async {
        guard settings.showCalendarEvents else {
            state = .disabled
            return
        }

        // Recreate the store to pick up TCC changes made while Orpyt was running.
        eventStore = EKEventStore()
        let authorization = authorizationStatus

        if isAuthorized(authorization) {
            await refresh(using: settings)
        } else if authorization == .notDetermined {
            state = .needsPermission
        } else if #available(macOS 14.0, *), authorization == .writeOnly {
            state = .failed("Calendar needs full access")
        } else {
            state = .failed("Calendar access is off")
        }
    }

    public func enable(using settings: ClockSettingsStore) async {
        // Reset the store so it picks up any authorization changes made in System Settings.
        eventStore = EKEventStore()
        let authorization = authorizationStatus

        if isAuthorized(authorization) {
            await refresh(using: settings)
            return
        }

        if authorization == .denied || authorization == .restricted {
            state = .failed("Calendar access is off")
            return
        }

        state = .loading

        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await requestLegacyEventAccess()
            }

            if granted {
                eventStore = EKEventStore()
                await refresh(using: settings)
            } else {
                state = .failed("Calendar access is off")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func refresh(using settings: ClockSettingsStore) async {
        guard settings.showCalendarEvents else {
            disable()
            return
        }

        let authorization = authorizationStatus
        guard isAuthorized(authorization) else {
            state = authorization == .notDetermined ? .needsPermission : .failed("Calendar access is off")
            return
        }

        refreshTask?.cancel()
        state = .loading

        refreshTask = Task {
            let now = Date()
            let endDate = now.addingTimeInterval(60 * 60 * 24)
            let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
            let events = eventStore.events(matching: predicate)
                .filter { !$0.isAllDay && $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }

            let snapshot = events.first.map { event -> MeetingSnapshot in
                MeetingSnapshot(
                    title: { let t = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return t.isEmpty ? "Untitled meeting" : t }(),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarName: event.calendar.title,
                    joinURL: Self.extractJoinURL(from: event)
                )
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.state = .loaded(snapshot)
            }
        }
    }

    public func disable() {
        refreshTask?.cancel()
        state = .disabled
    }

    private static func extractJoinURL(from event: EKEvent) -> URL? {
        // Prefer the explicit URL field on the event
        if let url = event.url {
            return url
        }
        // Fall back to scanning notes for a video call link
        guard let notes = event.notes else { return nil }
        let patterns = ["https://zoom.us/", "https://meet.google.com/", "https://teams.microsoft.com/", "https://us.webex.com/", "https://meet.lync.com/"]
        let words = notes.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            if let url = URL(string: word), patterns.contains(where: { word.hasPrefix($0) }) {
                return url
            }
        }
        return nil
    }

    private var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    private func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .authorized
        }

        return status == .authorized
    }

    private func requestLegacyEventAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
