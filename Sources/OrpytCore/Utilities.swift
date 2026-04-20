import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

@MainActor
public enum ClockFormatter {
    private static var formatterCache: [String: DateFormatter] = [:]

    public static func menuBarAttributedTitle(
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

    public static func menuBarTitle(for date: Date, settings: ClockSettingsStore) -> String {
        let segments = visibleSegments(for: date, settings: settings)
        return segments.isEmpty ? "Orpyt" : segments.joined(separator: " | ")
    }

    public static func menuBarTooltip(for date: Date, settings: ClockSettingsStore, weatherStore: WeatherStore) -> String {
        let lines = visibleDetailLines(for: date, settings: settings, weatherStore: weatherStore)
        return lines.isEmpty ? "Orpyt" : lines.joined(separator: "\n")
    }

    public static func timeText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
        let format = settings.use24HourClock
            ? (settings.showSeconds ? "HH:mm:ss" : "HH:mm")
            : (settings.showSeconds ? "h:mm:ss a" : "h:mm a")
        let formatter = formatter(for: timeZoneID, format: format)
        return formatter.string(from: date)
    }

    public static func dateText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
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

    public static func metaText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
        var parts: [String] = []

        if settings.showTimeZoneAbbreviation, let abbreviation = TimeZone(identifier: timeZoneID)?.abbreviation(for: date) {
            parts.append(abbreviation)
        }

        if settings.showGMTOffset, let timeZone = TimeZone(identifier: timeZoneID) {
            parts.append(gmtOffsetText(for: timeZone, date: date))
        }

        return parts.joined(separator: "  ")
    }

    public static func detailLine(
        for date: Date,
        timeZoneID: String,
        label: String,
        settings: ClockSettingsStore,
        weatherState: WeatherState
    ) -> String {
        var parts = [
            "\(label): \(timeText(for: date, timeZoneID: timeZoneID, settings: settings))",
        ]

        let dateString = dateText(for: date, timeZoneID: timeZoneID, settings: settings)
        if !dateString.isEmpty {
            parts.append(dateString)
        }

        if settings.enableWeather {
            switch weatherState {
            case let .loaded(snapshot):
                parts.append("\(snapshot.temperatureText), \(snapshot.conditionText)")
            default:
                break
            }
        }

        return parts.joined(separator: " | ")
    }

    public static func cardIconName(for date: Date, timeZoneID: String, weatherState: WeatherState) -> String {
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

public enum TimeZoneCatalog {
    public static let defaultPrimaryID = TimeZone.current.identifier

    public static func defaultSecondaryID(relativeTo primaryID: String) -> String {
        let candidates = ["Etc/UTC", "Europe/London", "America/New_York"]
        return candidates.first(where: { $0 != primaryID && option(for: $0) != nil }) ?? "Europe/London"
    }

    nonisolated(unsafe) static let options: [TimeZoneOption] = {
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

    nonisolated(unsafe) private static let optionIndex: [String: TimeZoneOption] = Dictionary(
        uniqueKeysWithValues: options.map { ($0.id, $0) }
    )

    public static func option(for id: String) -> TimeZoneOption? {
        optionIndex[id]
    }

    public static func weatherLookupName(for id: String) -> String {
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

    public static func representativeLocation(for id: String) -> CLLocation? {
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

public struct TimeZoneOption: Identifiable, Hashable {
    public let id: String
    public let shortLabel: String
    public let cityName: String
    public let displayName: String
    public let searchableText: String

    public var utcOffsetSeconds: Int {
        TimeZone(identifier: id)?.secondsFromGMT() ?? 0
    }
}
