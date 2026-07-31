import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UserNotifications
import WeatherKit

public struct SettingsView: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var weatherStore: WeatherStore
    @ObservedObject public var calendarStore: CalendarStore
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var agentStore: AgentActivityStore
    @ObservedObject public var integrationManager: AgentIntegrationManager
    @ObservedObject public var navigationStore: SettingsNavigationStore
    public let onCheckForUpdates: () -> Void
    public let onTestReviewPrompt: () -> Void
    @State private var primarySearchText = ""
    @State private var secondarySearchText = ""

    public init(
        settings: ClockSettingsStore,
        weatherStore: WeatherStore,
        calendarStore: CalendarStore,
        subscriptionStore: SubscriptionStore,
        agentStore: AgentActivityStore,
        integrationManager: AgentIntegrationManager,
        navigationStore: SettingsNavigationStore,
        onCheckForUpdates: @escaping () -> Void,
        onTestReviewPrompt: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.weatherStore = weatherStore
        self.calendarStore = calendarStore
        self.subscriptionStore = subscriptionStore
        self.agentStore = agentStore
        self.integrationManager = integrationManager
        self.navigationStore = navigationStore
        self.onCheckForUpdates = onCheckForUpdates
        self.onTestReviewPrompt = onTestReviewPrompt
    }

    public var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            detailView(for: navigationStore.selectedPane)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var settingsSidebar: some View {
        #if os(macOS)
        List(SettingsPane.allCases, selection: $navigationStore.selectedPane) { pane in
            Label(pane.rawValue, systemImage: pane.icon)
                .tag(pane)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .listStyle(.sidebar)
        #else
        List(SettingsPane.allCases) { pane in
            Button {
                navigationStore.selectedPane = pane
            } label: {
                Label(pane.rawValue, systemImage: pane.icon)
            }
            .buttonStyle(.plain)
            .listRowBackground(navigationStore.selectedPane == pane ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .listStyle(.sidebar)
        #endif
    }

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        let banner = ProUpgradeBanner(subscriptionStore: subscriptionStore, welcomeStore: WelcomePeriodStore.shared)
        switch pane {
        case .overview:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                SettingsOverviewPane(settings: settings, weatherStore: weatherStore, calendarStore: calendarStore, subscriptionStore: subscriptionStore, onCheckForUpdates: onCheckForUpdates, onTestReviewPrompt: onTestReviewPrompt)
            }
            .navigationTitle("Overview")
        case .timeZones:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                TimeZonesPane(settings: settings, primarySearchText: $primarySearchText, secondarySearchText: $secondarySearchText)
            }
            .navigationTitle("Time Zones")
        case .menuBar:
            #if os(macOS)
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                MenuBarPane(settings: settings, subscriptionStore: subscriptionStore, navigationStore: navigationStore)
            }
            .navigationTitle("Menu Bar")
            #else
            DashboardDisplayPane(settings: settings)
                .navigationTitle("Dashboard Layout")
            #endif
        case .details:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                DetailsPane(settings: settings)
            }
            .navigationTitle("Clock Details")
        case .calendar:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                CalendarPane(settings: settings, calendarStore: calendarStore, subscriptionStore: subscriptionStore, navigationStore: navigationStore)
            }
            .navigationTitle("Calendar")
        case .agents:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                AgentPulseSettingsPane(agentStore: agentStore, integrationManager: integrationManager)
            }
            .navigationTitle("AI Agents (Beta)")
        case .weather:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                WeatherPane(settings: settings, subscriptionStore: subscriptionStore, navigationStore: navigationStore)
            }
            .navigationTitle("Weather")
        case .appearance:
            VStack(spacing: 0) {
                banner.padding(.horizontal, 16).padding(.top, 12)
                AppearancePane(settings: settings, subscriptionStore: subscriptionStore, navigationStore: navigationStore)
            }
            .navigationTitle("Appearance")
        }
    }
}

@MainActor
public final class SettingsNavigationStore: ObservableObject {
    @Published public var selectedPane: SettingsPane = .overview

    public init() {}
}

public enum SettingsPane: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case timeZones = "Time Zones"
    case menuBar = "Menu Bar"
    case details = "Clock Details"
    case calendar = "Calendar"
    case agents = "AI Agents (Beta)"
    case weather = "Weather"
    case appearance = "Appearance"

    public var id: String { rawValue }

    public static var allCases: [SettingsPane] {
        #if os(macOS)
        return [.overview, .timeZones, .menuBar, .details, .calendar, .agents, .weather, .appearance]
        #else
        return [.overview, .timeZones, .details, .calendar, .agents, .weather, .appearance]
        #endif
    }

    public var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .timeZones: return "globe.americas"
        case .menuBar: return "menubar.rectangle"
        case .details: return "list.bullet.rectangle.portrait"
        case .calendar: return "calendar"
        case .agents: return "sparkles.rectangle.stack"
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
        case .agents: return "Codex and Claude task awareness"
        case .weather: return "Weather synced with each clock"
        case .appearance: return "Popover mood and polish"
        }
    }
}

public struct AgentPulseSettingsPane: View {
    @ObservedObject public var agentStore: AgentActivityStore
    @ObservedObject public var integrationManager: AgentIntegrationManager
    @State private var iconImportError: String?

    public init(agentStore: AgentActivityStore, integrationManager: AgentIntegrationManager) {
        self.agentStore = agentStore
        self.integrationManager = integrationManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            stickyPreview

            Divider().opacity(0.55)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    MenuBarSettingsCard(
                        icon: "sparkles.rectangle.stack",
                        title: "Agent Pulse",
                        subtitle: "Private, local task awareness for Codex and Claude."
                    ) {
                        VStack(spacing: 0) {
                            MenuBarToggleRow(
                                title: "Enable Agent Pulse",
                                subtitle: "Track provider, project folder, state, and timing metadata locally.",
                                systemImage: "power",
                                isOn: $agentStore.isEnabled
                            )
                            MenuBarSettingsDivider()
                            MenuBarToggleRow(
                                title: "Show task details in popover",
                                subtitle: "Include up to three active or unread tasks when you open Orpyt.",
                                systemImage: "rectangle.bottomhalf.inset.filled",
                                isOn: $agentStore.showTaskDetailsInPopover
                            )
                            .disabled(!agentStore.isEnabled)
                        }
                    }

                    MenuBarSettingsCard(
                        icon: "bell.badge",
                        title: "Notifications",
                        subtitle: "Choose which task transitions should interrupt you."
                    ) {
                        VStack(spacing: 0) {
                            MenuBarToggleRow(
                                title: "Attention alerts",
                                subtitle: "Notify when an agent needs a decision or input.",
                                systemImage: "exclamationmark.bubble",
                                isOn: $agentStore.attentionNotificationsEnabled
                            )
                            MenuBarSettingsDivider()
                            MenuBarToggleRow(
                                title: "Completion alerts",
                                subtitle: "Notify when an agent finishes a task.",
                                systemImage: "checkmark.circle",
                                isOn: $agentStore.completionNotificationsEnabled
                            )
                        }
                        .disabled(!agentStore.isEnabled)
                    }

                    ForEach(AgentProvider.allCases) { provider in
                        integrationCard(provider)
                    }

                    MenuBarSettingsCard(
                        icon: "paintpalette",
                        title: "Indicator Appearance",
                        subtitle: "Match each menu-bar state to an icon you can recognize at a glance."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(AgentIndicatorAppearanceStatus.allCases) { status in
                                indicatorAppearanceRow(status)
                                if status != AgentIndicatorAppearanceStatus.allCases.last {
                                    MenuBarSettingsDivider()
                                }
                            }
                            Text("Previews disappear automatically after eight seconds and are never restored on relaunch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!agentStore.isEnabled)
                    }

                    let historyActivities = agentStore.activities.filter { !$0.isIndicatorPreview }
                    if !historyActivities.isEmpty {
                        MenuBarSettingsCard(
                            icon: "clock.arrow.circlepath",
                            title: "Recent Activity",
                            subtitle: "Task state retained locally for up to seven days."
                        ) {
                            VStack(spacing: 0) {
                                ForEach(historyActivities.prefix(8)) { activity in
                                    HStack(spacing: 10) {
                                        Image(systemName: activity.provider.systemImage)
                                            .foregroundStyle(statusTint(activity.state))
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(activity.projectName).font(.callout.weight(.medium))
                                            Text("\(activity.sourceTitle) · \(activity.state.title)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(activity.updatedAt, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(minHeight: 44)
                                    if activity.id != historyActivities.prefix(8).last?.id {
                                        MenuBarSettingsDivider()
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button("Clear finished") { agentStore.clearFinished() }
                                        .controlSize(.small)
                                }
                                .padding(.top, 8)
                            }
                        }
                    }

                    Label("Prompts, responses, commands, transcript files, and source code are never included in Agent Pulse events.", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { integrationManager.refresh() }
        .onChange(of: agentStore.isEnabled) { enabled in
            guard enabled else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        .alert("Couldn’t use that icon", isPresented: Binding(
            get: { iconImportError != nil },
            set: { if !$0 { iconImportError = nil } }
        )) {
            Button("OK", role: .cancel) { iconImportError = nil }
        } message: {
            Text(iconImportError ?? "Choose a different image.")
        }
    }

    private var stickyPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Pulse Preview")
                        .font(.system(size: 13, weight: .semibold))
                    Text("A live summary of what Orpyt will show in the menu bar and popover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(agentPreviewTitle, systemImage: agentPreviewIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(agentPreviewColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.055)))
            }

            HStack(spacing: 12) {
                Image(systemName: agentPreviewIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(agentPreviewColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(agentPreviewColor.opacity(agentStore.isEnabled ? 0.12 : 0.05)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu-bar status stays compact")
                        .font(.system(size: 13, weight: .semibold))
                    Text(agentStore.showTaskDetailsInPopover
                         ? "Task details appear below your clocks when activity is available."
                         : "Task details stay hidden; indicators and notifications still work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(.bar)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 3)
    }

    private var agentPreviewTitle: String {
        guard agentStore.isEnabled else { return "Off" }
        switch agentStore.indicatorState {
        case .hidden: return "Idle"
        case .running: return "Running"
        case .attention: return "Needs attention"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var agentPreviewIcon: String {
        guard agentStore.isEnabled else { return "pause.circle" }
        switch agentStore.indicatorState {
        case .hidden: return "moon.zzz"
        case .running: return agentStore.indicatorIcon(for: .running)
        case .attention: return agentStore.indicatorIcon(for: .attention)
        case .completed: return agentStore.indicatorIcon(for: .completed)
        case .failed: return agentStore.indicatorIcon(for: .failed)
        }
    }

    private var agentPreviewColor: Color {
        guard agentStore.isEnabled else { return .secondary }
        switch agentStore.indicatorState {
        case .hidden: return .secondary
        case .running: return .purple
        case .attention: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    @ViewBuilder
    private func integrationCard(_ provider: AgentProvider) -> some View {
        let state = integrationManager.states[provider] ?? .notInstalled
        MenuBarSettingsCard(
            icon: provider.systemImage,
            title: provider == .codex ? "Codex CLI & Desktop" : provider.title,
            subtitle: "Connect Orpyt to receive local task-state events."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(state.title, systemImage: statusSymbol(state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(state))
                    Spacer()
                }
                Text(integrationManager.configPath(for: provider))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if provider == .codex, state == .installed || state == .receivingEvents {
                    Text("In Codex CLI, open /hooks and trust the Orpyt definitions once. The same user-level hooks cover supported local Codex/ChatGPT desktop tasks.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if case let .malformedConfiguration(message) = state {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                if integrationManager.lastErrorProvider == provider,
                   let error = integrationManager.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if !integrationManager.supportsAutomaticSetup {
                    Text("The App Store sandbox cannot edit this hidden configuration file. Copy the configuration, add it at the path above, then restart the agent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if integrationManager.supportsAutomaticSetup {
                        Button(state == .notInstalled ? "Install integration" : "Reinstall") {
                            agentStore.isEnabled = true
                            _ = integrationManager.install(provider)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Copy manual configuration") {
                            copyConfiguration(for: provider)
                        }
                    } else {
                        Button("Copy configuration") {
                            copyConfiguration(for: provider)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if integrationManager.supportsAutomaticSetup, state != .notInstalled {
                        Button("Uninstall", role: .destructive) { _ = integrationManager.uninstall(provider) }
                    }
                }
            }
        }
    }

    private func copyConfiguration(for provider: AgentProvider) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(integrationManager.manualConfiguration(for: provider), forType: .string)
        agentStore.isEnabled = true
    }

    private func statusTint(_ state: AgentActivityState) -> Color {
        switch state {
        case .running: return .purple
        case .needsAttention: return .orange
        case .completed: return .green
        case .failed: return .red
        case .stale: return .secondary
        }
    }

    private func indicatorAppearanceRow(_ status: AgentIndicatorAppearanceStatus) -> some View {
        let hasCustomIcon = agentStore.customIndicatorIconFiles[status] != nil
        return HStack(spacing: 12) {
            Text(status.title)
                .font(.callout.weight(.medium))
                .frame(width: 105, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(status.iconOptions, id: \.self) { icon in
                    Button {
                        agentStore.setIndicatorIcon(icon, for: status)
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(!hasCustomIcon && agentStore.indicatorIcon(for: status) == icon ? statusTint(status) : Color.secondary)
                            .frame(width: 28, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(!hasCustomIcon && agentStore.indicatorIcon(for: status) == icon ? statusTint(status).opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(!hasCustomIcon && agentStore.indicatorIcon(for: status) == icon ? statusTint(status).opacity(0.6) : Color.secondary.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Use \(icon) for \(status.title.lowercased())")
                }
            }

            if let customImage = agentStore.customIndicatorImage(for: status) {
                Image(nsImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .padding(2)
                    .background(statusTint(status).opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(statusTint(status).opacity(0.7)))
                    .help("Custom icon")
            }

            Spacer()
            Button(hasCustomIcon ? "Replace…" : "Upload…") {
                importCustomIcon(for: status)
            }
            .buttonStyle(.borderless)
            if hasCustomIcon {
                Button("Remove") {
                    agentStore.removeCustomIndicatorIcon(for: status)
                }
                .buttonStyle(.borderless)
            }
            Button("Preview") {
                agentStore.isEnabled = true
                agentStore.simulate(status.eventKind)
            }
            .buttonStyle(.bordered)
        }
    }

    private func importCustomIcon(for status: AgentIndicatorAppearanceStatus) {
        let panel = NSOpenPanel()
        panel.title = "Choose an icon for \(status.title)"
        panel.prompt = "Use Icon"
        panel.message = "PNG with a transparent background works best. Orpyt stores a private, normalized copy."
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try agentStore.importCustomIndicatorIcon(from: url, for: status)
            agentStore.isEnabled = true
            agentStore.simulate(status.eventKind)
        } catch {
            iconImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func statusTint(_ status: AgentIndicatorAppearanceStatus) -> Color {
        switch status {
        case .running: return .purple
        case .attention: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func statusSymbol(_ state: AgentIntegrationState) -> String {
        switch state {
        case .notInstalled: return "circle"
        case .manualSetupRequired: return "doc.on.clipboard"
        case .installed: return "checkmark.circle"
        case .receivingEvents: return "checkmark.circle.fill"
        case .malformedConfiguration: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ state: AgentIntegrationState) -> Color {
        switch state {
        case .notInstalled: return .secondary
        case .manualSetupRequired: return .blue
        case .installed: return .orange
        case .receivingEvents: return .green
        case .malformedConfiguration: return .red
        }
    }
}


public struct SettingsOverviewPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var weatherStore: WeatherStore
    @ObservedObject public var calendarStore: CalendarStore
    @ObservedObject public var subscriptionStore: SubscriptionStore
    public let onCheckForUpdates: () -> Void
    public let onTestReviewPrompt: () -> Void
    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1.0)) { context in
                overviewContent(now: context.date)
                    .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $subscriptionStore.showProSheet) {
            SubscriptionPane(subscriptionStore: subscriptionStore)
                .frame(width: 460, height: 560)
        }
    }

    private func overviewContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            OverviewHeroHeader(settings: settings, subscriptionStore: subscriptionStore, onCheckForUpdates: onCheckForUpdates, onTestReviewPrompt: onTestReviewPrompt)

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

            #if DEBUG
            WelcomePeriodDebugPanel(welcomeStore: WelcomePeriodStore.shared)
            #endif
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
                value: settings.effectiveWeatherEnabled
                    ? (liveWeatherCount > 0 ? "\(liveWeatherCount)/2 Live" : "Loading")
                    : (subscriptionStore.hasAccess(to: .weather) ? "Off" : "Pro Locked"),
                caption: settings.effectiveWeatherEnabled ? "Graceful fallback enabled" : (subscriptionStore.hasAccess(to: .weather) ? "Chronos-only mode" : "Unlock live weather in Orpyt Pro")
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
                value: settings.effectiveCalendarEnabled ? calendarMetricTitle : (subscriptionStore.hasAccess(to: .calendar) ? "Off" : "Pro Locked"),
                caption: settings.effectiveCalendarEnabled ? calendarMetricCaption : (subscriptionStore.hasAccess(to: .calendar) ? "Read-only meeting context" : "Unlock next meeting context in Orpyt Pro")
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
            return snapshot?.nextMeeting == nil ? "No Events" : "Live"
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
            return snapshot?.nextMeeting?.title ?? "Nothing in the next 24 hours"
        case let .failed(message):
            return message
        }
    }
}

#if DEBUG
public struct WelcomePeriodDebugPanel: View {
    @ObservedObject public var welcomeStore: WelcomePeriodStore
    @State private var flushed = false
    @State private var subscriptionReset = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "ant.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("DEBUG — Welcome Period")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Reset Day") {
                    welcomeStore.debugSetDay(nil)
                    flushed = false
                }
                .font(.system(size: 10))
                .controlSize(.mini)

                Button(subscriptionReset ? "Sub Reset ✓" : "Reset Sub") {
                    let defaults = UserDefaults.standard
                    let subKeys = ["subscription.entitlementState", "subscription.activePlanID",
                                   "subscription.renewalDate", "subscription.expirationDate",
                                   "subscription.willAutoRenew", "subscription.statusMessage"]
                    subKeys.forEach { defaults.removeObject(forKey: $0) }
                    defaults.synchronize()
                    Task { await SubscriptionStore.shared.refreshEntitlements() }
                    subscriptionReset = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { subscriptionReset = false }
                }
                .font(.system(size: 10))
                .controlSize(.mini)
                .foregroundStyle(subscriptionReset ? .green : .blue)

                Button(flushed ? "Flushed ✓" : "Flush All Data") {
                    let domain = Bundle.main.bundleIdentifier ?? "com.orpyt.app"
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    UserDefaults.standard.removePersistentDomain(forName: "com.orpyt.clocks")
                    UserDefaults.standard.synchronize()
                    welcomeStore.debugSetDay(nil)
                    flushed = true
                }
                .font(.system(size: 10))
                .controlSize(.mini)
                .foregroundStyle(flushed ? .green : .red)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([1, 3, 6, 10, 12, 13, 14, 16], id: \.self) { day in
                        Button(day == 16 ? "Day 16 (Expired)" : "Day \(day)") {
                            welcomeStore.debugSetDay(day)
                            flushed = false
                        }
                        .font(.system(size: 10, weight: .medium))
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .tint(day == 16 ? .red : .primary)
                    }
                }
            }

            Text("Remaining: \(welcomeStore.daysRemaining) · In period: \(welcomeStore.isInWelcomePeriod ? "yes" : "no") · Expired: \(welcomeStore.hasExpired ? "yes" : "no")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ProUpgradeBanner(
                subscriptionStore: SubscriptionStore.shared,
                welcomeStore: welcomeStore
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}
#endif

public struct ProUpgradeBanner: View {
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var welcomeStore: WelcomePeriodStore

    private var isVisible: Bool {
        guard subscriptionStore.shouldShowUpgradeActions else { return false }
        if subscriptionStore.entitlementState.hasProAccess { return false }
        return true
    }

    private var bannerText: String {
        if subscriptionStore.entitlementState == .trial {
            return "✦  Trial active — your card won't be charged yet. Cancel any time."
        }
        if subscriptionStore.entitlementState.hasProAccess {
            return "✦  Orpyt Pro is active — \(subscriptionStore.statusMessage)"
        }
        return "✦  \(welcomeStore.bannerMessage(yearlyPrice: subscriptionStore.yearlyMonthlyEquivalent))"
    }

    private var bannerColor: Color {
        switch welcomeStore.urgencyLevel {
        case .expired: return .red
        case .critical: return .orange
        case .warning: return Color(hex: "#E6A817")
        case .neutral: return Color.accentColor
        }
    }

    public var body: some View {
        if isVisible {
            Button(action: { subscriptionStore.showProSheet = true }) {
                HStack(spacing: 10) {
                    Text(bannerText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Subscribe →")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.18)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [bannerColor, bannerColor.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}

public struct OverviewHeroHeader: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var subscriptionStore: SubscriptionStore
    public let onCheckForUpdates: () -> Void
    public let onTestReviewPrompt: () -> Void

    private var systemZoneTitle: String {
        TimeZone.current.identifier.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? "Local"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
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

                if !appVersion.isEmpty {
                    Text("Version \(appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(ReviewPromptStore.suggestionsURL)
                } label: {
                    Label("Suggest a Feature", systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if subscriptionStore.supportsDirectUpdates {
                    Button {
                        onCheckForUpdates()
                    } label: {
                        Label("Check for Updates…", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: { subscriptionStore.showProSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: subscriptionStore.entitlementState.hasProAccess ? "crown.fill" : "crown")
                                .font(.system(size: 10, weight: .semibold))
                            Text(subscriptionStore.entitlementState.hasProAccess ? "Pro" : "Try Pro Free")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                #if DEBUG
                Button {
                    onTestReviewPrompt()
                } label: {
                    Label("Test Feedback Prompt", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                OverviewInlineTag(title: "Mode", value: settings.use24HourClock ? "24h" : "12h")
                OverviewInlineTag(title: "Weather", value: settings.effectiveWeatherEnabled ? "On" : (subscriptionStore.hasAccess(to: .weather) ? "Off" : "Pro"))
                OverviewInlineTag(title: "Plan", value: subscriptionStore.entitlementSummary)
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
                    value: settings.effectiveWeatherEnabled && settings.showWeatherInMenuBar ? "Weather" : settings.showStatusIcon ? "Ambient" : "Off"
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

public struct ProSuccessView: View {
    public let statusMessage: String
    @State private var appeared = false

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#5B8DEF"), Color(hex: "#9B6DFF")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)

            Text("Welcome to Orpyt Pro")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .opacity(appeared ? 1 : 0)

            Text(statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.vertical, 32)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                appeared = true
            }
        }
    }
}

public struct SubscriptionPane: View {
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var welcomeStore: WelcomePeriodStore = WelcomePeriodStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var justPurchased = false

    private var isSubscribed: Bool { subscriptionStore.entitlementState.hasProAccess }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#5B8DEF"), Color(hex: "#9B6DFF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        Text("Orpyt Pro")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    Text(isSubscribed
                         ? subscriptionStore.statusMessage
                         : welcomeStore.hasExpired
                             ? "You had 14 days free. Keep everything from \(subscriptionStore.yearlyMonthlyEquivalent)."
                             : "Everything you need, working across time zones.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .padding(16)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if subscriptionStore.supportsDirectUpdates {
                        SettingsCalloutCard(
                            title: "Source build",
                            subtitle: "This build includes the free feature set. Orpyt Pro is available through the App Store version."
                        )
                    } else if !isSubscribed {
                        // ── Pro features grid ─────────────────────────────
                        ProFeaturesGrid()

                        // ── 7-day trial card ──────────────────────────────
                        ProTrialCard()

                        // ── Plan cards ────────────────────────────────────
                        VStack(spacing: 10) {
                            ForEach(subscriptionStore.availablePlans.sorted { $0.isRecommended && !$1.isRecommended }) { plan in
                                SubscriptionPlanCard(
                                    plan: plan,
                                    yearlyMonthlyEquivalent: subscriptionStore.yearlyMonthlyEquivalent,
                                    isProcessing: subscriptionStore.isProcessingPurchase,
                                    isLoadingProducts: subscriptionStore.isLoadingProducts
                                ) {
                                    Task {
                                        await subscriptionStore.purchase(planID: plan.id)
                                        if subscriptionStore.entitlementState.hasProAccess {
                                            justPurchased = true
                                        }
                                    }
                                }
                            }
                        }

                        // ── Cancel reassurance ────────────────────────────
                        ProCancelCard()

                    } else {
                        ProSuccessView(statusMessage: subscriptionStore.statusMessage)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                    dismiss()
                                }
                            }
                    }

                    if let error = subscriptionStore.lastErrorMessage {
                        VStack(spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 14))
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button("Try Again") {
                                Task {
                                    await subscriptionStore.refreshEntitlements()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                    }

                    if subscriptionStore.isLoadingProducts {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading prices from App Store…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(20)
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Restore") { Task { await subscriptionStore.restorePurchases() } }
                        .disabled(subscriptionStore.isProcessingPurchase)
                    Button("Manage") { subscriptionStore.manageSubscriptions() }
                    Button("Redeem Code") { subscriptionStore.redeemOfferCode() }
                    Spacer()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                HStack(spacing: 16) {
                    Button("Privacy Policy") {
                        NSWorkspace.shared.open(URL(string: "https://aihtshamali.github.io/orpyt-world-time-made-simple/privacy/")!)
                    }
                    Button("Terms of Use") {
                        NSWorkspace.shared.open(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    Spacer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

public struct ProFeaturesGrid: View {
    private let row1: [(String, String, String)] = [
        ("cloud.sun.fill",         "Live Weather",        "Weather on every clock card"),
        ("calendar",               "Calendar Context",    "Next meeting in the popover"),
    ]
    private let row2: [(String, String, String)] = [
        ("clock.arrow.circlepath", "Time Scroller",       "Scrub forward & back across zones"),
        ("sparkles",               "Appearance",          "Custom themes and polish"),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's included")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(row1, id: \.0) { icon, title, subtitle in
                        ProFeatureCell(icon: icon, title: title, subtitle: subtitle)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(row2, id: \.0) { icon, title, subtitle in
                        ProFeatureCell(icon: icon, title: title, subtitle: subtitle)
                    }
                }
            }
        }
    }
}

public struct ProFeatureCell: View {
    let icon: String
    let title: String
    let subtitle: String

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

public struct ProTrialCard: View {
    public var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#5B8DEF"), Color(hex: "#9B6DFF")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                Text("7")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("7 days completely free")
                    .font(.system(size: 13, weight: .semibold))
                Text("Full Pro access from day one. Your card is only charged on day 8 — if you decide to stay.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: "#5B8DEF").opacity(0.08), Color(hex: "#9B6DFF").opacity(0.08)],
                    startPoint: .leading, endPoint: .trailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "#5B8DEF").opacity(0.2), lineWidth: 1)
        )
    }
}

public struct ProCancelCard: View {
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("Cancel any time — really.")
                    .font(.system(size: 12, weight: .semibold))
                Text("No forms, no calls, no emails. One tap in System Settings or your iPhone. Apple handles it instantly.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

public struct SubscriptionPlanCard: View {
    public let plan: SubscriptionPlanDescriptor
    public let yearlyMonthlyEquivalent: String
    public let isProcessing: Bool
    public let isLoadingProducts: Bool
    public let onSubscribe: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            if plan.isRecommended {
                HStack {
                    Spacer()
                    Text("MOST POPULAR")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .tracking(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [Color(hex: "#5B8DEF"), Color(hex: "#9B6DFF")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                        )
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, -4)
            }

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.isRecommended ? "Yearly" : "Monthly")
                        .font(.system(size: 15, weight: .semibold))
                    Text(plan.isRecommended
                         ? "Billed annually · best value"
                         : "Billed monthly · cancel any time")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.priceText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if plan.isRecommended {
                        Text(yearlyMonthlyEquivalent + " · billed annually")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Button(action: onSubscribe) {
                HStack(spacing: 6) {
                    if isProcessing || isLoadingProducts {
                        ProgressView().controlSize(.small)
                    }
                    Text(isLoadingProducts
                         ? "Loading…"
                         : plan.isRecommended ? "Start Free Trial — Yearly" : "Start Free Trial — Monthly")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isProcessing || isLoadingProducts)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    plan.isRecommended
                        ? LinearGradient(colors: [Color(hex: "#5B8DEF").opacity(0.5), Color(hex: "#9B6DFF").opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.black.opacity(0.06), Color.black.opacity(0.06)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1.2
                )
        )
    }
}

public struct SubscriptionHighlightCard: View {
    public let feature: OrpytProFeature

    public var body: some View {
        SettingsCalloutCard(
            title: "Unlock \(feature.title)",
            subtitle: feature.summary
        )
    }
}

public struct SettingsCalloutCard: View {
    public let title: String
    public let subtitle: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 0.8)
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
            return settings.effectiveWeatherEnabled ? message : ambientSummary
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
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "clock.badge.checkmark.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(.tint)
            .background(Color(nsColor: .controlBackgroundColor))
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
                #if os(macOS)
                if hovering && !isHovered {
                    NSCursor.pointingHand.push()
                } else if !hovering && isHovered {
                    NSCursor.pop()
                }
                #endif

                isHovered = hovering
            }
            .onDisappear {
                #if os(macOS)
                if isHovered {
                    NSCursor.pop()
                }
                #endif
                isHovered = false
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
        image(named: ["logo.png", "Orpyt.icns"])
    }

    public static func brandImage() -> NSImage? {
        image(named: ["logo.png", "orpyt-logo.png"])
    }

    private static func image(named fileNames: [String]) -> NSImage? {
        for fileName in fileNames {
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Picker("", selection: $selectedSlot) {
                    Text("Primary").tag(ClockSlot.primary)
                    Text("Secondary").tag(ClockSlot.secondary)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                InlineTimeZoneEditorView(
                    title: selectedSlot == .primary ? "Primary Clock" : "Secondary Clock",
                    selectedTimeZoneID: selectedSlot == .primary ? $settings.primaryTimeZoneID : $settings.secondaryTimeZoneID,
                    customLabel: selectedSlot == .primary ? $settings.primaryCustomLabel : $settings.secondaryCustomLabel,
                    searchText: selectedSlot == .primary ? $primarySearchText : $secondarySearchText,
                    onDone: {}
                )

                Button("Swap Primary ↔ Secondary") {
                    settings.swapTimeZones()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(24)
        }
    }
}

#if os(macOS)
public struct MenuBarPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var navigationStore: SettingsNavigationStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    @State private var draggingLayoutItem: MenuBarLayoutItem?

    private var hasPowerMenuBarAccess: Bool {
        subscriptionStore.hasAccess(to: .appearance)
    }

    private var iconMode: Binding<MenuBarIconMode> {
        Binding(
            get: {
                if settings.effectiveWeatherEnabled && settings.showWeatherInMenuBar { return .weather }
                if settings.showStatusIcon { return .ambient }
                return .none
            },
            set: { newValue in
                switch newValue {
                case .none:
                    settings.setMenuBarVisibility(icon: false, weather: false)
                case .ambient:
                    settings.setMenuBarVisibility(icon: true, weather: false)
                case .weather:
                    guard settings.effectiveWeatherEnabled else {
                        settings.setMenuBarVisibility(icon: false, weather: false)
                        return
                    }
                    settings.setMenuBarVisibility(icon: false, weather: true)
                }
            }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            stickyPreview

            Divider().opacity(0.55)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if !hasPowerMenuBarAccess {
                        powerMenuBarUpsell
                    }

                    MenuBarSettingsCard(
                        icon: "rectangle.3.group",
                        title: "Layout",
                        subtitle: "Arrange Orpyt's menu bar modules in the order you scan them."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(spacing: 8) {
                                ForEach(settings.menuBarLayoutItems) { item in
                                    MenuBarModuleDragRow(
                                        item: item,
                                        isDragging: draggingLayoutItem == item
                                    )
                                    .onDrag {
                                        draggingLayoutItem = item
                                        return NSItemProvider(object: item.rawValue as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: MenuBarLayoutDropDelegate(
                                            targetItem: item,
                                            draggingItem: $draggingLayoutItem,
                                            settings: settings
                                        )
                                    )
                                }
                            }
                            .disabled(!hasPowerMenuBarAccess)

                            Text("Drag rows to reorder. The preview above updates as the order changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    MenuBarSettingsCard(
                        icon: "clock",
                        title: "Time Zones",
                        subtitle: "Keep clock visibility and per-city time format in one place."
                    ) {
                        VStack(spacing: 0) {
                            MenuBarClockPowerRow(
                                title: "Primary",
                                color: .purple,
                                timeZoneID: settings.primaryTimeZoneID,
                                isVisible: $settings.showPrimaryClock,
                                formatOverride: $settings.primaryClockFormatOverride,
                                isAdvancedLocked: !hasPowerMenuBarAccess
                            )
                            MenuBarSettingsDivider()
                            MenuBarClockPowerRow(
                                title: "Secondary",
                                color: .blue,
                                timeZoneID: settings.secondaryTimeZoneID,
                                isVisible: $settings.showSecondaryClock,
                                formatOverride: $settings.secondaryClockFormatOverride,
                                isAdvancedLocked: !hasPowerMenuBarAccess
                            )
                        }
                    }

                    MenuBarSettingsCard(
                        icon: "slider.horizontal.3",
                        title: "Display",
                        subtitle: "Tune the compact text, precision, icon style, and spacing."
                    ) {
                        VStack(spacing: 0) {
                            MenuBarToggleRow(
                                title: "Zone labels",
                                subtitle: "Show short city labels beside times.",
                                systemImage: "textformat.size",
                                isOn: $settings.showZoneLabelInMenuBar
                            )
                            MenuBarSettingsDivider()
                            MenuBarToggleRow(
                                title: "24-hour time",
                                subtitle: "Default format for clocks without an override.",
                                systemImage: "24.square",
                                isOn: $settings.use24HourClock
                            )
                            MenuBarSettingsDivider()
                            MenuBarToggleRow(
                                title: "Seconds",
                                subtitle: "Refresh the menu bar every second.",
                                systemImage: "timer",
                                isOn: $settings.showSeconds
                            )
                            MenuBarSettingsDivider()
                            MenuBarPickerRow(
                                title: "Icon mode",
                                subtitle: iconModeHelpText,
                                systemImage: "cloud.sun",
                                controlWidth: 158
                            ) {
                                Picker("", selection: iconMode) {
                                    ForEach(MenuBarIconMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .labelsHidden()
                            }
                            MenuBarSettingsDivider()
                            MenuBarPickerRow(
                                title: "Separator",
                                subtitle: "Choose how clocks are divided.",
                                systemImage: "alternatingcurrent",
                                controlWidth: 158
                            ) {
                                Picker("", selection: $settings.menuBarSeparatorStyle) {
                                    ForEach(MenuBarSeparatorStyle.allCases) { style in
                                        Text(style.title).tag(style)
                                    }
                                }
                                .labelsHidden()
                                .disabled(!hasPowerMenuBarAccess)
                            }
                            MenuBarSettingsDivider()
                            MenuBarPickerRow(
                                title: "Spacing",
                                subtitle: "Keep the bar compact or give items more air.",
                                systemImage: "arrow.left.and.right",
                                controlWidth: 158
                            ) {
                                Picker("", selection: $settings.menuBarSpacing) {
                                    ForEach(MenuBarSpacing.allCases) { spacing in
                                        Text(spacing.title).tag(spacing)
                                    }
                                }
                                .labelsHidden()
                                .disabled(!hasPowerMenuBarAccess)
                            }
                        }
                    }

                    MenuBarSettingsCard(
                        icon: "calendar.badge.clock",
                        title: "Calendar Indicator",
                        subtitle: "Meeting alert details stay in Calendar so there is only one source of truth."
                    ) {
                        HStack(spacing: 12) {
                            Label(settings.meetingIndicatorStyle.title, systemImage: "bell.badge")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Click opens \(settings.meetingIndicatorClickAction.title.lowercased()).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Configure") {
                                navigationStore.selectedPane = .calendar
                            }
                            .controlSize(.small)
                        }
                    }

                    MenuBarSettingsCard(
                        icon: "arrow.clockwise",
                        title: "Refresh",
                        subtitle: "Choose how often Orpyt checks weather and calendar updates."
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            MenuBarPickerRow(
                                title: "Automatic updates",
                                subtitle: refreshHelpText,
                                systemImage: "bolt.horizontal.circle",
                                controlWidth: 174
                            ) {
                                Picker("", selection: $settings.refreshIntervalPreference) {
                                    ForEach(RefreshIntervalPreference.allCases) { interval in
                                        Text(interval.title).tag(interval)
                                    }
                                }
                                .labelsHidden()
                                .disabled(!hasPowerMenuBarAccess)
                            }
                        }
                    }

                    MenuBarSettingsCard(
                        icon: "power",
                        title: "System",
                        subtitle: "Keep Orpyt ready when your Mac starts."
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            MenuBarToggleRow(
                                title: "Launch at Login",
                                subtitle: launchAtLogin.statusMessage,
                                systemImage: "macwindow.on.rectangle",
                                isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })
                            )
                            if let errorMessage = launchAtLogin.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 32)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { launchAtLogin.refresh() }
    }

    private var stickyPreview: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: settings.showSeconds ? 1.0 : 60.0)) { context in
            PowerMenuBarPreview(
                settings: settings,
                now: context.date,
                isLocked: !hasPowerMenuBarAccess,
                onMeetingIndicatorClick: {
                    navigationStore.selectedPane = .calendar
                }
            )
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .background(.bar)
            .shadow(color: .black.opacity(0.10), radius: 12, y: 3)
        }
    }

    private var powerMenuBarUpsell: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Power Menu Bar is part of Orpyt Pro.")
                    .fontWeight(.semibold)
                Text("Basic visibility, labels, default time format, and icon mode stay available. Pro unlocks ordering, spacing, per-clock format, and refresh controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Unlock Pro") {
                subscriptionStore.focus(on: .appearance)
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
        )
    }

    private var iconModeHelpText: String {
        if !subscriptionStore.hasAccess(to: .weather) {
            return "Weather icons unlock with Orpyt Pro."
        }

        if !settings.enableWeather {
            return "Turn on live weather in Weather to use weather icons."
        }

        return "Choose no icon, an ambient icon, or live weather."
    }

    private var refreshHelpText: String {
        switch settings.refreshIntervalPreference {
        case .automatic:
            return "Weather every 15 minutes, calendar every 5 minutes."
        default:
            return "Use a single cadence for weather and calendar checks."
        }
    }

}

private struct PowerMenuBarPreview: View {
    @ObservedObject var settings: ClockSettingsStore
    @ObservedObject private var agentStore = AgentActivityStore.shared
    let now: Date
    let isLocked: Bool
    let onMeetingIndicatorClick: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu Bar Preview")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Live preview of the Orpyt-owned items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(isLocked ? "Pro layout locked" : "Live", systemImage: isLocked ? "lock.fill" : "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isLocked ? Color.accentColor : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.055)))
            }

            HStack(spacing: 0) {
                ForEach(Array(visiblePreviewItems.enumerated()), id: \.element) { index, item in
                    previewItem(for: item)
                    if index < visiblePreviewItems.count - 1 {
                        Text(settings.effectiveMenuBarSeparatorStyle.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(.horizontal, settings.effectiveMenuBarSpacing == .comfortable ? 8 : 5)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(menuBarCapsuleBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.24), lineWidth: 1)
            )
            .shadow(color: Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 2)
            .opacity(isLocked ? 0.78 : 1)
        }
    }

    private var menuBarCapsuleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.white.opacity(0.10), Color.white.opacity(0.045)]
                        : [Color.white.opacity(0.76), Color(nsColor: .controlBackgroundColor).opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var visiblePreviewItems: [MenuBarLayoutItem] {
        settings.menuBarLayoutItems.filter { item in
            switch item {
            case .agentIndicator:
                // The layout preview represents configured positions, not only
                // items that happen to be live at this instant. Keep the slot
                // visible here while the real menu bar may still hide it at idle.
                return true
            case .meetingIndicator:
                return settings.meetingIndicatorStyle != .off
            case .primaryClock:
                return settings.showPrimaryClock
            case .secondaryClock:
                return settings.showSecondaryClock
            }
        }
    }

    @ViewBuilder
    private func previewItem(for item: MenuBarLayoutItem) -> some View {
        switch item {
        case .agentIndicator:
            Image(systemName: agentPreviewIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agentPreviewColor)
                .help("Agent Pulse: \(agentPreviewTitle)")
        case .meetingIndicator:
            Button(action: onMeetingIndicatorClick) {
                Text("Now")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: .red.opacity(0.16), radius: 5, y: 1)
            }
            .buttonStyle(.plain)
            .help("Open meeting alert settings")
        case .primaryClock:
            previewClock(
                accent: .purple,
                icon: settings.showWeatherInMenuBar ? "cloud.sun.fill" : "clock",
                text: clockPreview(slot: .primary)
            )
        case .secondaryClock:
            previewClock(
                accent: .blue,
                icon: settings.showWeatherInMenuBar ? "cloud.fill" : "clock",
                text: clockPreview(slot: .secondary)
            )
        }
    }

    private var agentPreviewTitle: String {
        switch agentStore.indicatorState {
        case .hidden: return "Idle"
        case .running: return "Running"
        case .attention: return "Needs attention"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var agentPreviewIcon: String {
        switch agentStore.indicatorState {
        case .hidden: return "moon.zzz"
        case .running: return agentStore.indicatorIcon(for: .running)
        case .attention: return agentStore.indicatorIcon(for: .attention)
        case .completed: return agentStore.indicatorIcon(for: .completed)
        case .failed: return agentStore.indicatorIcon(for: .failed)
        }
    }

    private var agentPreviewColor: Color {
        switch agentStore.indicatorState {
        case .hidden: return .secondary
        case .running: return .purple
        case .attention: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func previewClock(accent: Color, icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.055)))
    }

    private func clockPreview(slot: ClockSlot) -> String {
        let timeZoneID = slot == .primary ? settings.primaryTimeZoneID : settings.secondaryTimeZoneID
        let customLabel = slot == .primary ? settings.primaryCustomLabel : settings.secondaryCustomLabel
        let formatOverride = slot == .primary ? settings.primaryClockFormatOverride : settings.secondaryClockFormatOverride
        let label = settings.displayLabel(for: timeZoneID, customLabel: customLabel)
        let time = ClockFormatter.timeText(
            for: now,
            timeZoneID: timeZoneID,
            settings: settings,
            formatOverride: formatOverride
        )
        return settings.showZoneLabelInMenuBar ? "\(label) \(time)" : time
    }
}

private struct MenuBarModuleDragRow: View {
    let item: MenuBarLayoutItem
    let isDragging: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Image(systemName: item.systemImageName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.11))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .fontWeight(.medium)
                Text(item.compactTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isDragging ? 0.10 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(isDragging ? 0.13 : 0.07), lineWidth: 1)
        )
    }
}

private struct MenuBarLayoutDropDelegate: DropDelegate {
    let targetItem: MenuBarLayoutItem
    @Binding var draggingItem: MenuBarLayoutItem?
    let settings: ClockSettingsStore

    func dropEntered(info: DropInfo) {
        guard let draggingItem,
              draggingItem != targetItem,
              let fromIndex = settings.menuBarLayoutItems.firstIndex(of: draggingItem),
              let toIndex = settings.menuBarLayoutItems.firstIndex(of: targetItem) else {
            return
        }

        var items = settings.menuBarLayoutItems
        withAnimation(.snappy(duration: 0.18)) {
            items.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
            settings.setMenuBarLayoutItems(items)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if info.location == .zero {
            draggingItem = nil
        }
    }
}

private struct MenuBarClockPowerRow: View {
    let title: String
    let color: Color
    let timeZoneID: String
    @Binding var isVisible: Bool
    @Binding var formatOverride: MenuBarClockFormatOverride
    let isAdvancedLocked: Bool

    private var locationTitle: String {
        TimeZoneCatalog.option(for: timeZoneID)?.displayName ?? timeZoneID
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(locationTitle)
                    .fontWeight(.medium)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $formatOverride) {
                ForEach(MenuBarClockFormatOverride.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .labelsHidden()
            .frame(width: 142)
            .disabled(isAdvancedLocked)
            Toggle("", isOn: $isVisible)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

private struct MenuBarSettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            content
                .padding(.leading, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct MenuBarToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

private struct MenuBarPickerRow<Control: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let controlWidth: CGFloat
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 16)
            control
                .frame(width: controlWidth)
        }
        .padding(.vertical, 10)
    }
}

private struct MenuBarSettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 32)
    }
}

private enum MenuBarIconMode: String, CaseIterable, Identifiable {
    case none
    case ambient
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .ambient:
            return "Ambient"
        case .weather:
            return "Weather"
        }
    }
}

#endif

public struct DashboardDisplayPane: View {
    @ObservedObject public var settings: ClockSettingsStore

    public var body: some View {
        Form {
            Section("Visible Clocks") {
                Toggle(isOn: $settings.showPrimaryClock) {
                    Text("Show primary clock")
                    Text("Keep the first city visible on the dashboard.")
                }
                Toggle(isOn: $settings.showSecondaryClock) {
                    Text("Show secondary clock")
                    Text("Keep the second city visible on the dashboard.")
                }
            }

            Section("Dashboard Format") {
                Toggle(isOn: $settings.showZoneLabelInMenuBar) {
                    Text("Show zone labels")
                    Text("Display short city labels beside compact clock previews.")
                }
                Toggle(isOn: $settings.use24HourClock) {
                    Text("Use 24-hour time")
                    Text("Switch dashboard clocks between 12-hour and 24-hour formats.")
                }
                Toggle(isOn: $settings.showSeconds) {
                    Text("Show seconds")
                    Text("Update the dashboard every second.")
                }
            }

            Section("Time Scroller") {
                Toggle(isOn: $settings.muteScrollerSound) {
                    Text("Mute scroller feedback")
                    Text("Turn off touch feedback while scrubbing time.")
                }
            }
        }
        .formStyle(.grouped)
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
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var navigationStore: SettingsNavigationStore

    public var body: some View {
        Form {
            Section("Next Meeting") {
                if subscriptionStore.hasAccess(to: .calendar) {
                    Toggle(isOn: $settings.showCalendarEvents) {
                        Text("Show next meeting")
                        Text("Read your next calendar event and show it in the popover.")
                    }
                } else {
                    ProLockedSettingsRow(
                        feature: .calendar,
                        title: "Show next meeting",
                        subtitle: "Read your next calendar event and show it in the popover.",
                        buttonTitle: "Unlock Orpyt Pro"
                    ) {
                        subscriptionStore.focus(on: .calendar)
                    }
                }
                if case let .loaded(snapshot) = calendarStore.state, let nextMeeting = snapshot?.nextMeeting {
                    LabeledContent("Next event") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(nextMeeting.title).fontWeight(.medium)
                            Text(nextMeeting.calendarName).foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Meeting time zone", selection: $settings.meetingTimeZonePreference) {
                    ForEach(MeetingTimeZonePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Text("Mac Time Zone keeps meetings tied to where you are, independent of the primary and secondary clocks.")
                    .foregroundStyle(.secondary)
                Text(statusDescription)
                    .foregroundStyle(.secondary)
            }
            Section("Meeting Alerts") {
                Picker("Indicator style", selection: $settings.meetingIndicatorStyle) {
                    ForEach(MeetingIndicatorStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("Hover behavior", selection: $settings.meetingIndicatorHoverBehavior) {
                    ForEach(MeetingIndicatorHoverBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }

                Picker("Click action", selection: $settings.meetingIndicatorClickAction) {
                    ForEach(MeetingIndicatorClickAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }

                Picker("Warning timing", selection: $settings.meetingWarningMode) {
                    ForEach(MeetingWarningMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.meetingWarningMode == .preset {
                    Picker("Preset", selection: $settings.meetingWarningPreset) {
                        ForEach(MeetingWarningPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                } else {
                    Stepper(value: $settings.meetingEarlyWarningMinutes, in: 2...60) {
                        LabeledContent("Early warning") {
                            Text("\(settings.meetingEarlyWarningMinutes) min")
                        }
                    }

                    Stepper(value: $settings.meetingCriticalWarningMinutes, in: 1...59) {
                        LabeledContent("Critical warning") {
                            Text("\(settings.meetingCriticalWarningMinutes) min")
                        }
                    }
                }

                Text("The stable default keeps the clock still and puts meeting details in the tooltip. Preview Popover shows the title near the menu bar without moving the clocks.")
                    .foregroundStyle(.secondary)
            }
            Section("Today’s Plan") {
                Text("Use the 3-dot menu on the next meeting card to reveal the rest of today’s meetings inline or jump into Calendar.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(subscriptionStore.hasAccess(to: .calendar)
                     ? "Orpyt never creates or edits events. Permission is requested only after you turn this on."
                     : "Calendar context is part of Orpyt Pro. When you unlock it, Orpyt still only reads upcoming events and never edits them.")
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
        case let .loaded(snapshot):
            if let nextMeeting = snapshot?.nextMeeting {
                return "Next meeting in the popover: \(nextMeeting.title)"
            }
            return "No upcoming events in the next 24 hours."
        case let .failed(message): return message
        }
    }
}

public struct WeatherPane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var navigationStore: SettingsNavigationStore

    public var body: some View {
        Form {
            Section("Live Weather") {
                if subscriptionStore.hasAccess(to: .weather) {
                    Toggle(isOn: $settings.enableWeather) {
                        Text("Enable live weather")
                        Text("Attach live weather to each clock.")
                    }
                } else {
                    ProLockedSettingsRow(
                        feature: .weather,
                        title: "Enable live weather",
                        subtitle: "Attach live weather to each clock.",
                        buttonTitle: "Unlock Orpyt Pro"
                    ) {
                        subscriptionStore.focus(on: .weather)
                    }
                }
                Text("Weather follows each selected clock city automatically.")
                    .foregroundStyle(.secondary)
            }

            Section("Cards") {
                Toggle(isOn: $settings.showWeatherLocation) {
                    Text("Show location in cards")
                    Text("Display the resolved city below the condition.")
                }
                .disabled(!settings.effectiveWeatherEnabled)
                Toggle(isOn: $settings.showFeelsLikeTemperature) {
                    Text("Show feels like temperature")
                    Text("Include apparent temperature in the card details.")
                }
                .disabled(!settings.effectiveWeatherEnabled)
            }

            Section("Menu Bar") {
                Text("Menu bar icon mode now lives in the Menu Bar pane so all top-bar controls stay together.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

public struct AppearancePane: View {
    @ObservedObject public var settings: ClockSettingsStore
    @ObservedObject public var subscriptionStore: SubscriptionStore
    @ObservedObject public var navigationStore: SettingsNavigationStore

    public var body: some View {
        Form {
            Section("Popover") {
                if subscriptionStore.hasAccess(to: .appearance) {
                    Picker("Appearance", selection: Binding(
                        get: { settings.appearanceMode },
                        set: { settings.appearanceMode = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } else {
                    ProLockedSettingsRow(
                        feature: .appearance,
                        title: "Custom appearance",
                        subtitle: "Choose light, dark, or system-controlled styling for the popover.",
                        buttonTitle: "Unlock Orpyt Pro"
                    ) {
                        subscriptionStore.focus(on: .appearance)
                    }
                }
                Text("This changes Orpyt's clock surface only. Settings follow the system appearance.")
                    .foregroundStyle(.secondary)
            }

            Section("Interaction") {
                Toggle(isOn: $settings.muteScrollerSound) {
                    Text("Mute scroller tick")
                    Text("Turn off the native tick sound while scrubbing time.")
                }
                .disabled(!subscriptionStore.hasAccess(to: .appearance))
            }
        }
        .formStyle(.grouped)
    }
}

public struct ProLockedSettingsRow: View {
    public let feature: OrpytProFeature
    public let title: String
    public let subtitle: String
    public let buttonTitle: String
    public let onTap: () -> Void

    public var body: some View {
        ZStack(alignment: .trailing) {
            // Real control — visible but blurred
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: feature.symbolName)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 4)
            .blur(radius: 2)
            .allowsHitTesting(false)

            // Crown lock badge
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Pro")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.13)))
            .foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}


#if os(macOS)
public final class OrpytSettingsWindow: NSWindow {
    override public func cancelOperation(_ sender: Any?) {
        close()
    }
}
#endif


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
