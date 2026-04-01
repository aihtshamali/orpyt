import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

public struct StatusPopoverView: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var weatherStore: WeatherStore
    @ObservedObject public var calendarStore: CalendarStore
    public let appearanceMode: AppearanceMode
    public let onOpenSettings: () -> Void
    public let onSwapTimeZones: () -> Void
    public let onQuit: () -> Void
    public let onContentHeightChange: (CGFloat) -> Void
    @State private var isQuickSearchPresented = false
    @State private var quickSearchText = ""
    @State private var quickSearchTarget: ClockSlot = .secondary
    @State private var timeShiftMinutes = 0
    @State private var primarySearchText = ""
    @State private var secondarySearchText = ""
    @FocusState private var isQuickSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private static let maxPopoverHeight: CGFloat = 760

    private var isScrollEnabled: Bool {
        isQuickSearchPresented
    }

    public init(
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        calendarStore: CalendarStore,
        appearanceMode: AppearanceMode,
        onOpenSettings: @escaping () -> Void,
        onSwapTimeZones: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onContentHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.appearanceMode = appearanceMode
        self.onOpenSettings = onOpenSettings
        self.onSwapTimeZones = onSwapTimeZones
        self.onQuit = onQuit
        self.onContentHeightChange = onContentHeightChange
    }

    private var palette: PopoverPalette {
        PopoverPalette.make(for: appearanceMode, systemColorScheme: colorScheme)
    }

    private var preferredPopoverHeight: CGFloat {
        var height: CGFloat = settings.showPrimaryClock && settings.showSecondaryClock ? 455 : 420

        if isQuickSearchPresented {
            height += 220
        }

        if settings.enableWeather {
            height += 36
        }

        if settings.enableWeather, weatherStore.attribution != nil {
            height += 18
        }

        if settings.showCalendarEvents {
            height += 82
        }

        height += 86

        return height
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: settings.showSeconds ? 1 : 60)) { context in
            let displayedDate = context.date.addingTimeInterval(TimeInterval(timeShiftMinutes * 60))
            ZStack(alignment: .topLeading) {
                PopoverBackdrop(palette: palette)

                ScrollViewReader { scrollProxy in
                    ScrollView(isScrollEnabled ? .vertical : [], showsIndicators: isScrollEnabled) {
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear
                                .frame(height: 0)
                                .id("popoverTop")

                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Orpyt")
                                        .font(.system(size: 17, weight: .semibold))
                                    Text("Synced across cities, weather, and work.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    CompactGlassButton(
                                        symbol: isQuickSearchPresented ? "xmark" : "magnifyingglass",
                                        palette: palette,
                                        action: toggleQuickSearch
                                    )
                                    .help(isQuickSearchPresented ? "Close search" : "Search cities")
                                    CompactGlassButton(symbol: "arrow.left.arrow.right", palette: palette, action: onSwapTimeZones)
                                        .help("Swap clocks")
                                    CompactGlassButton(symbol: "slider.horizontal.3", palette: palette, action: onOpenSettings)
                                        .help("Open settings")
                                    CompactGlassButton(symbol: "power", palette: palette) {
                                        onQuit()
                                    }
                                    .help("Quit Orpyt")
                                }
                            }

                            if isQuickSearchPresented {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)

                                        TextField("Search city or time zone", text: $quickSearchText)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 13, weight: .medium))
                                            .focused($isQuickSearchFocused)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(palette.chromeFill)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(palette.chromeStroke, lineWidth: 0.8)
                                    )

                                    if visibleSlots.count > 1 {
                                        Picker("Target", selection: $quickSearchTarget) {
                                            Text("Primary").tag(ClockSlot.primary)
                                            Text("Secondary").tag(ClockSlot.secondary)
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))

                                PopoverQuickSearchView(
                                    searchText: $quickSearchText,
                                    targetSlot: $quickSearchTarget,
                                    primaryCustomLabel: $settings.primaryCustomLabel,
                                    secondaryCustomLabel: $settings.secondaryCustomLabel,
                                    availableSlots: visibleSlots,
                                    results: quickSearchResults,
                                    onSelect: applyQuickSearch(_:),
                                    onUseCurrentTimeZone: useCurrentTimeZoneForQuickSearch
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            HStack(spacing: 12) {
                                if settings.showPrimaryClock {
                                    ClockCardView(
                                        slot: .primary,
                                        title: "Primary",
                                        label: settings.displayLabel(
                                            for: settings.primaryTimeZoneID,
                                            customLabel: settings.primaryCustomLabel
                                        ),
                                        timeZoneID: settings.primaryTimeZoneID,
                                        settings: settings,
                                        weatherState: weatherStore.state(for: .primary),
                                        date: displayedDate,
                                        palette: palette,
                                        onTap: {
                                            if isQuickSearchPresented && quickSearchTarget == .primary {
                                                toggleQuickSearch()
                                            } else {
                                                quickSearchTarget = .primary
                                                if !isQuickSearchPresented { toggleQuickSearch() }
                                            }
                                        }
                                    )
                                }

                                if settings.showSecondaryClock {
                                    ClockCardView(
                                        slot: .secondary,
                                        title: "Secondary",
                                        label: settings.displayLabel(
                                            for: settings.secondaryTimeZoneID,
                                            customLabel: settings.secondaryCustomLabel
                                        ),
                                        timeZoneID: settings.secondaryTimeZoneID,
                                        settings: settings,
                                        weatherState: weatherStore.state(for: .secondary),
                                        date: displayedDate,
                                        palette: palette,
                                        onTap: {
                                            if isQuickSearchPresented && quickSearchTarget == .secondary {
                                                toggleQuickSearch()
                                            } else {
                                                quickSearchTarget = .secondary
                                                if !isQuickSearchPresented { toggleQuickSearch() }
                                            }
                                        }
                                    )
                                }
                            }

                            if settings.showCalendarEvents {
                                NextMeetingSnippetView(
                                    state: calendarStore.state,
                                    now: context.date,
                                    primaryTimeZoneID: settings.primaryTimeZoneID,
                                    onOpenMeeting: openMeeting,
                                    onRequestAccess: {
                                        let status = EKEventStore.authorizationStatus(for: .event)
                                        let isDenied: Bool
                                        if #available(macOS 14.0, *) {
                                            isDenied = status == .denied || status == .restricted
                                        } else {
                                            isDenied = status == .denied || status == .restricted
                                        }
                                        if isDenied {
                                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                                        } else {
                                            Task { await calendarStore.enable(using: settings) }
                                        }
                                    }
                                )
                            }

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                            ], spacing: 10) {
                                QuickSettingChip(
                                    title: settings.use24HourClock ? "24h" : "12h",
                                    subtitle: "Clock mode",
                                    isOn: $settings.use24HourClock,
                                    palette: palette
                                )

                                QuickSettingChip(
                                    title: settings.showSeconds ? "Seconds On" : "Seconds Off",
                                    subtitle: "Precision",
                                    isOn: $settings.showSeconds,
                                    palette: palette
                                )
                            }

                            TimeScrollerStrip(
                                timeShiftMinutes: $timeShiftMinutes,
                                palette: palette,
                                isMuted: $settings.muteScrollerSound,
                                now: context.date
                            )

                            if settings.enableWeather, let attribution = weatherStore.attribution {
                                WeatherAttributionFooterView(attribution: attribution)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .onChange(of: isQuickSearchPresented) { _ in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollProxy.scrollTo("popoverTop", anchor: .top)
                        }
                    }
                }
            }
            .frame(width: 452)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 30, x: 0, y: 18)
            .onAppear {
                onContentHeightChange(preferredPopoverHeight)
            }
            .onDisappear {
                // Reset all transient UI state when the popover closes.
                // Persisted settings (time zone, labels, chip toggles) are NOT touched.
                isQuickSearchPresented = false
                quickSearchText = ""
                primarySearchText = ""
                secondarySearchText = ""
                timeShiftMinutes = 0
            }
            .onChange(of: preferredPopoverHeight) { newValue in
                onContentHeightChange(newValue)
            }
            .task(id: timeShiftMinutes) {
                guard timeShiftMinutes != 0 else { return }
                let currentValue = timeShiftMinutes
                try? await Task.sleep(for: .seconds(30))

                guard !Task.isCancelled, timeShiftMinutes == currentValue else { return }

                withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                    timeShiftMinutes = 0
                }
            }
        }
    }



    private var visibleSlots: [ClockSlot] {
        var slots: [ClockSlot] = []

        if settings.showPrimaryClock {
            slots.append(.primary)
        }

        if settings.showSecondaryClock {
            slots.append(.secondary)
        }

        return slots.isEmpty ? [.primary, .secondary] : slots
    }

    private var quickSearchResults: [TimeZoneOption] {
        TimeZoneSearchProvider.results(
            for: quickSearchText,
            suggestions: [targetTimeZoneID(for: .primary), targetTimeZoneID(for: .secondary),
                          TimeZone.current.identifier, "Etc/UTC",
                          "Europe/London", "America/New_York", "Asia/Tokyo", "Asia/Karachi"]
        )
    }

    private func targetTimeZoneID(for slot: ClockSlot) -> String {
        switch slot {
        case .primary:
            return settings.primaryTimeZoneID
        case .secondary:
            return settings.secondaryTimeZoneID
        }
    }

    private func toggleQuickSearch() {
        if isQuickSearchPresented {
            isQuickSearchPresented = false
            quickSearchText = ""
            return
        }

        quickSearchTarget = defaultQuickSearchTarget
        isQuickSearchPresented = true

        DispatchQueue.main.async {
            isQuickSearchFocused = true
        }
    }

    private var defaultQuickSearchTarget: ClockSlot {
        if visibleSlots == [.primary] {
            return .primary
        }

        if visibleSlots == [.secondary] {
            return .secondary
        }

        return .secondary
    }

    private func applyQuickSearch(_ option: TimeZoneOption) {
        switch quickSearchTarget {
        case .primary:
            settings.primaryTimeZoneID = option.id
        case .secondary:
            settings.secondaryTimeZoneID = option.id
        }

        quickSearchText = ""
        isQuickSearchPresented = false
    }

    private func useCurrentTimeZoneForQuickSearch() {
        let currentIdentifier = TimeZone.current.identifier

        switch quickSearchTarget {
        case .primary:
            settings.primaryTimeZoneID = currentIdentifier
        case .secondary:
            settings.secondaryTimeZoneID = currentIdentifier
        }

        quickSearchText = ""
        isQuickSearchPresented = false
    }

    private func openMeeting(_ snapshot: MeetingSnapshot) {
        if let joinURL = snapshot.joinURL {
            NSWorkspace.shared.open(joinURL)
            return
        }
        if let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: calendarURL, configuration: configuration)
        }
    }

}

public struct PopoverQuickSearchView: View {
    @Binding public var searchText: String
    @Binding public var targetSlot: ClockSlot
    @Binding public var primaryCustomLabel: String
    @Binding public var secondaryCustomLabel: String
    public let availableSlots: [ClockSlot]
    public let results: [TimeZoneOption]
    public let onSelect: (TimeZoneOption) -> Void
    public let onUseCurrentTimeZone: () -> Void

    private var customLabelBinding: Binding<String> {
        targetSlot == .primary ? $primaryCustomLabel : $secondaryCustomLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Search")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button(action: onUseCurrentTimeZone) {
                    Label("Current", systemImage: "location.fill")
                }
                .buttonStyle(.borderless)
                .orpytClickableHover(scale: 1.02, brightness: 0.012)
                .font(.system(size: 11, weight: .medium))
            }

            if availableSlots.count > 1 {
                Text(targetSlot == .primary ? "Updating the primary clock." : "Updating the secondary clock.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Pick a city and Orpyt will update the visible clock immediately.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Custom label field
            TextField("Custom name (optional)", text: customLabelBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )

            VStack(spacing: 0) {
                ForEach(results) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(option.id)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(shortTargetTitle)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .orpytClickableHover(scale: 1.01, brightness: 0.015)

                    if option.id != results.last?.id {
                        Divider()
                            .opacity(0.4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
        }
    }

    private var shortTargetTitle: String {
        switch targetSlot {
        case .primary:
            return "Primary"
        case .secondary:
            return "Secondary"
        }
    }
}

public struct PopoverPalette {
    public let backgroundColors: [Color]
    public let orbPrimary: Color
    public let orbSecondary: Color
    public let cardFill: Color
    public let cardStroke: Color
    public let chipOffFill: Color
    public let chipOnFill: Color
    public let chromeFill: Color
    public let chromeStroke: Color
    public let badgeFill: Color
    public let badgeStroke: Color

    public static func make(for appearanceMode: AppearanceMode, systemColorScheme: ColorScheme) -> PopoverPalette {
        let colorScheme: ColorScheme
        switch appearanceMode {
        case .system:
            colorScheme = systemColorScheme
        case .light:
            colorScheme = .light
        case .dark:
            colorScheme = .dark
        }

        switch colorScheme {
        case .dark:
            return PopoverPalette(
                backgroundColors: [
                    Color(red: 0.14, green: 0.17, blue: 0.22),
                    Color(red: 0.12, green: 0.18, blue: 0.30),
                    Color(red: 0.17, green: 0.15, blue: 0.24),
                ],
                orbPrimary: Color.white.opacity(0.08),
                orbSecondary: Color.blue.opacity(0.16),
                cardFill: Color.white.opacity(0.08),
                cardStroke: Color.white.opacity(0.12),
                chipOffFill: Color.white.opacity(0.07),
                chipOnFill: Color.white.opacity(0.12),
                chromeFill: Color.white.opacity(0.08),
                chromeStroke: Color.white.opacity(0.14),
                badgeFill: Color.white.opacity(0.08),
                badgeStroke: Color.white.opacity(0.12)
            )
        default:
            return PopoverPalette(
                backgroundColors: [
                    Color.white.opacity(0.76),
                    Color(red: 0.84, green: 0.90, blue: 0.98).opacity(0.78),
                    Color(red: 0.95, green: 0.93, blue: 1).opacity(0.72),
                ],
                orbPrimary: Color.white.opacity(0.32),
                orbSecondary: Color.blue.opacity(0.14),
                cardFill: Color.white.opacity(0.24),
                cardStroke: Color.white.opacity(0.26),
                chipOffFill: Color.white.opacity(0.18),
                chipOnFill: Color.white.opacity(0.34),
                chromeFill: Color.white.opacity(0.20),
                chromeStroke: Color.white.opacity(0.22),
                badgeFill: Color.white.opacity(0.16),
                badgeStroke: Color.white.opacity(0.18)
            )
        }
    }
}

public struct PopoverBackdrop: View {
    public let palette: PopoverPalette

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.orbPrimary)
                .frame(width: 220, height: 220)
                .offset(x: -120, y: -110)
                .blur(radius: 20)

            Circle()
                .fill(palette.orbSecondary)
                .frame(width: 240, height: 240)
                .offset(x: 120, y: 70)
                .blur(radius: 24)
        }
        .background(.ultraThinMaterial)
    }
}

public struct CompactGlassButton: View {
    public let symbol: String
    public let palette: PopoverPalette
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.chromeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.chromeStroke, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .orpytClickableHover(scale: 1.04, brightness: 0.02)
    }
}

public struct QuickSettingChip: View {
    public let title: String
    public let subtitle: String
    @Binding public var isOn: Bool
    public let palette: PopoverPalette

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? palette.chipOnFill : palette.chipOffFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.chromeStroke.opacity(isOn ? 1 : 0.7), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .orpytClickableHover(scale: 1.015, brightness: 0.018)
    }
}

/// Shared reference that lets TimeScrollerWheelCapture focus the slider directly.
@MainActor
public final class SliderFocusProxy: ObservableObject {
    weak var slider: NSSlider?
    func focus() {
        guard let slider, let window = slider.window else { return }
        window.makeFirstResponder(slider)
    }
    func blur() {
        guard let slider, let window = slider.window else { return }
        if window.firstResponder === slider { window.makeFirstResponder(nil) }
    }
}

public struct TimeScrollerStrip: View {
    @Binding public var timeShiftMinutes: Int
    public let palette: PopoverPalette
    @Binding public var isMuted: Bool
    public let now: Date
    @State private var isHovered = false
    @StateObject private var focusProxy = SliderFocusProxy()

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(timeShiftMinutes) / 60.0 },
            set: { newValue in
                let snapped = (newValue * 4).rounded() / 4
                timeShiftMinutes = Int(snapped * 60)
            }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Time Scroller")
                            .font(.system(size: 12, weight: .semibold))
                        Text(scrolledTimeLabel)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(timeShiftMinutes == 0 ? Color.secondary : Color.accentColor)
                    }
                    Text(timeShiftMinutes == 0 ? "Showing right now across both clocks." : shiftLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isMuted ? .secondary : .primary)
                }
                .buttonStyle(.borderless)
                .help(isMuted ? "Turn on scroll sound" : "Mute scroll sound")

                Button(timeShiftMinutes == 0 ? "Now" : "Reset") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        timeShiftMinutes = 0
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
            }

            WheelScrubbingSlider(
                value: sliderValue,
                range: -12...12,
                step: 0.25,
                isMuted: isMuted,
                focusProxy: focusProxy
            )
            .frame(height: 18)

            // Tick marks + labels — tappable to jump directly to that hour
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let labeledHours: [(hour: Int, label: String)] = [
                    (-12, "-12h"), (-9, "-9h"), (-6, "-6h"), (-3, "-3h"),
                    (0, "Now"), (3, "+3h"), (6, "+6h"), (9, "+9h"), (12, "+12h")
                ]
                ForEach(labeledHours, id: \.hour) { item in
                    let fraction = Double(item.hour + 12) / 24.0
                    let xPos = totalWidth * fraction
                    let isAtCurrentHour = (timeShiftMinutes / 60 == item.hour && timeShiftMinutes % 60 == 0)
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(isAtCurrentHour ? Color.primary.opacity(0.6) : Color.primary.opacity(0.18))
                            .frame(width: isAtCurrentHour ? 1.5 : 1, height: isAtCurrentHour ? 6 : 4)
                        Text(item.label)
                            .font(.system(size: 9, weight: isAtCurrentHour ? .semibold : .regular))
                            .foregroundStyle(isAtCurrentHour ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.7))
                            .fixedSize()
                    }
                    .position(x: xPos, y: 12)
                    .contentShape(Rectangle().size(CGSize(width: 36, height: 28)).offset(x: xPos - 18, y: 0))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            timeShiftMinutes = item.hour * 60
                        }
                        focusProxy.focus()
                    }
                    .cursor(.pointingHand)
                }
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            // Wheel capture behind all content so clicks pass through to buttons/labels
            TimeScrollerWheelCapture(isMuted: isMuted, focusProxy: focusProxy) { step in
                let newValue = max(-12.0, min(12.0, Double(timeShiftMinutes) / 60.0 + Double(step) * 0.25))
                let snapped = (newValue * 4).rounded() / 4
                timeShiftMinutes = Int(snapped * 60)
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isHovered ? palette.cardStroke.opacity(2.2) : palette.cardStroke, lineWidth: isHovered ? 1.2 : 0.8)
        )
        .onHover { hovered in
            isHovered = hovered
            if !hovered {
                focusProxy.blur()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var scrolledTimeLabel: String {
        let shifted = now.addingTimeInterval(TimeInterval(timeShiftMinutes * 60))
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "h:mm a"
        return  "(" + fmt.string(from: shifted) + ")"
    }

    private var shiftLabel: String {
        let absoluteMinutes = abs(timeShiftMinutes)
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        let prefix = timeShiftMinutes > 0 ? "+" : "-"
        if minutes == 0 {
            return "Previewing \(prefix)\(hours)h across your clocks."
        }
        return "Previewing \(prefix)\(hours)h \(minutes)m across your clocks."
    }
}


/// Transparent NSView overlay that captures horizontal scrubbing while allowing
/// normal vertical scrolling to continue through the popover content.
public struct TimeScrollerWheelCapture: NSViewRepresentable {
    public let isMuted: Bool
    public let focusProxy: SliderFocusProxy?
    public let onStep: (Int) -> Void

    public func makeNSView(context: Context) -> TimeScrollerWheelNSView {
        let view = TimeScrollerWheelNSView()
        view.isMuted = isMuted
        view.focusProxy = focusProxy
        view.onStep = onStep
        return view
    }

    public func updateNSView(_ nsView: TimeScrollerWheelNSView, context: Context) {
        nsView.isMuted = isMuted
        nsView.focusProxy = focusProxy
        nsView.onStep = onStep
    }
}

public final class TimeScrollerWheelNSView: NSView {
    public var onStep: (Int) -> Void = { _ in }
    public var isMuted: Bool = false
    public var focusProxy: SliderFocusProxy?
    private var accumulatedDelta: CGFloat = 0
    private let scrollThreshold: CGFloat = 6

    override public var acceptsFirstResponder: Bool { true }

    // Pass all mouse clicks through so SwiftUI buttons underneath remain hittable.
    override public func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    override public func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    override public func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
    override public func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }

    override public func scrollWheel(with event: NSEvent) {
        let horizontalDelta = event.scrollingDeltaX
        let verticalDelta = event.scrollingDeltaY
        guard abs(horizontalDelta) > abs(verticalDelta) else {
            nextResponder?.scrollWheel(with: event)
            return
        }

        guard abs(horizontalDelta) > 0.1 else {
            nextResponder?.scrollWheel(with: event)
            return
        }

        accumulatedDelta += horizontalDelta

        while abs(accumulatedDelta) >= scrollThreshold {
            let direction = accumulatedDelta > 0 ? -1 : 1
            accumulatedDelta += accumulatedDelta > 0 ? -scrollThreshold : scrollThreshold
            focusProxy?.focus()
            onStep(direction)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            TickFeedbackPlayer.shared.play(isMuted: isMuted)
        }
    }
}

public struct WheelScrubbingSlider: NSViewRepresentable {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double
    public let isMuted: Bool
    public var focusProxy: SliderFocusProxy? = nil

    public func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    public func makeNSView(context: Context) -> WheelScrubbingNSSlider {
        let slider = WheelScrubbingNSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.valueDidChange(_:)))
        slider.stepValue = step
        slider.isMuted = isMuted
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueDidChange(_:))
        focusProxy?.slider = slider
        return slider
    }

    public func updateNSView(_ nsView: WheelScrubbingNSSlider, context: Context) {
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        nsView.stepValue = step
        nsView.isMuted = isMuted
        if abs(nsView.doubleValue - value) > 0.001 {
            nsView.doubleValue = value
        }
        focusProxy?.slider = nsView
    }

    @MainActor
    public final class Coordinator: NSObject {
        @Binding private var value: Double

        init(value: Binding<Double>) {
            _value = value
        }

        @objc func valueDidChange(_ sender: NSSlider) {
            value = sender.doubleValue
        }
    }
}

public final class WheelScrubbingNSSlider: NSSlider {
    public var stepValue: Double = 0.25
    public var isMuted = false
    private var accumulatedDelta: CGFloat = 0
    private let scrollThreshold: CGFloat = 6

    override public func scrollWheel(with event: NSEvent) {
        let dominantDelta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX

        accumulatedDelta += dominantDelta

        while abs(accumulatedDelta) >= scrollThreshold {
            let direction = accumulatedDelta > 0 ? -1.0 : 1.0
            accumulatedDelta += accumulatedDelta > 0 ? -scrollThreshold : scrollThreshold

            let nextValue = max(minValue, min(maxValue, doubleValue + (direction * stepValue)))
            guard abs(nextValue - doubleValue) > 0.0001 else { continue }

            doubleValue = nextValue
            sendAction(action, to: target)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            TickFeedbackPlayer.shared.play(isMuted: isMuted)
        }
    }
}

@MainActor
public final class TickFeedbackPlayer {
    public static let shared = TickFeedbackPlayer()

    // Template sound — never played directly; cloned for each tick so there's
    // no stop/play contention and playback starts with zero latency.
    private let template: NSSound?

    private init() {
        if let bundled = NSSound(named: NSSound.Name("Tink")) {
            template = bundled
        } else {
            template = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)
        }
        template?.volume = 0.22
    }

    public func play(isMuted: Bool = false) {
        guard !isMuted, let copy = template?.copy() as? NSSound else { return }
        copy.play()
    }
}

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
