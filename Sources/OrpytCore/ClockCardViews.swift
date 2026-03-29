import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

public struct ClockCardView: View {
    public let slot: ClockSlot
    public let title: String
    public let label: String
    public let timeZoneID: String
    @ObservedObject public var settings: ClockSettingsStore
    public let weatherState: WeatherState
    public let date: Date
    public let isEditing: Bool
    public let palette: PopoverPalette

    private var timeFontSize: CGFloat {
        if settings.showSeconds {
            return settings.use24HourClock ? 46 : 40
        }

        return settings.use24HourClock ? 54 : 50
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: ClockFormatter.cardIconName(for: date, timeZoneID: timeZoneID, weatherState: weatherState))
                        .font(.system(size: 15, weight: .semibold))
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(.primary.opacity(0.86))

                Spacer()

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(ClockFormatter.timeText(for: date, timeZoneID: timeZoneID, settings: settings))
                .font(.system(size: timeFontSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)

            Text(ClockFormatter.dateText(for: date, timeZoneID: timeZoneID, settings: settings))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                let metaText = ClockFormatter.metaText(for: date, timeZoneID: timeZoneID, settings: settings)
                if !metaText.isEmpty {
                    CapsuleInfoBadge(text: metaText, palette: palette)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            WeatherSummaryView(
                slot: slot,
                settings: settings,
                weatherState: weatherState
            )
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)

            Text(isEditing ? "Editing from popover" : "Click to change city")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            minHeight: settings.enableWeather ? 270 : 220,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isEditing ? palette.chipOnFill : palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isEditing ? Color.accentColor.opacity(0.35) : palette.cardStroke, lineWidth: 1)
        )
    }
}

/// Shared search logic used by both the popover quick search and the inline editor.
public struct TimeZoneSearchProvider {
    /// Returns matching options for a query, or suggested defaults when query is empty.
    public static func results(
        for query: String,
        suggestions: [String],
        limit: Int = 8
    ) -> [TimeZoneOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return suggested(from: suggestions)
        }
        return Array(
            TimeZoneCatalog.options
                .lazy
                .filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
                .prefix(limit)
        )
    }

    public static func suggested(from identifiers: [String]) -> [TimeZoneOption] {
        var seen = Set<String>()
        return identifiers.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return TimeZoneCatalog.option(for: id)
        }
    }
}

public struct InlineTimeZoneEditorView: View {
    public let title: String
    @Binding public var selectedTimeZoneID: String
    @Binding public var customLabel: String
    @Binding public var searchText: String
    public let onDone: () -> Void
    @State private var useCustomLabel: Bool

    public init(
        title: String,
        selectedTimeZoneID: Binding<String>,
        customLabel: Binding<String>,
        searchText: Binding<String>,
        onDone: @escaping () -> Void
    ) {
        self.title = title
        _selectedTimeZoneID = selectedTimeZoneID
        _customLabel = customLabel
        _searchText = searchText
        self.onDone = onDone
        _useCustomLabel = State(
            initialValue: !customLabel.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var filteredOptions: [TimeZoneOption] {
        TimeZoneSearchProvider.results(
            for: searchText,
            suggestions: [selectedTimeZoneID, TimeZone.current.identifier,
                          "America/Chicago", "America/New_York", "Europe/London",
                          "Asia/Karachi", "Asia/Dubai", "Asia/Singapore"]
        )
    }

    private var selectedOption: TimeZoneOption? {
        TimeZoneCatalog.option(for: selectedTimeZoneID)
    }

    private func useCurrentTimeZone() {
        selectedTimeZoneID = TimeZone.current.identifier
        searchText = ""
        onDone()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: useCurrentTimeZone) {
                    Image(systemName: "location.fill")
                }
                .buttonStyle(SecondaryGlassButtonStyle())
                .orpytClickableHover(scale: 1.03, brightness: 0.015)
                .help("Use current time zone")
                Button("Done", action: onDone)
                    .buttonStyle(SecondaryGlassButtonStyle())
                    .orpytClickableHover(scale: 1.03, brightness: 0.015)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedOption?.cityName ?? selectedTimeZoneID)
                        .font(.system(size: 13, weight: .semibold))
                    Text(selectedOption?.id ?? selectedTimeZoneID)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Custom Name", isOn: $useCustomLabel)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if useCustomLabel {
                TextField("Custom label", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Search time zone", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Start typing to search, or pick from the suggested cities below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(filteredOptions) { option in
                    Button {
                        selectedTimeZoneID = option.id
                        onDone()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(option.id)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTimeZoneID == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .orpytClickableHover(scale: 1.01, brightness: 0.012)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                }
            }
            .listStyle(.inset)
            .frame(height: 170)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
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

public struct CapsuleInfoBadge: View {
    public let text: String
    public let palette: PopoverPalette

    public var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(palette.badgeFill)
            )
            .overlay(
                Capsule()
                    .stroke(palette.badgeStroke, lineWidth: 0.8)
            )
    }
}

public struct WeatherSummaryView: View {
    public let slot: ClockSlot
    @ObservedObject public var settings: ClockSettingsStore
    public let weatherState: WeatherState

    public var body: some View {
        if settings.enableWeather {
            Group {
                switch weatherState {
                case .idle:
                    EmptyView()
                case .loading:
                    Label("Loading weather", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                case let .loaded(snapshot):
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: snapshot.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(snapshot.temperatureText) • \(snapshot.conditionText)")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            if settings.showWeatherLocation || settings.showFeelsLikeTemperature {
                                Text(detailText(for: snapshot))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case let .failed(message):
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.top, 2)
        }
    }

    private func detailText(for snapshot: WeatherSnapshot) -> String {
        var parts: [String] = []

        if settings.showWeatherLocation {
            parts.append(snapshot.resolvedLocationName)
        }

        if settings.showFeelsLikeTemperature {
            parts.append("Feels like \(snapshot.feelsLikeText)")
        }

        return parts.joined(separator: " • ")
    }
}

public struct WeatherAttributionFooterView: View {
    public let attribution: WeatherAttributionSnapshot
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        HStack {
            AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 14)
                default:
                    Text("Apple Weather")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Link("Legal", destination: attribution.legalPageURL)
                .font(.system(size: 10))
        }
        .padding(.top, 4)
    }
}

public struct NextMeetingSnippetView: View {
    public let state: CalendarState
    public let now: Date
    public let primaryTimeZoneID: String
    public let onOpenMeeting: (MeetingSnapshot) -> Void

    public var body: some View {
        Group {
            switch state {
            case .disabled:
                EmptyView()
            case .needsPermission:
                cardSurface(interactive: false) {
                    summaryRow(symbol: "calendar.badge.exclamationmark", title: "Calendar ready", subtitle: "Turn it on in settings to show your next meeting.", showsChevron: false)
                }
            case .loading:
                cardSurface(interactive: false) {
                    summaryRow(symbol: "calendar", title: "Checking your calendar", subtitle: "Looking for the next event.", showsChevron: false)
                }
            case let .loaded(snapshot):
                if let snapshot {
                    Button {
                        onOpenMeeting(snapshot)
                    } label: {
                        cardSurface(interactive: true) {
                            summaryRow(
                                symbol: "calendar",
                                title: snapshot.title,
                                subtitle: meetingSubtitle(for: snapshot),
                                showsChevron: true
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .orpytClickableHover(scale: 1.012, brightness: 0.014)
                } else {
                    cardSurface(interactive: false) {
                        summaryRow(symbol: "calendar", title: "No upcoming meetings", subtitle: "Nothing scheduled in the next 24 hours.", showsChevron: false)
                    }
                }
            case let .failed(message):
                cardSurface(interactive: false) {
                    summaryRow(symbol: "calendar.badge.exclamationmark", title: "Calendar unavailable", subtitle: message, showsChevron: false)
                }
            }
        }
    }

    private func summaryRow(symbol: String, title: String, subtitle: String, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Next Meeting")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func cardSurface<Content: View>(interactive: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(interactive ? 0.16 : 0.12),
                                Color.white.opacity(interactive ? 0.20 : 0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(interactive ? 0.28 : 0.18), lineWidth: interactive ? 1.0 : 0.9)
            )
            .shadow(color: Color.accentColor.opacity(interactive ? 0.10 : 0.04), radius: interactive ? 12 : 6, x: 0, y: interactive ? 7 : 3)
    }

    private func meetingSubtitle(for snapshot: MeetingSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone(identifier: primaryTimeZoneID)
        formatter.dateFormat = "h:mm a"

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .short

        let startTime = formatter.string(from: snapshot.startDate)
        let relative = relativeFormatter.localizedString(for: snapshot.startDate, relativeTo: now)
        return "\(startTime) • \(relative) • \(snapshot.calendarName)"
    }
}
