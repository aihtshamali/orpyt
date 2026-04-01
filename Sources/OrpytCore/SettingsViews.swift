import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

public struct SettingsView: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var weatherStore: WeatherStore
    @ObservedObject public var calendarStore: CalendarStore
    @State private var primarySearchText = ""
    @State private var secondarySearchText = ""
    @State private var selectedPane: SettingsPane? = .overview

    public init(settings: ClockSettingsStore, weatherStore: WeatherStore, calendarStore: CalendarStore) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.rawValue, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .listStyle(.sidebar)
        } detail: {
            detailView(for: selectedPane ?? .overview)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .overview:
            SettingsOverviewPane(settings: settings, weatherStore: weatherStore, calendarStore: calendarStore)
                .navigationTitle("Overview")
        case .timeZones:
            TimeZonesPane(
                settings: settings,
                primarySearchText: $primarySearchText,
                secondarySearchText: $secondarySearchText
            )
            .navigationTitle("Time Zones")
        case .menuBar:
            MenuBarPane(settings: settings)
                .navigationTitle("Menu Bar")
        case .details:
            DetailsPane(settings: settings)
                .navigationTitle("Clock Details")
        case .calendar:
            CalendarPane(settings: settings, calendarStore: calendarStore)
                .navigationTitle("Calendar")
        case .weather:
            WeatherPane(settings: settings)
                .navigationTitle("Weather")
        case .appearance:
            AppearancePane(settings: settings)
                .navigationTitle("Appearance")
        }
    }
}

public enum SettingsPane: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case timeZones = "Time Zones"
    case menuBar = "Menu Bar"
    case details = "Clock Details"
    case calendar = "Calendar"
    case weather = "Weather"
    case appearance = "Appearance"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .timeZones: return "globe.americas"
        case .menuBar: return "menubar.rectangle"
        case .details: return "list.bullet.rectangle.portrait"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        case .appearance: return "square.3.layers.3d.top.filled"
        }
    }

    public var subtitle: String {
        switch self {
        case .overview: return "Live preview and app summary"
        case .timeZones: return "Cities, labels, and ordering"
        case .menuBar: return "Compact top bar behavior"
        case .details: return "Metadata and badges"
        case .calendar: return "Read-only next meeting context"
        case .weather: return "Weather synced with each clock"
        case .appearance: return "Popover mood and polish"
        }
    }
}


public struct SettingsOverviewPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var weatherStore: WeatherStore
    @ObservedObject public var calendarStore: CalendarStore

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1.0)) { context in
                overviewContent(now: context.date)
                    .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func overviewContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            OverviewHeroHeader(settings: settings)

            if settings.isMenuBarOverflowing {
                MenuBarOverflowBanner()
            }

            OverviewMenuBarPreview(settings: settings, now: now)

            HStack(alignment: .top, spacing: 18) {
                OverviewWeatherCard(
                    title: "Primary",
                    timeZoneID: settings.primaryTimeZoneID,
                    label: settings.displayLabel(
                        for: settings.primaryTimeZoneID,
                        customLabel: settings.primaryCustomLabel
                    ),
                    isVisible: settings.showPrimaryClock,
                    now: now,
                    settings: settings,
                    weatherState: weatherStore.state(for: .primary)
                )

                OverviewWeatherCard(
                    title: "Secondary",
                    timeZoneID: settings.secondaryTimeZoneID,
                    label: settings.displayLabel(
                        for: settings.secondaryTimeZoneID,
                        customLabel: settings.secondaryCustomLabel
                    ),
                    isVisible: settings.showSecondaryClock,
                    now: now,
                    settings: settings,
                    weatherState: weatherStore.state(for: .secondary)
                )
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                ForEach(metrics(now: now)) { metric in
                    OverviewMetricTile(metric: metric)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metrics(now: Date) -> [OverviewMetricDescriptor] {
        let liveWeatherCount = [weatherStore.state(for: .primary), weatherStore.state(for: .secondary)]
            .reduce(0) { partialResult, state in
                if case .loaded = state {
                    return partialResult + 1
                }
                return partialResult
            }
        let visibleClockCount = [settings.showPrimaryClock, settings.showSecondaryClock]
            .reduce(0) { $0 + ($1 ? 1 : 0) }

        return [
            OverviewMetricDescriptor(
                icon: "clock.arrow.circlepath",
                title: "Clock Mode",
                value: settings.use24HourClock ? "24h" : "12h",
                caption: settings.showSeconds ? "Seconds live" : "Minute precision"
            ),
            OverviewMetricDescriptor(
                icon: settings.enableWeather ? "cloud.sun.fill" : "cloud.slash",
                title: "Weather",
                value: settings.enableWeather
                    ? (liveWeatherCount > 0 ? "\(liveWeatherCount)/2 Live" : "Loading")
                    : "Off",
                caption: settings.enableWeather ? "Graceful fallback enabled" : "Chronos-only mode"
            ),
            OverviewMetricDescriptor(
                icon: "rectangle.split.2x1",
                title: "Visible Clocks",
                value: "\(visibleClockCount)",
                caption: visibleClockCount == 2 ? "Both cities pinned" : "Single clock focus"
            ),
            OverviewMetricDescriptor(
                icon: "calendar",
                title: "Calendar",
                value: settings.showCalendarEvents ? calendarMetricTitle : "Off",
                caption: settings.showCalendarEvents ? calendarMetricCaption : "Read-only meeting context"
            ),
        ]
    }

    private var calendarMetricTitle: String {
        switch calendarStore.state {
        case .disabled:
            // Toggle is on but store hasn't initialised yet — treat as loading
            return settings.showCalendarEvents ? "Starting" : "Off"
        case .needsPermission:
            return "Needs Access"
        case .loading:
            return "Loading"
        case let .loaded(snapshot):
            return snapshot == nil ? "No Events" : "Live"
        case .failed:
            return "Unavailable"
        }
    }

    private var calendarMetricCaption: String {
        switch calendarStore.state {
        case .disabled:
            return settings.showCalendarEvents ? "Initialising calendar access" : "Read-only meeting context"
        case .needsPermission:
            return "Permission requested only on enable"
        case .loading:
            return "Checking the next event"
        case let .loaded(snapshot):
            return snapshot?.title ?? "Nothing in the next 24 hours"
        case let .failed(message):
            return message
        }
    }
}

public struct OverviewHeroHeader: View {
    @ObservedObject public var settings: ClockSettingsStore

    private var systemZoneTitle: String {
        TimeZone.current.identifier.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? "Local"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                SettingsAppIconView(size: 56)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Orpyt")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("A live overview for your active clocks.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    OverviewInlineTag(title: "Appearance", value: settings.appearanceMode.title)
                    Text("System time zone: \(systemZoneTitle)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                OverviewInlineTag(title: "Mode", value: settings.use24HourClock ? "24h" : "12h")
                OverviewInlineTag(title: "Weather", value: settings.enableWeather ? "On" : "Off")
                OverviewInlineTag(title: "System", value: systemZoneTitle)
            }
        }
    }
}

public struct MenuBarOverflowBanner: View {
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Menu bar is full")
                    .font(.system(size: 13, weight: .semibold))
                Text("Orpyt is hidden because your menu bar has no space. Use **Bartender** or **Ice** (free) to manage menu bar icons and reveal Orpyt.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Get Ice") {
                NSWorkspace.shared.open(URL(string: "https://icemenubar.app")!)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

public struct OverviewMenuBarPreview: View {
    @ObservedObject public var settings: ClockSettingsStore
    public let now: Date

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Live Menu Bar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(ClockFormatter.menuBarTitle(for: now, settings: settings))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 16)

                OverviewInlineTag(
                    title: "Icons",
                    value: settings.showWeatherInMenuBar ? "Weather" : settings.showStatusIcon ? "Ambient" : "Off"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Color.accentColor.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
        )
    }
}

public struct OverviewInlineTag: View {
    public let title: String
    public let value: String

    public var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

public struct OverviewMetricDescriptor: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let value: String
    public let caption: String
}

public struct OverviewMetricTile: View {
    public let metric: OverviewMetricDescriptor

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: metric.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(metric.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(metric.value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(metric.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Color.accentColor.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 0.8)
        )
    }
}

public struct OverviewWeatherCard: View {
    public let title: String
    public let timeZoneID: String
    public let label: String
    public let isVisible: Bool
    public let now: Date
    @ObservedObject public var settings: ClockSettingsStore
    public let weatherState: WeatherState

    private var theme: OverviewCardTheme {
        OverviewCardTheme(date: now, timeZoneID: timeZoneID, weatherState: weatherState)
    }

    private var cityName: String {
        TimeZoneCatalog.option(for: timeZoneID)?.cityName ?? timeZoneID
    }

    private var cardIconName: String {
        ClockFormatter.cardIconName(for: now, timeZoneID: timeZoneID, weatherState: weatherState)
    }

    private var weatherSummary: String {
        switch weatherState {
        case let .loaded(snapshot):
            return "\(snapshot.conditionText) • \(snapshot.temperatureText)"
        case .loading:
            return "Refreshing live conditions"
        case let .failed(message):
            return settings.enableWeather ? message : ambientSummary
        case .idle:
            return ambientSummary
        }
    }

    private var ambientSummary: String {
        let hour = Calendar.current.dateComponents(in: TimeZone(identifier: timeZoneID) ?? .current, from: now).hour ?? 12
        switch hour {
        case 6..<11:
            return "Morning light"
        case 11..<17:
            return "Daylight active"
        case 17..<21:
            return "Evening transition"
        default:
            return "Night cycle"
        }
    }

    private var footerItems: [(String, String)] {
        let offset = OverviewCardTheme.gmtOffsetText(for: timeZoneID, date: now)
        let status = isVisible ? "Active" : "Hidden"
        return [
            ("globe", offset),
            (isVisible ? "eye" : "eye.slash", status),
        ]
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(theme.background)

            OverviewAnimatedSky(theme: theme)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(theme.stroke, lineWidth: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cityName)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        Image(systemName: cardIconName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.accent)

                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                Spacer(minLength: 34)

                Text(ClockFormatter.timeText(for: now, timeZoneID: timeZoneID, settings: settings))
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text(weatherSummary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 14)

                Spacer()

                Rectangle()
                    .fill(theme.stroke.opacity(0.7))
                    .frame(height: 1)
                    .padding(.bottom, 12)

                HStack(spacing: 14) {
                    ForEach(Array(footerItems.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Image(systemName: item.0)
                                .font(.system(size: 10, weight: .semibold))
                            Text(item.1)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 348, alignment: .topLeading)
        .shadow(color: theme.shadow, radius: 24, x: 0, y: 14)
        .opacity(isVisible ? 1 : 0.82)
    }
}

@MainActor
public struct OverviewCardTheme {
    public enum Kind {
        case daylight
        case cloud
        case rain
        case snow
        case night
        case storm
    }

    public let kind: Kind
    public let background: LinearGradient
    public let primaryText: Color
    public let secondaryText: Color
    public let accent: Color
    public let stroke: Color
    public let shadow: Color

    public init(date: Date, timeZoneID: String, weatherState: WeatherState) {
        let kind = Self.kind(for: date, timeZoneID: timeZoneID, weatherState: weatherState)
        self.kind = kind

        switch kind {
        case .daylight:
            background = LinearGradient(
                colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.86, green: 0.91, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = Color(red: 0.10, green: 0.16, blue: 0.24)
            secondaryText = Color(red: 0.25, green: 0.35, blue: 0.48)
            accent = Color(red: 0.18, green: 0.50, blue: 1.0)
            stroke = Color.white.opacity(0.65)
            shadow = Color.blue.opacity(0.10)
        case .cloud:
            background = LinearGradient(
                colors: [Color(red: 0.92, green: 0.95, blue: 0.99), Color(red: 0.82, green: 0.87, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = Color(red: 0.12, green: 0.16, blue: 0.22)
            secondaryText = Color(red: 0.32, green: 0.38, blue: 0.48)
            accent = Color(red: 0.32, green: 0.47, blue: 0.70)
            stroke = Color.white.opacity(0.60)
            shadow = Color.black.opacity(0.08)
        case .rain:
            background = LinearGradient(
                colors: [Color(red: 0.28, green: 0.32, blue: 0.40), Color(red: 0.18, green: 0.21, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = .white
            secondaryText = Color.white.opacity(0.78)
            accent = Color(red: 0.69, green: 0.84, blue: 1.0)
            stroke = Color.white.opacity(0.12)
            shadow = Color.black.opacity(0.18)
        case .snow:
            background = LinearGradient(
                colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.88, green: 0.92, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = Color(red: 0.12, green: 0.18, blue: 0.28)
            secondaryText = Color(red: 0.38, green: 0.46, blue: 0.58)
            accent = Color(red: 0.24, green: 0.50, blue: 1.0)
            stroke = Color.white.opacity(0.72)
            shadow = Color.blue.opacity(0.10)
        case .night:
            background = LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.15), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = .white
            secondaryText = Color.white.opacity(0.74)
            accent = Color(red: 0.64, green: 0.67, blue: 1.0)
            stroke = Color.white.opacity(0.10)
            shadow = Color.black.opacity(0.25)
        case .storm:
            background = LinearGradient(
                colors: [Color(red: 0.15, green: 0.18, blue: 0.29), Color(red: 0.08, green: 0.08, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            primaryText = .white
            secondaryText = Color.white.opacity(0.78)
            accent = Color(red: 0.68, green: 0.79, blue: 1.0)
            stroke = Color.white.opacity(0.10)
            shadow = Color.black.opacity(0.24)
        }
    }

    private static func kind(for date: Date, timeZoneID: String, weatherState: WeatherState) -> Kind {
        let descriptor: String

        switch weatherState {
        case let .loaded(snapshot):
            descriptor = "\(snapshot.symbolName) \(snapshot.conditionText)".lowercased()
        default:
            descriptor = ClockFormatter.cardIconName(for: date, timeZoneID: timeZoneID, weatherState: weatherState).lowercased()
        }

        if descriptor.contains("bolt") || descriptor.contains("thunder") {
            return .storm
        }
        if descriptor.contains("snow") {
            return .snow
        }
        if descriptor.contains("rain") || descriptor.contains("drizzle") {
            return .rain
        }
        if descriptor.contains("moon") || descriptor.contains("night") || descriptor.contains("stars") {
            return .night
        }
        if descriptor.contains("cloud") || descriptor.contains("fog") || descriptor.contains("overcast") {
            return .cloud
        }
        return .daylight
    }

    public static func gmtOffsetText(for timeZoneID: String, date: Date) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return "GMT"
        }

        let seconds = timeZone.secondsFromGMT(for: date)
        let hours = seconds / 3600
        let minutes = abs((seconds / 60) % 60)
        return String(format: "GMT%+.2d:%02d", hours, minutes)
    }
}

public struct OverviewAnimatedSky: View {
    public let theme: OverviewCardTheme

    public var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 6.0)) { context in
            GeometryReader { geometry in
                let phase = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    driftingOrbs(size: geometry.size, phase: phase)
                    animatedLayer(size: geometry.size, phase: phase)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
    }

    private func driftingOrbs(size: CGSize, phase: Double) -> some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(theme.kind == .night ? 0.10 : 0.12))
                .frame(width: size.width * 0.60, height: size.width * 0.60)
                .blur(radius: 10)
                .offset(
                    x: CGFloat(cos(phase * 0.3) * 18),
                    y: CGFloat(sin(phase * 0.25) * 16) - 52
                )

            Circle()
                .fill(Color.white.opacity(theme.kind == .night ? 0.04 : 0.10))
                .frame(width: size.width * 0.36, height: size.width * 0.36)
                .blur(radius: 8)
                .offset(
                    x: size.width * 0.22 + CGFloat(sin(phase * 0.34) * 14),
                    y: -size.height * 0.20 + CGFloat(cos(phase * 0.28) * 10)
                )
        }
    }

    @ViewBuilder
    private func animatedLayer(size: CGSize, phase: Double) -> some View {
        switch theme.kind {
        case .daylight:
            sunlightLayer(size: size, phase: phase)
        case .cloud:
            cloudLayer(size: size, phase: phase)
        case .rain:
            ZStack {
                cloudLayer(size: size, phase: phase)
                rainLayer(size: size, phase: phase, intensity: 10)
            }
        case .snow:
            ZStack {
                cloudLayer(size: size, phase: phase)
                snowLayer(size: size, phase: phase)
            }
        case .night:
            starsLayer(size: size, phase: phase)
        case .storm:
            ZStack {
                cloudLayer(size: size, phase: phase)
                rainLayer(size: size, phase: phase, intensity: 13)
                stormPulse(size: size, phase: phase)
            }
        }
    }

    private func sunlightLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(0.22))
                .frame(width: size.width * 0.28, height: size.width * 0.28)
                .blur(radius: 4)
                .offset(x: size.width * 0.22, y: -size.height * 0.18)
                .scaleEffect(1 + CGFloat(sin(phase * 1.5)) * 0.05)

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: size.width * 0.40, height: size.width * 0.40)
                .offset(x: size.width * 0.22, y: -size.height * 0.18)
                .scaleEffect(1 + CGFloat(cos(phase * 1.2)) * 0.04)
        }
    }

    private func cloudLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(theme.kind == .rain || theme.kind == .storm ? 0.10 : 0.16))
                    .frame(width: size.width * 0.28, height: size.height * 0.10)
                    .blur(radius: 6)
                    .offset(
                        x: CGFloat(-20 + index * 48) + CGFloat(sin(phase * 0.32 + Double(index)) * 16),
                        y: CGFloat(-92 + index * 8)
                    )
            }
        }
    }

    private func rainLayer(size: CGSize, phase: Double, intensity: Int) -> some View {
        ZStack {
            ForEach(0..<intensity, id: \.self) { index in
                Capsule()
                    .fill(theme.accent.opacity(0.35))
                    .frame(width: 2, height: CGFloat(22 + (index % 3) * 6))
                    .rotationEffect(.degrees(18))
                    .offset(
                        x: CGFloat(
                            (phase * 84 + Double(index * 37))
                                .truncatingRemainder(dividingBy: Double(size.width + 110))
                        ) - size.width * 0.55,
                        y: CGFloat(
                            (phase * 160 + Double(index * 53))
                                .truncatingRemainder(dividingBy: Double(size.height + 150))
                        ) - size.height * 0.55
                    )
            }
        }
    }

    private func snowLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: CGFloat(4 + (index % 3)), height: CGFloat(4 + (index % 3)))
                    .offset(
                        x: CGFloat(
                            (phase * 26 + Double(index * 41) + sin(phase + Double(index)) * 18)
                                .truncatingRemainder(dividingBy: Double(size.width + 100))
                        ) - size.width * 0.52,
                        y: CGFloat(
                            (phase * 72 + Double(index * 29))
                                .truncatingRemainder(dividingBy: Double(size.height + 130))
                        ) - size.height * 0.52
                    )
            }
        }
    }

    private func starsLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.7 + 0.25 * sin(phase * 1.4 + Double(index))))
                    .frame(width: CGFloat(index % 3 == 0 ? 3.5 : 2.4), height: CGFloat(index % 3 == 0 ? 3.5 : 2.4))
                    .offset(
                        x: CGFloat((index * 31) % Int(max(size.width - 40, 1))) - size.width / 2 + 20,
                        y: CGFloat((index * 27) % Int(max(size.height * 0.55, 1))) - size.height / 2 + 28
                    )
            }
        }
    }

    private func stormPulse(size: CGSize, phase: Double) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.10 + max(0, sin(phase * 3.8)) * 0.22))
            .frame(width: size.width * 0.18, height: 14)
            .blur(radius: 6)
            .rotationEffect(.degrees(-22))
            .offset(x: size.width * 0.12, y: -size.height * 0.06)
    }
}

public struct SettingsAppIconView: View {
    public let size: CGFloat

    public var body: some View {
        iconContent
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var iconContent: some View {
        if let brandImage = AppAssetLoader.brandImage() {
            Image(nsImage: brandImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else if let appIconImage = AppAssetLoader.appIconImage() {
            Image(nsImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else if let appIcon = NSApplication.shared.applicationIconImage, appIcon.size.width > 0 {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Image(systemName: "clock.badge.checkmark.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.22)
                .foregroundStyle(.tint)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

public struct OrpytClickableHoverModifier: ViewModifier {
    public let scale: CGFloat
    public let brightness: Double
    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1)
            .brightness(isHovered ? brightness : 0)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { hovering in
                if hovering && !isHovered {
                    NSCursor.pointingHand.push()
                } else if !hovering && isHovered {
                    NSCursor.pop()
                }

                isHovered = hovering
            }
            .onDisappear {
                if isHovered {
                    NSCursor.pop()
                    isHovered = false
                }
            }
    }
}

extension View {
    public func orpytClickableHover(scale: CGFloat = 1.01, brightness: Double = 0.01) -> some View {
        modifier(OrpytClickableHoverModifier(scale: scale, brightness: brightness))
    }
}

public enum AppAssetLoader {
    public static func appIconImage() -> NSImage? {
        for fileName in ["appstore.png", "logo.png", "Orpyt.icns"] {
            if let url = Bundle.main.resourceURL?.appendingPathComponent(fileName),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    public static func brandImage() -> NSImage? {
        for fileName in ["logo.png", "appstore.png", "orpyt-logo.png"] {
            if let url = Bundle.main.resourceURL?.appendingPathComponent(fileName),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}

public struct TimeZonesPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @Binding public var primarySearchText: String
    @Binding public var secondarySearchText: String
    @State private var selectedSlot: ClockSlot = .primary

    public var body: some View {
        Form {
            Section("Clock") {
                Picker("Edit clock", selection: $selectedSlot) {
                    Text("Primary").tag(ClockSlot.primary)
                    Text("Secondary").tag(ClockSlot.secondary)
                }
                .pickerStyle(.segmented)
            }

            Section("Location") {
                TimeZonePickerCard(
                    title: selectedSlot == .primary ? "Primary Clock" : "Secondary Clock",
                    customLabel: selectedSlot == .primary ? $settings.primaryCustomLabel : $settings.secondaryCustomLabel,
                    selectedTimeZoneID: selectedSlot == .primary ? $settings.primaryTimeZoneID : $settings.secondaryTimeZoneID,
                    searchText: selectedSlot == .primary ? $primarySearchText : $secondarySearchText
                )
            }

            Section {
                Button("Swap Primary and Secondary") {
                    settings.swapTimeZones()
                }
            }
        }
        .formStyle(.grouped)
    }
}

public struct MenuBarPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared

    public var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })) {
                    Text("Launch at Login")
                    Text(launchAtLogin.statusMessage)
                }
                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
            }

            Section("Clocks") {
                Toggle(isOn: $settings.showPrimaryClock) {
                    Text("Show primary clock")
                    Text("Keep the first city visible in the menu bar.")
                }
                Toggle(isOn: $settings.showSecondaryClock) {
                    Text("Show secondary clock")
                    Text("Keep the second city visible in the menu bar.")
                }
            }

            Section("Display") {
                Toggle(isOn: $settings.showZoneLabelInMenuBar) {
                    Text("Show zone labels")
                    Text("Display short city labels beside the time.")
                }
                Toggle(isOn: $settings.showStatusIcon) {
                    Text("Show ambient icon")
                    Text("Use day or night iconography in the menu bar.")
                }
                Toggle(isOn: $settings.use24HourClock) {
                    Text("Use 24-hour time")
                    Text("Switch between 12-hour and 24-hour formats.")
                }
                Toggle(isOn: $settings.showSeconds) {
                    Text("Show seconds")
                    Text("Update the top bar every second.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }
}

public struct DetailsPane: View {
    @ObservedObject public var settings: ClockSettingsStore

    public var body: some View {
        Form {
            Section("Metadata") {
                Toggle(isOn: $settings.showWeekday) {
                    Text("Show weekday")
                    Text("Include weekday in the detailed card.")
                }
                Toggle(isOn: $settings.showDate) {
                    Text("Show date")
                    Text("Include day and month in the detail view.")
                }
                Toggle(isOn: $settings.showTimeZoneAbbreviation) {
                    Text("Show time zone abbreviation")
                    Text("Display labels like EDT or BST.")
                }
                Toggle(isOn: $settings.showGMTOffset) {
                    Text("Show GMT offset")
                    Text("Show numeric GMT offset badges.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

public struct CalendarPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var calendarStore: CalendarStore

    public var body: some View {
        Form {
            Section("Next Meeting") {
                Toggle(isOn: $settings.showCalendarEvents) {
                    Text("Show next meeting")
                    Text("Read your next calendar event and show it in the popover.")
                }
                if case let .loaded(snapshot) = calendarStore.state, let snapshot {
                    LabeledContent("Next event") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(snapshot.title).fontWeight(.medium)
                            Text(snapshot.calendarName).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(statusDescription)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Orpyt never creates or edits events. Permission is requested only after you turn this on.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusDescription: String {
        switch calendarStore.state {
        case .disabled: return "Calendar context is off."
        case .needsPermission: return "Turn the toggle off and back on to request access."
        case .loading: return "Looking for your next event."
        case let .loaded(snapshot): return snapshot == nil ? "No upcoming events in the next 24 hours." : "Next meeting will appear in the popover."
        case let .failed(message): return message
        }
    }
}

public struct WeatherPane: View {
    @ObservedObject public var settings: ClockSettingsStore

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.enableWeather) {
                    Text("Enable live weather")
                    Text("Attach live weather to each clock.")
                }
            }

            Section("Display") {
                Toggle(isOn: $settings.showWeatherInMenuBar) {
                    Text("Use weather icons")
                    Text("Switch the menu bar icon mode from ambient to weather.")
                }
                .disabled(!settings.enableWeather)
                Toggle(isOn: $settings.showWeatherLocation) {
                    Text("Show location in cards")
                    Text("Display the resolved city below the condition.")
                }
                .disabled(!settings.enableWeather)
                Toggle(isOn: $settings.showFeelsLikeTemperature) {
                    Text("Show feels like temperature")
                    Text("Include apparent temperature in the card details.")
                }
                .disabled(!settings.enableWeather)
            }

            Section {
                Text("Weather follows each selected clock city automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

public struct AppearancePane: View {
    @ObservedObject public var settings: ClockSettingsStore

    public var body: some View {
        Form {
            Section("Popover") {
                Picker("Appearance", selection: Binding(
                    get: { settings.appearanceMode },
                    set: { settings.appearanceMode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("This changes the menu bar popover only. Settings always follow macOS.")
                    .foregroundStyle(.secondary)
            }

            Section("Interaction") {
                Toggle(isOn: $settings.muteScrollerSound) {
                    Text("Mute scroller tick")
                    Text("Turn off the native tick sound while scrubbing time.")
                }
            }
        }
        .formStyle(.grouped)
    }
}


public final class OrpytSettingsWindow: NSWindow {
    override public func cancelOperation(_ sender: Any?) {
        close()
    }
}

public struct GlossyInputGroup<Content: View>: View {
    public let title: String
    public let description: String
    @ViewBuilder let content: Content

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct TimeZonePickerCard: View {
    public let title: String
    @Binding public var customLabel: String
    @Binding public var selectedTimeZoneID: String
    @Binding public var searchText: String
    @State private var useCustomLabel: Bool

    public init(
        title: String,
        customLabel: Binding<String>,
        selectedTimeZoneID: Binding<String>,
        searchText: Binding<String>
    ) {
        self.title = title
        _customLabel = customLabel
        _selectedTimeZoneID = selectedTimeZoneID
        _searchText = searchText
        _useCustomLabel = State(
            initialValue: !customLabel.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var filteredOptions: [TimeZoneOption] {
        TimeZoneSearchProvider.results(
            for: searchText,
            suggestions: [selectedTimeZoneID, TimeZone.current.identifier,
                          "America/New_York", "America/Los_Angeles", "Europe/London",
                          "Europe/Paris", "Asia/Dubai", "Asia/Karachi",
                          "Asia/Kolkata", "Asia/Singapore", "Asia/Tokyo", "Australia/Sydney"],
            limit: 80
        )
    }

    private var selectedOption: TimeZoneOption? {
        TimeZoneCatalog.option(for: selectedTimeZoneID)
    }

    private func useCurrentTimeZone() {
        selectedTimeZoneID = TimeZone.current.identifier
        searchText = ""
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Use Current Time Zone", action: useCurrentTimeZone)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .orpytClickableHover(scale: 1.02, brightness: 0.012)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedOption?.cityName ?? selectedTimeZoneID)
                        .font(.system(size: 13, weight: .semibold))
                    Text(selectedOption?.id ?? selectedTimeZoneID)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Custom Name", isOn: $useCustomLabel)
                    .controlSize(.small)
            }

            if useCustomLabel {
                TextField("Custom label", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Search time zone", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Suggested cities are shown first. Start typing to search the full time zone list.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(filteredOptions) { option in
                    Button {
                        selectedTimeZoneID = option.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(option.id)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedTimeZoneID == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .orpytClickableHover(scale: 1.01, brightness: 0.012)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                }
            }
            .listStyle(.inset)
            .frame(height: 280)
        }
        .padding(.top, 2)
        .onChange(of: useCustomLabel) { isEnabled in
            if !isEnabled {
                customLabel = ""
            }
        }
        .onChange(of: selectedTimeZoneID) { _ in
            if !useCustomLabel {
                customLabel = ""
            }
        }
    }
}

public struct PrimaryGlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 0.92))
            )
            .foregroundStyle(.white)
    }
}

public struct SecondaryGlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.26 : 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            )
    }
}
