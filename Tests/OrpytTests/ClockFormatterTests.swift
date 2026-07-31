import Testing
import Foundation
@testable import OrpytCore

@Suite("ClockFormatter", .serialized)
@MainActor
struct ClockFormatterTests {

    // Fixed reference date: 2024-06-15 14:30:45 UTC (Saturday)
    private static let referenceDate: Date = {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 6; comps.day = 15
        comps.hour = 14; comps.minute = 30; comps.second = 45
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }()

    private let date = ClockFormatterTests.referenceDate
    private let gmtID = "GMT"
    private let nyID = "America/New_York"

    // MARK: timeText

    @Test("timeText 24h no seconds returns HH:mm")
    func timeText24hNoSeconds() {
        let s = makeSettings(use24Hour: true, showSeconds: false)
        #expect(ClockFormatter.timeText(for: date, timeZoneID: gmtID, settings: s) == "14:30")
    }

    @Test("timeText 24h with seconds returns HH:mm:ss")
    func timeText24hWithSeconds() {
        let s = makeSettings(use24Hour: true, showSeconds: true)
        #expect(ClockFormatter.timeText(for: date, timeZoneID: gmtID, settings: s) == "14:30:45")
    }

    @Test("timeText 12h no seconds is in 12-hour format")
    func timeText12hNoSeconds() {
        let s = makeSettings(use24Hour: false, showSeconds: false)
        let result = ClockFormatter.timeText(for: date, timeZoneID: gmtID, settings: s).lowercased()
        #expect(result.contains("pm") || result.contains("am"))
        #expect(result.contains("2:30"))
    }

    @Test("timeText 12h with seconds includes seconds and am/pm")
    func timeText12hWithSeconds() {
        let s = makeSettings(use24Hour: false, showSeconds: true)
        let result = ClockFormatter.timeText(for: date, timeZoneID: gmtID, settings: s).lowercased()
        #expect(result.contains("45"))
        #expect(result.contains("pm") || result.contains("am"))
    }

    @Test("timeText respects time zone — NYC is 10:30 when GMT is 14:30 (EDT = UTC-4)")
    func timeTextRespectsTimeZone() {
        let s = makeSettings(use24Hour: true, showSeconds: false)
        let result = ClockFormatter.timeText(for: date, timeZoneID: nyID, settings: s)
        #expect(result == "10:30")
    }

    // MARK: dateText

    @Test("dateText empty when weekday and date both disabled")
    func dateTextEmpty() {
        let s = makeSettings(showWeekday: false, showDate: false)
        #expect(ClockFormatter.dateText(for: date, timeZoneID: gmtID, settings: s).isEmpty)
    }

    @Test("dateText contains day-of-month when showDate enabled")
    func dateTextContainsDay() {
        let s = makeSettings(showWeekday: false, showDate: true)
        let result = ClockFormatter.dateText(for: date, timeZoneID: gmtID, settings: s)
        #expect(result.contains("15"))
        #expect(result.contains("Jun"))
    }

    @Test("dateText contains weekday abbreviation when showWeekday enabled")
    func dateTextContainsWeekday() {
        let s = makeSettings(showWeekday: true, showDate: false)
        let result = ClockFormatter.dateText(for: date, timeZoneID: gmtID, settings: s)
        #expect(result.contains("Sat"))
    }

    @Test("dateText contains both weekday and date when both enabled")
    func dateTextBoth() {
        let s = makeSettings(showWeekday: true, showDate: true)
        let result = ClockFormatter.dateText(for: date, timeZoneID: gmtID, settings: s)
        #expect(result.contains("Sat"))
        #expect(result.contains("15"))
    }

    // MARK: metaText

    @Test("metaText empty when both abbreviation and offset disabled")
    func metaTextEmpty() {
        let s = makeSettings(showAbbreviation: false, showGMTOffset: false)
        #expect(ClockFormatter.metaText(for: date, timeZoneID: gmtID, settings: s).isEmpty)
    }

    @Test("metaText contains timezone abbreviation for GMT")
    func metaTextContainsAbbreviation() {
        let s = makeSettings(showAbbreviation: true, showGMTOffset: false)
        let result = ClockFormatter.metaText(for: date, timeZoneID: gmtID, settings: s)
        #expect(result.contains("UTC") || result.contains("GMT"))
    }

    @Test("metaText contains GMT offset string")
    func metaTextContainsOffset() {
        let s = makeSettings(showAbbreviation: false, showGMTOffset: true)
        let result = ClockFormatter.metaText(for: date, timeZoneID: gmtID, settings: s)
        #expect(result.contains("GMT"))
        #expect(result.contains("00:00"))
    }

    @Test("metaText GMT offset for NYC shows -04:00 in summer (EDT)")
    func metaTextNYCOffset() {
        let s = makeSettings(showAbbreviation: false, showGMTOffset: true)
        let result = ClockFormatter.metaText(for: date, timeZoneID: nyID, settings: s)
        #expect(result.contains("GMT-04:00"))
    }

    @Test("metaText both abbreviation and offset separated by double space")
    func metaTextBothFields() {
        let s = makeSettings(showAbbreviation: true, showGMTOffset: true)
        let result = ClockFormatter.metaText(for: date, timeZoneID: gmtID, settings: s)
        #expect(result.contains("  ")) // double-space separator
    }

    // MARK: menuBarTitle

    @Test("menuBarTitle non-empty with one clock")
    func menuBarTitleNonEmpty() {
        let s = makeSettings(showPrimary: true, showSecondary: false)
        let result = ClockFormatter.menuBarTitle(for: date, settings: s)
        #expect(!result.isEmpty)
        #expect(result != "Orpyt")
    }

    @Test("menuBarTitle contains pipe separator for two visible clocks")
    func menuBarTitleTwoClocks() {
        let s = makeSettings(showPrimary: true, showSecondary: true)
        let result = ClockFormatter.menuBarTitle(for: date, settings: s)
        #expect(result.contains(" | "))
    }

    @Test("menuBarTitle shows zone label when showZoneLabelInMenuBar is true")
    func menuBarTitleWithLabel() {
        let s = makeSettings(showPrimary: true, showSecondary: false, showZoneLabel: true)
        s.primaryCustomLabel = "UTC"
        let result = ClockFormatter.menuBarTitle(for: date, settings: s)
        #expect(result.contains("UTC"))
    }

    @Test("menuBarTitle omits zone label when showZoneLabelInMenuBar is false")
    func menuBarTitleWithoutLabel() {
        let s = makeSettings(showPrimary: true, showSecondary: false, showZoneLabel: false)
        s.primaryCustomLabel = "UNIQUELABEL"
        let result = ClockFormatter.menuBarTitle(for: date, settings: s)
        #expect(!result.contains("UNIQUELABEL"))
    }

    @Test("menuBarTitle follows custom clock order")
    func menuBarTitleCustomOrder() {
        let s = makeSettings(use24Hour: true, showPrimary: true, showSecondary: true)
        s.primaryCustomLabel = "GMT"
        s.secondaryCustomLabel = "NYC"
        s.setMenuBarLayoutItems([.secondaryClock, .primaryClock, .meetingIndicator])
        let result = ClockFormatter.menuBarTitle(for: date, settings: s)
        #expect(result.hasPrefix("NYC 10:30"))
        #expect(result.contains("|  GMT 14:30"))
    }

    @Test("menuBarTitle respects separator and spacing")
    func menuBarTitleSeparatorAndSpacing() {
        let s = makeSettings(use24Hour: true, showPrimary: true, showSecondary: true)
        s.primaryCustomLabel = "GMT"
        s.secondaryCustomLabel = "NYC"
        s.menuBarSeparatorStyle = .dot
        s.menuBarSpacing = .compact
        let result = ClockFormatter.menuBarTitle(for: date, settings: s)
        #expect(result.contains("GMT 14:30 • NYC 10:30"))
    }

    @Test("menuBarTitle supports per-clock format override")
    func menuBarTitleClockFormatOverride() {
        let s = makeSettings(use24Hour: true, showPrimary: true, showSecondary: true)
        s.primaryCustomLabel = "GMT"
        s.secondaryCustomLabel = "NYC"
        s.secondaryClockFormatOverride = .twelveHour
        let result = ClockFormatter.menuBarTitle(for: date, settings: s).lowercased()
        #expect(result.contains("gmt 14:30"))
        #expect(result.contains("nyc 10:30 am"))
    }

    // MARK: detailLine

    @Test("detailLine contains label and time")
    func detailLineContainsLabelAndTime() {
        let s = makeSettings(use24Hour: true, showSeconds: false)
        let line = ClockFormatter.detailLine(
            for: date,
            timeZoneID: gmtID,
            label: "GMT",
            settings: s,
            weatherState: .idle
        )
        #expect(line.contains("GMT:"))
        #expect(line.contains("14:30"))
    }

    @Test("detailLine does not include weather when enableWeather is false")
    func detailLineNoWeatherWhenDisabled() {
        let s = makeSettings()
        s.enableWeather = false
        let snapshot = WeatherSnapshot(
            symbolName: "sun.max.fill",
            temperatureText: "20°C",
            conditionText: "Sunny",
            feelsLikeText: "Feels 18°C",
            resolvedLocationName: "London"
        )
        let line = ClockFormatter.detailLine(
            for: date,
            timeZoneID: gmtID,
            label: "GMT",
            settings: s,
            weatherState: .loaded(snapshot)
        )
        #expect(!line.contains("Sunny"))
        #expect(!line.contains("20°C"))
    }

    @Test("detailLine includes weather when enableWeather is true and state is loaded")
    func detailLineIncludesWeatherWhenEnabled() {
        let s = makeSettings()
        s.enableWeather = true
        let snapshot = WeatherSnapshot(
            symbolName: "sun.max.fill",
            temperatureText: "20°C",
            conditionText: "Sunny",
            feelsLikeText: "Feels 18°C",
            resolvedLocationName: "London"
        )
        let line = ClockFormatter.detailLine(
            for: date,
            timeZoneID: gmtID,
            label: "GMT",
            settings: s,
            weatherState: .loaded(snapshot)
        )
        #expect(line.contains("Sunny"))
        #expect(line.contains("20°C"))
    }

    // MARK: Meeting alerts

    @Test("activeMeetingAlert returns nil when the next meeting is outside the warning window")
    func activeMeetingAlertReturnsNilOutsideThreshold() {
        let settings = makeSettings()
        settings.showCalendarEvents = true
        settings.meetingIndicatorStyle = .imminentPill
        settings.meetingWarningMode = .preset
        settings.meetingWarningPreset = .tenAndFive

        let meeting = MeetingSnapshot(
            id: "meeting-outside-window",
            title: "Design Review",
            startDate: date.addingTimeInterval(16 * 60),
            endDate: date.addingTimeInterval(46 * 60),
            calendarName: "Work",
            joinURL: nil
        )
        let snapshot = CalendarAgendaSnapshot(nextMeeting: meeting, todayAgenda: [meeting])

        let alert = ClockFormatter.activeMeetingAlert(
            for: date,
            settings: settings,
            calendarState: .loaded(snapshot)
        )

        #expect(alert == nil)
    }

    @Test("activeMeetingAlert escalates from early to critical as the meeting gets closer")
    func activeMeetingAlertEscalates() {
        let settings = makeSettings()
        settings.showCalendarEvents = true
        settings.meetingIndicatorStyle = .imminentPill
        settings.meetingWarningMode = .preset
        settings.meetingWarningPreset = .tenAndFive

        let meeting = MeetingSnapshot(
            id: "meeting-escalates",
            title: "Standup",
            startDate: date.addingTimeInterval(8 * 60),
            endDate: date.addingTimeInterval(38 * 60),
            calendarName: "Work",
            joinURL: URL(string: "https://meet.example.com/standup")
        )
        let snapshot = CalendarAgendaSnapshot(nextMeeting: meeting, todayAgenda: [meeting])

        let earlyAlert = ClockFormatter.activeMeetingAlert(
            for: date,
            settings: settings,
            calendarState: .loaded(snapshot)
        )
        #expect(earlyAlert?.phase == .early)
        #expect(earlyAlert?.minutesUntilStart == 8)
        #expect(earlyAlert?.isLive == false)

        let criticalDate = date.addingTimeInterval(4 * 60)
        let criticalAlert = ClockFormatter.activeMeetingAlert(
            for: criticalDate,
            settings: settings,
            calendarState: .loaded(snapshot)
        )
        #expect(criticalAlert?.phase == .critical)
        #expect(criticalAlert?.minutesUntilStart == 4)
        #expect(criticalAlert?.isLive == false)
    }

    @Test("activeMeetingAlert remains critical while a meeting is live")
    func activeMeetingAlertStaysCriticalWhenLive() {
        let settings = makeSettings()
        settings.showCalendarEvents = true
        settings.meetingIndicatorStyle = .fullReplace

        let meeting = MeetingSnapshot(
            id: "meeting-live",
            title: "Ops Sync",
            startDate: date.addingTimeInterval(-2 * 60),
            endDate: date.addingTimeInterval(18 * 60),
            calendarName: "Ops",
            joinURL: nil
        )
        let snapshot = CalendarAgendaSnapshot(nextMeeting: meeting, todayAgenda: [meeting])

        let alert = ClockFormatter.activeMeetingAlert(
            for: date,
            settings: settings,
            calendarState: .loaded(snapshot)
        )

        #expect(alert?.phase == .critical)
        #expect(alert?.minutesUntilStart == 0)
        #expect(alert?.isLive == true)
    }

    @Test("meeting time text can use calendar event timezone independent of primary clock")
    func meetingTimeTextUsesEventTimeZoneWhenSelected() {
        let settings = makeSettings(use24Hour: false)
        settings.primaryTimeZoneID = "America/Chicago"
        settings.meetingTimeZonePreference = .event

        let meeting = MeetingSnapshot(
            id: "meeting-event-zone",
            title: "Standup",
            startDate: date,
            endDate: date.addingTimeInterval(30 * 60),
            calendarName: "Work",
            timeZoneID: "Europe/London",
            joinURL: nil
        )

        let result = ClockFormatter.meetingTimeText(for: meeting, settings: settings).lowercased()

        #expect(result.contains("3:30"))
        #expect(result.contains("pm"))
    }

    @Test("meeting time text only uses primary clock when explicitly selected")
    func meetingTimeTextUsesPrimaryOnlyWhenSelected() {
        let settings = makeSettings(use24Hour: false)
        settings.primaryTimeZoneID = "America/Chicago"
        settings.meetingTimeZonePreference = .primary

        let meeting = MeetingSnapshot(
            id: "meeting-primary-zone",
            title: "Standup",
            startDate: date,
            endDate: date.addingTimeInterval(30 * 60),
            calendarName: "Work",
            timeZoneID: "Europe/London",
            joinURL: nil
        )

        let result = ClockFormatter.meetingTimeText(for: meeting, settings: settings).lowercased()

        #expect(result.contains("9:30"))
        #expect(result.contains("am"))
    }

    // MARK: Helpers

    private func makeSettings(
        use24Hour: Bool = true,
        showSeconds: Bool = false,
        showWeekday: Bool = false,
        showDate: Bool = false,
        showAbbreviation: Bool = false,
        showGMTOffset: Bool = false,
        showPrimary: Bool = true,
        showSecondary: Bool = false,
        showZoneLabel: Bool = true
    ) -> ClockSettingsStore {
        SubscriptionStore.shared.applyTestingEntitlementState(.active)

        let s = ClockSettingsStore.shared
        s.use24HourClock = use24Hour
        s.showSeconds = showSeconds
        s.showWeekday = showWeekday
        s.showDate = showDate
        s.showTimeZoneAbbreviation = showAbbreviation
        s.showGMTOffset = showGMTOffset
        s.showPrimaryClock = showPrimary
        s.showSecondaryClock = showSecondary
        s.primaryTimeZoneID = gmtID
        s.secondaryTimeZoneID = nyID
        s.primaryCustomLabel = ""
        s.secondaryCustomLabel = ""
        s.showZoneLabelInMenuBar = showZoneLabel
        s.setMenuBarLayoutItems(MenuBarLayoutItem.defaultOrder)
        s.primaryClockFormatOverride = .appDefault
        s.secondaryClockFormatOverride = .appDefault
        s.menuBarSeparatorStyle = .pipe
        s.menuBarSpacing = .comfortable
        s.refreshIntervalPreference = .automatic
        s.meetingTimeZonePreference = .system
        s.enableWeather = false
        return s
    }
}
