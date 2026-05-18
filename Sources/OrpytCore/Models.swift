import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

public struct WeatherSnapshot {
    public let symbolName: String
    public let temperatureText: String
    public let conditionText: String
    public let feelsLikeText: String
    public let resolvedLocationName: String
}

public struct WeatherAttributionSnapshot {
    public let combinedMarkLightURL: URL
    public let combinedMarkDarkURL: URL
    public let legalPageURL: URL
}

public struct MeetingSnapshot: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarName: String
    public let joinURL: URL?

    public var hasJoinURL: Bool {
        joinURL != nil
    }
}

public struct CalendarAgendaSnapshot: Equatable {
    public let nextMeeting: MeetingSnapshot?
    public let todayAgenda: [MeetingSnapshot]

    public var hasJoinableMeeting: Bool {
        todayAgenda.contains(where: \.hasJoinURL)
    }
}

public enum WeatherState {
    case idle
    case loading
    case loaded(WeatherSnapshot)
    case failed(String)
}

public enum CalendarState {
    case disabled
    case needsPermission
    case loading
    case loaded(CalendarAgendaSnapshot?)
    case failed(String)
}

public enum MeetingIndicatorStyle: String, Codable, CaseIterable, Identifiable {
    case off
    case tinyBadge
    case imminentPill
    case fullReplace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .tinyBadge: return "Tiny Badge"
        case .imminentPill: return "Imminent Pill"
        case .fullReplace: return "Full Replace"
        }
    }
}

public enum MeetingWarningMode: String, Codable, CaseIterable, Identifiable {
    case preset
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preset: return "Preset"
        case .custom: return "Custom"
        }
    }
}

public enum MeetingWarningPreset: String, Codable, CaseIterable, Identifiable {
    case fiveMinutesOnly
    case tenAndFive
    case fifteenAndFive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fiveMinutesOnly: return "5 min only"
        case .tenAndFive: return "10 / 5 min"
        case .fifteenAndFive: return "15 / 5 min"
        }
    }

    public var earlyWarningMinutes: Int {
        switch self {
        case .fiveMinutesOnly: return 5
        case .tenAndFive: return 10
        case .fifteenAndFive: return 15
        }
    }

    public var criticalWarningMinutes: Int {
        switch self {
        case .fiveMinutesOnly: return 1
        case .tenAndFive: return 5
        case .fifteenAndFive: return 5
        }
    }
}

public enum MeetingIndicatorHoverBehavior: String, Codable, CaseIterable, Identifiable {
    case tooltipOnly
    case previewShortTitle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tooltipOnly: return "Tooltip Only"
        case .previewShortTitle: return "Preview Popover"
        }
    }
}

public enum MeetingIndicatorClickAction: String, Codable, CaseIterable, Identifiable {
    case openMeeting
    case openCalendar
    case revealTitle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openMeeting: return "Join or Open Meeting"
        case .openCalendar: return "Open Calendar"
        case .revealTitle: return "Reveal Title"
        }
    }
}

public enum MeetingAlertPhase: Equatable {
    case early
    case critical
}

public struct MeetingAlertSnapshot: Equatable {
    public let meeting: MeetingSnapshot
    public let phase: MeetingAlertPhase
    public let minutesUntilStart: Int
    public let isLive: Bool
}

public struct WeatherRefreshConfiguration {
    public let enableWeather: Bool
    public let showPrimaryClock: Bool
    public let showSecondaryClock: Bool
    public let primaryTimeZoneID: String
    public let secondaryTimeZoneID: String
    public let primaryQuery: String
    public let secondaryQuery: String

    @MainActor
    public init(settings: ClockSettingsStore) {
        enableWeather = settings.effectiveWeatherEnabled
        showPrimaryClock = settings.showPrimaryClock
        showSecondaryClock = settings.showSecondaryClock
        primaryTimeZoneID = settings.primaryTimeZoneID
        secondaryTimeZoneID = settings.secondaryTimeZoneID
        primaryQuery = settings.primaryWeatherLocation
        secondaryQuery = settings.secondaryWeatherLocation
    }
}
