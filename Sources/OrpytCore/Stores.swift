import Combine
import CoreLocation
import EventKit
import Security
#if os(macOS)
import ServiceManagement
#endif
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
    @Published public var meetingIndicatorStyle: MeetingIndicatorStyle { didSet { scheduleSave() } }
    @Published public var meetingWarningMode: MeetingWarningMode {
        didSet {
            guard !isMutatingMeetingWarningState else {
                scheduleSave()
                return
            }

            switch meetingWarningMode {
            case .preset:
                apply(meetingWarningPreset: meetingWarningPreset)
            case .custom:
                sanitizeMeetingWarningValues(source: .initialLoad)
            }

            scheduleSave()
        }
    }
    @Published public var meetingWarningPreset: MeetingWarningPreset {
        didSet {
            guard !isMutatingMeetingWarningState else {
                scheduleSave()
                return
            }
            apply(meetingWarningPreset: meetingWarningPreset)
            scheduleSave()
        }
    }
    @Published public var meetingEarlyWarningMinutes: Int {
        didSet {
            guard !isMutatingMeetingWarningState else {
                scheduleSave()
                return
            }
            sanitizeMeetingWarningValues(source: .earlyWarning)
            scheduleSave()
        }
    }
    @Published public var meetingCriticalWarningMinutes: Int {
        didSet {
            guard !isMutatingMeetingWarningState else {
                scheduleSave()
                return
            }
            sanitizeMeetingWarningValues(source: .criticalWarning)
            scheduleSave()
        }
    }
    @Published public var meetingIndicatorHoverBehavior: MeetingIndicatorHoverBehavior { didSet { scheduleSave() } }
    @Published public var meetingIndicatorClickAction: MeetingIndicatorClickAction { didSet { scheduleSave() } }
    @Published public var meetingTimeZonePreference: MeetingTimeZonePreference { didSet { scheduleSave() } }
    @Published public private(set) var menuBarLayoutItems: [MenuBarLayoutItem] { didSet { scheduleSave() } }
    @Published public var primaryClockFormatOverride: MenuBarClockFormatOverride { didSet { scheduleSave() } }
    @Published public var secondaryClockFormatOverride: MenuBarClockFormatOverride { didSet { scheduleSave() } }
    @Published public var menuBarSeparatorStyle: MenuBarSeparatorStyle { didSet { scheduleSave() } }
    @Published public var menuBarSpacing: MenuBarSpacing { didSet { scheduleSave() } }
    @Published public var refreshIntervalPreference: RefreshIntervalPreference { didSet { scheduleSave() } }
    @Published public var muteScrollerSound: Bool { didSet { scheduleSave() } }
    // Stored as the enum directly — avoids silent rawValue mismatch fallback to .system
    @Published public var appearanceMode: AppearanceMode { didSet { scheduleSave() } }
    /// Runtime-only: true when the status item is hidden due to menu bar overflow.
    @Published public var isMenuBarOverflowing: Bool = false

    private let defaults = UserDefaults.standard
    private var saveDebounceTask: Task<Void, Never>?
    private var isMutatingMeetingWarningState = false

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
        meetingIndicatorStyle = MeetingIndicatorStyle(rawValue: defaults.string(forKey: SettingsKeys.meetingIndicatorStyle) ?? "") ?? .imminentPill
        meetingWarningMode = MeetingWarningMode(rawValue: defaults.string(forKey: SettingsKeys.meetingWarningMode) ?? "") ?? .preset
        meetingWarningPreset = MeetingWarningPreset(rawValue: defaults.string(forKey: SettingsKeys.meetingWarningPreset) ?? "") ?? .tenAndFive
        meetingEarlyWarningMinutes = defaults.object(forKey: SettingsKeys.meetingEarlyWarningMinutes) as? Int ?? 10
        meetingCriticalWarningMinutes = defaults.object(forKey: SettingsKeys.meetingCriticalWarningMinutes) as? Int ?? 5
        meetingIndicatorHoverBehavior = MeetingIndicatorHoverBehavior(rawValue: defaults.string(forKey: SettingsKeys.meetingIndicatorHoverBehavior) ?? "") ?? .tooltipOnly
        meetingIndicatorClickAction = MeetingIndicatorClickAction(rawValue: defaults.string(forKey: SettingsKeys.meetingIndicatorClickAction) ?? "") ?? .openMeeting
        meetingTimeZonePreference = MeetingTimeZonePreference(rawValue: defaults.string(forKey: SettingsKeys.meetingTimeZonePreference) ?? "") ?? .system
        menuBarLayoutItems = Self.sanitizedMenuBarLayoutItems(
            defaults.stringArray(forKey: SettingsKeys.menuBarLayoutItems)?
                .compactMap(MenuBarLayoutItem.init(rawValue:))
        )
        primaryClockFormatOverride = MenuBarClockFormatOverride(rawValue: defaults.string(forKey: SettingsKeys.primaryClockFormatOverride) ?? "") ?? .appDefault
        secondaryClockFormatOverride = MenuBarClockFormatOverride(rawValue: defaults.string(forKey: SettingsKeys.secondaryClockFormatOverride) ?? "") ?? .appDefault
        menuBarSeparatorStyle = MenuBarSeparatorStyle(rawValue: defaults.string(forKey: SettingsKeys.menuBarSeparatorStyle) ?? "") ?? .pipe
        menuBarSpacing = MenuBarSpacing(rawValue: defaults.string(forKey: SettingsKeys.menuBarSpacing) ?? "") ?? .comfortable
        refreshIntervalPreference = RefreshIntervalPreference(rawValue: defaults.string(forKey: SettingsKeys.refreshIntervalPreference) ?? "") ?? .automatic
        muteScrollerSound = defaults.object(forKey: SettingsKeys.muteScrollerSound) as? Bool ?? false
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: SettingsKeys.appearanceModeRawValue) ?? "") ?? .system

        sanitizeMeetingWarningValues(source: .initialLoad)
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
        meetingIndicatorStyle = .imminentPill
        meetingWarningMode = .preset
        meetingWarningPreset = .tenAndFive
        meetingEarlyWarningMinutes = 10
        meetingCriticalWarningMinutes = 5
        meetingIndicatorHoverBehavior = .tooltipOnly
        meetingIndicatorClickAction = .openMeeting
        meetingTimeZonePreference = .system
        menuBarLayoutItems = MenuBarLayoutItem.defaultOrder
        primaryClockFormatOverride = .appDefault
        secondaryClockFormatOverride = .appDefault
        menuBarSeparatorStyle = .pipe
        menuBarSpacing = .comfortable
        refreshIntervalPreference = .automatic
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

    public var effectiveMeetingIndicatorStyle: MeetingIndicatorStyle {
        effectiveCalendarEnabled ? meetingIndicatorStyle : .off
    }

    public var effectiveMenuBarLayoutItems: [MenuBarLayoutItem] {
        SubscriptionStore.shared.hasAccess(to: .appearance)
            ? menuBarLayoutItems
            : MenuBarLayoutItem.defaultOrder
    }

    public var effectiveMenuBarSeparatorStyle: MenuBarSeparatorStyle {
        SubscriptionStore.shared.hasAccess(to: .appearance) ? menuBarSeparatorStyle : .pipe
    }

    public var effectiveMenuBarSpacing: MenuBarSpacing {
        SubscriptionStore.shared.hasAccess(to: .appearance) ? menuBarSpacing : .comfortable
    }

    public func effectiveClockFormatOverride(for slot: ClockSlot) -> MenuBarClockFormatOverride {
        guard SubscriptionStore.shared.hasAccess(to: .appearance) else { return .appDefault }
        switch slot {
        case .primary:
            return primaryClockFormatOverride
        case .secondary:
            return secondaryClockFormatOverride
        }
    }

    public func refreshInterval(for defaultInterval: TimeInterval) -> TimeInterval {
        guard SubscriptionStore.shared.hasAccess(to: .appearance) else { return defaultInterval }
        return refreshIntervalPreference.interval ?? defaultInterval
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

    public func moveMenuBarLayoutItems(from source: IndexSet, to destination: Int) {
        var items = menuBarLayoutItems
        items.move(fromOffsets: source, toOffset: destination)
        setMenuBarLayoutItems(items)
    }

    public func setMenuBarLayoutItems(_ items: [MenuBarLayoutItem]) {
        menuBarLayoutItems = Self.sanitizedMenuBarLayoutItems(items)
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
        defaults.set(meetingIndicatorStyle.rawValue, forKey: SettingsKeys.meetingIndicatorStyle)
        defaults.set(meetingWarningMode.rawValue, forKey: SettingsKeys.meetingWarningMode)
        defaults.set(meetingWarningPreset.rawValue, forKey: SettingsKeys.meetingWarningPreset)
        defaults.set(meetingEarlyWarningMinutes, forKey: SettingsKeys.meetingEarlyWarningMinutes)
        defaults.set(meetingCriticalWarningMinutes, forKey: SettingsKeys.meetingCriticalWarningMinutes)
        defaults.set(meetingIndicatorHoverBehavior.rawValue, forKey: SettingsKeys.meetingIndicatorHoverBehavior)
        defaults.set(meetingIndicatorClickAction.rawValue, forKey: SettingsKeys.meetingIndicatorClickAction)
        defaults.set(meetingTimeZonePreference.rawValue, forKey: SettingsKeys.meetingTimeZonePreference)
        defaults.set(menuBarLayoutItems.map(\.rawValue), forKey: SettingsKeys.menuBarLayoutItems)
        defaults.set(primaryClockFormatOverride.rawValue, forKey: SettingsKeys.primaryClockFormatOverride)
        defaults.set(secondaryClockFormatOverride.rawValue, forKey: SettingsKeys.secondaryClockFormatOverride)
        defaults.set(menuBarSeparatorStyle.rawValue, forKey: SettingsKeys.menuBarSeparatorStyle)
        defaults.set(menuBarSpacing.rawValue, forKey: SettingsKeys.menuBarSpacing)
        defaults.set(refreshIntervalPreference.rawValue, forKey: SettingsKeys.refreshIntervalPreference)
        defaults.set(muteScrollerSound, forKey: SettingsKeys.muteScrollerSound)
        defaults.set(appearanceMode.rawValue, forKey: SettingsKeys.appearanceModeRawValue)
    }

    private static func sanitizedMenuBarLayoutItems(_ items: [MenuBarLayoutItem]?) -> [MenuBarLayoutItem] {
        var result: [MenuBarLayoutItem] = []
        for item in items ?? [] where !result.contains(item) {
            result.append(item)
        }

        for item in MenuBarLayoutItem.defaultOrder where !result.contains(item) {
            result.append(item)
        }

        return result
    }

    private enum MeetingWarningSanitizationSource {
        case initialLoad
        case preset
        case earlyWarning
        case criticalWarning
    }

    private func apply(meetingWarningPreset: MeetingWarningPreset) {
        guard meetingWarningMode == .preset else { return }
        mutateMeetingWarningState {
            meetingEarlyWarningMinutes = meetingWarningPreset.earlyWarningMinutes
            meetingCriticalWarningMinutes = meetingWarningPreset.criticalWarningMinutes
        }
    }

    private func sanitizeMeetingWarningValues(source: MeetingWarningSanitizationSource) {
        var normalizedEarly = min(max(meetingEarlyWarningMinutes, 2), 60)
        var normalizedCritical = min(max(meetingCriticalWarningMinutes, 1), 59)
        var normalizedPreset = meetingWarningPreset

        if normalizedEarly <= normalizedCritical {
            switch source {
            case .criticalWarning:
                normalizedEarly = min(max(normalizedCritical + 1, 2), 60)
            default:
                normalizedCritical = max(1, min(normalizedEarly - 1, 59))
            }
        }

        if meetingWarningMode == .preset {
            if let matchingPreset = MeetingWarningPreset.allCases.first(where: {
                $0.earlyWarningMinutes == normalizedEarly && $0.criticalWarningMinutes == normalizedCritical
            }) {
                normalizedPreset = matchingPreset
            } else {
                normalizedPreset = .tenAndFive
                normalizedEarly = normalizedPreset.earlyWarningMinutes
                normalizedCritical = normalizedPreset.criticalWarningMinutes
            }
        }

        mutateMeetingWarningState {
            if meetingEarlyWarningMinutes != normalizedEarly {
                meetingEarlyWarningMinutes = normalizedEarly
            }

            if meetingCriticalWarningMinutes != normalizedCritical {
                meetingCriticalWarningMinutes = normalizedCritical
            }

            if meetingWarningMode == .preset, meetingWarningPreset != normalizedPreset {
                meetingWarningPreset = normalizedPreset
            }
        }
    }

    private func mutateMeetingWarningState(_ updates: () -> Void) {
        let wasMutating = isMutatingMeetingWarningState
        isMutatingMeetingWarningState = true
        updates()
        isMutatingMeetingWarningState = wasMutating
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
    public static let meetingIndicatorStyle = "meetingIndicatorStyle"
    public static let meetingWarningMode = "meetingWarningMode"
    public static let meetingWarningPreset = "meetingWarningPreset"
    public static let meetingEarlyWarningMinutes = "meetingEarlyWarningMinutes"
    public static let meetingCriticalWarningMinutes = "meetingCriticalWarningMinutes"
    public static let meetingIndicatorHoverBehavior = "meetingIndicatorHoverBehavior"
    public static let meetingIndicatorClickAction = "meetingIndicatorClickAction"
    public static let meetingTimeZonePreference = "meetingTimeZonePreference"
    public static let menuBarLayoutItems = "menuBarLayoutItems"
    public static let primaryClockFormatOverride = "primaryClockFormatOverride"
    public static let secondaryClockFormatOverride = "secondaryClockFormatOverride"
    public static let menuBarSeparatorStyle = "menuBarSeparatorStyle"
    public static let menuBarSpacing = "menuBarSpacing"
    public static let refreshIntervalPreference = "refreshIntervalPreference"
    public static let muteScrollerSound = "muteScrollerSound"
    public static let appearanceModeRawValue = "appearanceModeRawValue"
}

public enum MenuBarLayoutItem: String, CaseIterable, Identifiable, Sendable {
    case agentIndicator
    case meetingIndicator
    case primaryClock
    case secondaryClock

    public static let defaultOrder: [MenuBarLayoutItem] = [.agentIndicator, .meetingIndicator, .primaryClock, .secondaryClock]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agentIndicator:
            return "AI activity"
        case .meetingIndicator:
            return "Meeting indicator"
        case .primaryClock:
            return "Primary clock"
        case .secondaryClock:
            return "Secondary clock"
        }
    }

    public var compactTitle: String {
        switch self {
        case .agentIndicator:
            return "AI"
        case .meetingIndicator:
            return "Now"
        case .primaryClock:
            return "Primary"
        case .secondaryClock:
            return "Secondary"
        }
    }

    public var systemImageName: String {
        switch self {
        case .agentIndicator:
            return "sparkles"
        case .meetingIndicator:
            return "clock.badge.fill"
        case .primaryClock:
            return "cloud.sun.fill"
        case .secondaryClock:
            return "cloud.fill"
        }
    }
}

public enum MenuBarClockFormatOverride: String, CaseIterable, Identifiable, Sendable {
    case appDefault
    case twelveHour
    case twentyFourHour

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appDefault:
            return "App default"
        case .twelveHour:
            return "12-hour"
        case .twentyFourHour:
            return "24-hour"
        }
    }

    public func uses24Hour(appDefault: Bool) -> Bool {
        switch self {
        case .appDefault:
            return appDefault
        case .twelveHour:
            return false
        case .twentyFourHour:
            return true
        }
    }
}

public enum MenuBarSeparatorStyle: String, CaseIterable, Identifiable, Sendable {
    case pipe
    case dot

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pipe:
            return "Pipe"
        case .dot:
            return "Dot"
        }
    }

    public var symbol: String {
        switch self {
        case .pipe:
            return "|"
        case .dot:
            return "•"
        }
    }
}

public enum MenuBarSpacing: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact:
            return "Compact"
        case .comfortable:
            return "Comfortable"
        }
    }

    public var separatorPadding: String {
        switch self {
        case .compact:
            return " "
        case .comfortable:
            return "  "
        }
    }
}

public enum RefreshIntervalPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case oneMinute
    case fiveMinutes
    case fifteenMinutes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .oneMinute:
            return "Every 1 minute"
        case .fiveMinutes:
            return "Every 5 minutes"
        case .fifteenMinutes:
            return "Every 15 minutes"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .automatic:
            return nil
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 5 * 60
        case .fifteenMinutes:
            return 15 * 60
        }
    }
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
        #if os(macOS)
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
        #else
        isAvailable = false
        isEnabled = false
        statusMessage = "Launch at login is only available on Mac."
        errorMessage = nil
        #endif
    }

    public func setEnabled(_ enabled: Bool) {
        #if os(macOS)
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
        #else
        refresh()
        #endif
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

    @Published public private(set) var state: CalendarState = .disabled

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
        } else if isWriteOnly(authorization) {
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
            let granted = try await requestEventAccess()

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

            var localCalendar = Calendar.autoupdatingCurrent
            localCalendar.timeZone = .autoupdatingCurrent
            let endOfDay = localCalendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? endDate

            let snapshots = events.map { event in
                MeetingSnapshot(
                    id: event.calendarItemIdentifier,
                    title: { let t = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return t.isEmpty ? "Untitled meeting" : t }(),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarName: event.calendar.title,
                    timeZoneID: event.timeZone?.identifier,
                    joinURL: Self.extractJoinURL(from: event)
                )
            }

            let todayAgenda = snapshots.filter { $0.startDate <= endOfDay }
            let snapshot = snapshots.isEmpty ? nil : CalendarAgendaSnapshot(
                nextMeeting: snapshots.first,
                todayAgenda: todayAgenda
            )

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

    public var nextMeeting: MeetingSnapshot? {
        guard case let .loaded(snapshot) = state else { return nil }
        return snapshot?.nextMeeting
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

    private func isWriteOnly(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .writeOnly
        }
        return false
    }

    private func requestEventAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        }
        return try await requestLegacyEventAccess()
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
