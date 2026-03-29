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

public struct MeetingSnapshot {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarName: String
    public let joinURL: URL?
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
    case loaded(MeetingSnapshot?)
    case failed(String)
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
        enableWeather = settings.enableWeather
        showPrimaryClock = settings.showPrimaryClock
        showSecondaryClock = settings.showSecondaryClock
        primaryTimeZoneID = settings.primaryTimeZoneID
        secondaryTimeZoneID = settings.secondaryTimeZoneID
        primaryQuery = ""
        secondaryQuery = ""
    }
}
