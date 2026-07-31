#if canImport(AppKit)
import AppKit
#endif
import Combine
import CoreLocation
import EventKit
import Security
import SwiftUI
import WeatherKit

@MainActor
public enum ClockFormatter {
    #if os(macOS)
    public struct MenuBarMeetingIndicatorRender {
        public let prefix: NSAttributedString
        public let hitWidth: CGFloat

        public init(prefix: NSAttributedString, hitWidth: CGFloat) {
            self.prefix = prefix
            self.hitWidth = hitWidth
        }
    }

    public struct MenuBarClockSegment {
        public let item: MenuBarLayoutItem
        public let slot: ClockSlot
        public let attributedTitle: NSAttributedString
        public let plainTitle: String

        public init(item: MenuBarLayoutItem, slot: ClockSlot, attributedTitle: NSAttributedString, plainTitle: String) {
            self.item = item
            self.slot = slot
            self.attributedTitle = attributedTitle
            self.plainTitle = plainTitle
        }
    }
    #endif

    private static var formatterCache: [String: DateFormatter] = [:]

    #if os(macOS)
    public static func menuBarAttributedTitle(
        for date: Date,
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        primaryTextOverride: String? = nil
    ) -> NSAttributedString {
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let titleColor = NSColor.labelColor
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
        ]

        let segments = menuBarClockSegments(
            for: date,
            settings: settings,
            weatherStore: weatherStore,
            primaryTextOverride: primaryTextOverride,
            attributes: textAttributes,
            font: titleFont
        )

        guard !segments.isEmpty else {
            return NSAttributedString(string: "Orpyt", attributes: textAttributes)
        }

        let result = NSMutableAttributedString()

        for (index, segment) in segments.enumerated() {
            result.append(segment.attributedTitle)

            if index < segments.count - 1 {
                result.append(menuBarSeparator(settings: settings, attributes: textAttributes))
            }
        }

        return result
    }
    #endif

    public static func menuBarTitle(for date: Date, settings: ClockSettingsStore) -> String {
        let segments = visibleSegments(for: date, settings: settings)
        let separator = plainMenuBarSeparator(settings: settings)
        return segments.isEmpty ? "Orpyt" : segments.joined(separator: separator)
    }

    public static func menuBarTooltip(for date: Date, settings: ClockSettingsStore, weatherStore: WeatherStore) -> String {
        let lines = visibleDetailLines(for: date, settings: settings, weatherStore: weatherStore)
        return lines.isEmpty ? "Orpyt" : lines.joined(separator: "\n")
    }

    public static func activeMeetingAlert(
        for date: Date,
        settings: ClockSettingsStore,
        calendarState: CalendarState
    ) -> MeetingAlertSnapshot? {
        guard settings.effectiveMeetingIndicatorStyle != .off,
              case let .loaded(snapshot) = calendarState,
              let meeting = snapshot?.nextMeeting else {
            return nil
        }

        if date >= meeting.startDate && date < meeting.endDate {
            return MeetingAlertSnapshot(
                meeting: meeting,
                phase: .critical,
                minutesUntilStart: 0,
                isLive: true
            )
        }

        guard meeting.startDate > date else {
            return nil
        }

        let secondsUntilStart = meeting.startDate.timeIntervalSince(date)
        let minutesUntilStart = max(1, Int(ceil(secondsUntilStart / 60)))

        guard minutesUntilStart <= settings.meetingEarlyWarningMinutes else {
            return nil
        }

        return MeetingAlertSnapshot(
            meeting: meeting,
            phase: minutesUntilStart <= settings.meetingCriticalWarningMinutes ? .critical : .early,
            minutesUntilStart: minutesUntilStart,
            isLive: false
        )
    }

    #if os(macOS)
    public static func meetingIndicatorRender(
        for alert: MeetingAlertSnapshot,
        style: MeetingIndicatorStyle,
        font: NSFont
    ) -> MenuBarMeetingIndicatorRender? {
        switch style {
        case .off:
            return nil
        case .tinyBadge:
            guard let prefix = tinyBadgeAttachment(for: alert, font: font) else { return nil }
            return MenuBarMeetingIndicatorRender(prefix: prefix, hitWidth: font.pointSize + 8)
        case .imminentPill, .fullReplace:
            let label = meetingIndicatorLabel(for: alert)
            guard let prefix = pillAttachment(text: label, phase: alert.phase, font: font) else { return nil }
            let width = max(font.pointSize + 8, prefix.size().width + 6)
            return MenuBarMeetingIndicatorRender(prefix: prefix, hitWidth: width)
        }
    }
    #endif

    public static func meetingIndicatorLabel(for alert: MeetingAlertSnapshot) -> String {
        if alert.isLive {
            return "Now"
        }
        return "\(alert.minutesUntilStart)m"
    }

    public static func meetingCountdownText(for alert: MeetingAlertSnapshot) -> String {
        if alert.isLive {
            return "Live now"
        }
        return alert.minutesUntilStart == 1 ? "in 1 min" : "in \(alert.minutesUntilStart) min"
    }

    public static func meetingHoverTitle(for alert: MeetingAlertSnapshot) -> String {
        truncatedMeetingTitle(alert.meeting.title, maxLength: 30)
    }

    public static func meetingFullReplaceTitle(for alert: MeetingAlertSnapshot) -> String {
        if alert.isLive {
            return truncatedMeetingTitle(alert.meeting.title, maxLength: 26)
        }
        return "\(truncatedMeetingTitle(alert.meeting.title, maxLength: 20)) · \(meetingCountdownText(for: alert))"
    }

    public static func meetingTooltipLine(for alert: MeetingAlertSnapshot, settings: ClockSettingsStore) -> String {
        let startTime = meetingTimeText(for: alert.meeting, settings: settings)
        let status = alert.isLive ? "Live now" : meetingCountdownText(for: alert)
        return "Meeting: \(alert.meeting.title) • \(startTime) • \(status)"
    }

    public static func meetingTimeText(for meeting: MeetingSnapshot, settings: ClockSettingsStore) -> String {
        let formatter = formatter(for: meetingTimeZone(for: meeting, settings: settings), format: "h:mm a")
        return formatter.string(from: meeting.startDate)
    }

    public static func timeText(for date: Date, timeZoneID: String, settings: ClockSettingsStore) -> String {
        timeText(for: date, timeZoneID: timeZoneID, settings: settings, formatOverride: .appDefault)
    }

    public static func timeText(
        for date: Date,
        timeZoneID: String,
        settings: ClockSettingsStore,
        formatOverride: MenuBarClockFormatOverride
    ) -> String {
        let use24HourClock = formatOverride.uses24Hour(appDefault: settings.use24HourClock)
        let format = use24HourClock
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

        if settings.effectiveWeatherEnabled {
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

    private static func menuBarSegment(
        for date: Date,
        timeZoneID: String,
        label: String,
        settings: ClockSettingsStore,
        formatOverride: MenuBarClockFormatOverride = .appDefault
    ) -> String {
        let time = timeText(for: date, timeZoneID: timeZoneID, settings: settings, formatOverride: formatOverride)
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
                settings: settings,
                formatOverride: settings.effectiveClockFormatOverride(for: descriptor.slot)
            )
        }
    }

    #if os(macOS)
    public static func menuBarClockSegments(
        for date: Date,
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        primaryTextOverride: String? = nil,
        attributes: [NSAttributedString.Key: Any]? = nil,
        font: NSFont? = nil
    ) -> [MenuBarClockSegment] {
        let titleFont = font ?? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textAttributes = attributes ?? [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ]

        return visibleClockDescriptors(for: settings).compactMap { descriptor in
            guard let item = MenuBarLayoutItem(slot: descriptor.slot) else { return nil }
            let label = settings.displayLabel(for: descriptor.timeZoneID, customLabel: descriptor.customLabel)
            let formatOverride = settings.effectiveClockFormatOverride(for: descriptor.slot)
            let plainTitle = descriptor.slot == .primary && primaryTextOverride != nil
                ? primaryTextOverride!
                : menuBarSegment(
                    for: date,
                    timeZoneID: descriptor.timeZoneID,
                    label: label,
                    settings: settings,
                    formatOverride: formatOverride
                )
            let attributedTitle = NSMutableAttributedString()
            let weatherState = weatherStore.state(for: descriptor.slot)

            if let attachment = statusAttachment(
                for: date,
                timeZoneID: descriptor.timeZoneID,
                weatherState: weatherState,
                settings: settings,
                font: titleFont
            ) {
                attributedTitle.append(attachment)
                attributedTitle.append(NSAttributedString(string: " ", attributes: textAttributes))
            }

            attributedTitle.append(NSAttributedString(string: plainTitle, attributes: textAttributes))
            return MenuBarClockSegment(
                item: item,
                slot: descriptor.slot,
                attributedTitle: attributedTitle,
                plainTitle: plainTitle
            )
        }
    }

    public static func menuBarSeparator(
        settings: ClockSettingsStore,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        NSAttributedString(string: plainMenuBarSeparator(settings: settings), attributes: attributes)
    }
    #endif

    private static func plainMenuBarSeparator(settings: ClockSettingsStore) -> String {
        let padding = settings.effectiveMenuBarSpacing.separatorPadding
        return "\(padding)\(settings.effectiveMenuBarSeparatorStyle.symbol)\(padding)"
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
        var descriptorsByItem: [MenuBarLayoutItem: (slot: ClockSlot, timeZoneID: String, customLabel: String)] = [:]

        if settings.showPrimaryClock {
            descriptorsByItem[.primaryClock] = (slot: .primary, timeZoneID: settings.primaryTimeZoneID, customLabel: settings.primaryCustomLabel)
        }

        if settings.showSecondaryClock {
            descriptorsByItem[.secondaryClock] = (slot: .secondary, timeZoneID: settings.secondaryTimeZoneID, customLabel: settings.secondaryCustomLabel)
        }

        return settings.effectiveMenuBarLayoutItems.compactMap { descriptorsByItem[$0] }
    }

    #if os(macOS)
    private static func statusAttachment(
        for date: Date,
        timeZoneID: String,
        weatherState: WeatherState,
        settings: ClockSettingsStore,
        font: NSFont
    ) -> NSAttributedString? {
        let shouldShowWeatherIcon = settings.effectiveWeatherEnabled && settings.showWeatherInMenuBar
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
    #endif

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
        formatter(for: TimeZone(identifier: timeZoneID) ?? .autoupdatingCurrent, format: format)
    }

    private static func formatter(for timeZone: TimeZone, format: String) -> DateFormatter {
        let timeZoneID = timeZone.identifier
        let cacheKey = "\(timeZoneID)|\(format)"
        if let formatter = formatterCache[cacheKey] {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatterCache[cacheKey] = formatter
        return formatter
    }

    private static func meetingTimeZone(for meeting: MeetingSnapshot, settings: ClockSettingsStore) -> TimeZone {
        switch settings.meetingTimeZonePreference {
        case .system:
            return .autoupdatingCurrent
        case .event:
            return meeting.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        case .primary:
            return TimeZone(identifier: settings.primaryTimeZoneID) ?? .autoupdatingCurrent
        case .secondary:
            return TimeZone(identifier: settings.secondaryTimeZoneID) ?? .autoupdatingCurrent
        }
    }

    private static func truncatedMeetingTitle(_ title: String, maxLength: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: max(1, maxLength - 1))
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    #if os(macOS)
    private static func tinyBadgeAttachment(for alert: MeetingAlertSnapshot, font: NSFont) -> NSAttributedString? {
        let size = NSSize(width: font.pointSize - 1, height: font.pointSize - 1)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
        indicatorFillColor(for: alert.phase).setFill()
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = false

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -1.5, width: size.width, height: size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func pillAttachment(text: String, phase: MeetingAlertPhase, font: NSFont) -> NSAttributedString? {
        let textFont = NSFont.systemFont(ofSize: max(9, font.pointSize - 1), weight: .semibold)
        let horizontalPadding: CGFloat = 9
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: textAttributes)
        let imageSize = NSSize(width: ceil(textSize.width + horizontalPadding * 2), height: 18)
        let image = NSImage(size: imageSize)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: imageSize)
        let pillRect = rect.insetBy(dx: 0.5, dy: 0.5)
        indicatorFillColor(for: phase).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2).fill()

        let textRect = NSRect(
            x: round((imageSize.width - textSize.width) / 2),
            y: round((imageSize.height - textSize.height) / 2) - 1,
            width: ceil(textSize.width),
            height: ceil(textSize.height) + 2
        )
        (text as NSString).draw(in: textRect, withAttributes: textAttributes)

        image.unlockFocus()
        image.isTemplate = false

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -5, width: imageSize.width, height: imageSize.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func indicatorFillColor(for phase: MeetingAlertPhase) -> NSColor {
        switch phase {
        case .early:
            return NSColor(calibratedRed: 0.90, green: 0.56, blue: 0.16, alpha: 1)
        case .critical:
            return NSColor(calibratedRed: 0.85, green: 0.21, blue: 0.24, alpha: 1)
        }
    }
    #endif
}

extension MenuBarLayoutItem {
    public init?(slot: ClockSlot) {
        switch slot {
        case .primary:
            self = .primaryClock
        case .secondary:
            self = .secondaryClock
        }
    }
}

public enum TimeZoneCatalog {
    public static let defaultPrimaryID = TimeZone.current.identifier

    public static func defaultSecondaryID(relativeTo primaryID: String) -> String {
        let candidates = ["Etc/UTC", "Europe/London", "America/New_York"]
        return candidates.first(where: { $0 != primaryID && option(for: $0) != nil }) ?? "Europe/London"
    }

    nonisolated(unsafe) static let options: [TimeZoneOption] = {
        let enLocale = Locale(identifier: "en_US_POSIX")
        // Strip common suffixes from Apple's generic timezone names to extract country/region
        let suffixesToStrip = [" Standard Time", " Daylight Time", " Summer Time", " Time"]
        return TimeZone.knownTimeZoneIdentifiers
            .compactMap { identifier -> TimeZoneOption? in
                guard let timeZone = TimeZone(identifier: identifier) else { return nil }
                let cityName = identifier.split(separator: "/").last?
                    .replacingOccurrences(of: "_", with: " ") ?? identifier
                let shortLabel = shortLabel(for: identifier, fallback: cityName)
                let offset = offsetText(for: timeZone)
                let displayName = "\(cityName) (\(offset))"

                // Use Apple's own localized name to derive country context — no static data needed
                var countryHint = timeZone.localizedName(for: .generic, locale: enLocale) ?? ""
                for suffix in suffixesToStrip {
                    if countryHint.hasSuffix(suffix) {
                        countryHint = String(countryHint.dropLast(suffix.count))
                        break
                    }
                }
                let shortGeneric = timeZone.localizedName(for: .shortGeneric, locale: enLocale) ?? ""

                return TimeZoneOption(
                    id: identifier,
                    shortLabel: shortLabel,
                    cityName: cityName,
                    displayName: displayName,
                    searchableText: "\(cityName) \(identifier) \(shortLabel) \(offset) \(countryHint) \(shortGeneric)"
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

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
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
