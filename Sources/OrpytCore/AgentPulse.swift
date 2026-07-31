import AppKit
import Combine
import Darwin
import Foundation

public enum AgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var systemImage: String {
        switch self {
        case .codex: return "terminal.fill"
        case .claude: return "sparkles"
        }
    }
}

public enum AgentEventKind: String, Codable, Sendable {
    case started
    case attention
    case resumed
    case completed
    case failed
    case ended
}

public enum AgentActivityState: String, Codable, Sendable {
    case running
    case needsAttention
    case completed
    case failed
    case stale

    public var title: String {
        switch self {
        case .running: return "Running"
        case .needsAttention: return "Needs attention"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .stale: return "No recent update"
        }
    }

    public var systemImage: String {
        switch self {
        case .running: return "circle.dotted"
        case .needsAttention: return "exclamationmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .stale: return "clock.badge.questionmark"
        }
    }
}

public struct AgentEventEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let installationToken: String
    public let provider: AgentProvider
    public let kind: AgentEventKind
    public let sourceEvent: String
    public let sessionID: String
    public let turnID: String?
    public let workingDirectory: String
    public let terminalProgram: String?
    public let timestamp: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        installationToken: String,
        provider: AgentProvider,
        kind: AgentEventKind,
        sourceEvent: String,
        sessionID: String,
        turnID: String? = nil,
        workingDirectory: String,
        terminalProgram: String? = nil,
        timestamp: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.installationToken = installationToken
        self.provider = provider
        self.kind = kind
        self.sourceEvent = sourceEvent
        self.sessionID = sessionID
        self.turnID = turnID
        self.workingDirectory = workingDirectory
        self.terminalProgram = terminalProgram
        self.timestamp = timestamp
    }
}

public struct AgentActivity: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: AgentProvider
    public let sessionID: String
    public let turnID: String?
    public let projectName: String
    public let workingDirectory: String
    public let terminalProgram: String?
    public var state: AgentActivityState
    public let startedAt: Date
    public var updatedAt: Date
    public var isUnread: Bool

    public init(
        id: String,
        provider: AgentProvider,
        sessionID: String,
        turnID: String?,
        projectName: String,
        workingDirectory: String,
        terminalProgram: String?,
        state: AgentActivityState,
        startedAt: Date,
        updatedAt: Date,
        isUnread: Bool
    ) {
        self.id = id
        self.provider = provider
        self.sessionID = sessionID
        self.turnID = turnID
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.terminalProgram = terminalProgram
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.isUnread = isUnread
    }

    public var sourceTitle: String {
        switch terminalProgram {
        case "com.openai.codex", "com.openai.chat": return "Codex Desktop"
        default: return provider.title
        }
    }

    public var originatesFromCodexDesktop: Bool {
        terminalProgram == "com.openai.codex" || terminalProgram == "com.openai.chat"
    }

    public var isIndicatorPreview: Bool {
        sessionID.hasPrefix("orpyt-test-") || sessionID.hasPrefix("orpyt-preview-")
    }
}

public struct AgentActivityTransition: Equatable, Sendable {
    public let activity: AgentActivity
    public let kind: AgentEventKind
    public let occurredAt: Date
}

public enum AgentIndicatorState: Equatable, Sendable {
    case hidden
    case running
    case attention
    case completed
    case failed
}

public enum AgentIndicatorAppearanceStatus: String, CaseIterable, Identifiable, Sendable {
    case running
    case attention
    case completed
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .running: return "Running"
        case .attention: return "Needs attention"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    public var eventKind: AgentEventKind {
        switch self {
        case .running: return .started
        case .attention: return .attention
        case .completed: return .completed
        case .failed: return .failed
        }
    }

    public var defaultIcon: String {
        switch self {
        case .running: return "cpu.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    public var iconOptions: [String] {
        switch self {
        case .running:
            return ["cpu.fill", "sparkles", "bolt.circle.fill", "gearshape.2.fill"]
        case .attention:
            return ["exclamationmark.circle.fill", "bell.badge.fill", "hand.raised.fill", "questionmark.circle.fill"]
        case .completed:
            return ["checkmark.circle.fill", "checkmark.seal.fill", "checkmark.square.fill", "flag.checkered"]
        case .failed:
            return ["xmark.circle.fill", "xmark.octagon.fill", "exclamationmark.triangle.fill", "exclamationmark.octagon.fill"]
        }
    }
}

public enum AgentIndicatorIconImportError: LocalizedError, Equatable {
    case fileTooLarge
    case unreadableImage
    case invalidDimensions
    case couldNotNormalize
    case couldNotStore

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "Choose an image smaller than 10 MB."
        case .unreadableImage: return "Orpyt could not read that image. Try PNG, JPEG, HEIC, or TIFF."
        case .invalidDimensions: return "Choose an image between 8 and 8,192 pixels on each side."
        case .couldNotNormalize: return "Orpyt could not prepare that image for the menu bar."
        case .couldNotStore: return "Orpyt could not save the custom icon in Application Support."
        }
    }
}

public enum AgentEventCodecError: Error, Equatable {
    case invalidURL
    case invalidVersion
    case oversizedPayload
    case invalidPayload
    case invalidToken
    case invalidTimestamp
    case invalidIdentifier
}

public enum AgentEventCodec {
    public static let scheme = "orpyt"
    public static let host = "agent-event"
    public static let maximumPayloadCharacters = 8_192

    public static func url(for envelope: AgentEventEnvelope) throws -> URL {
        let data = try JSONEncoder.agentPulse.encode(envelope)
        let payload = data.base64URLEncodedString()
        guard payload.count <= maximumPayloadCharacters else { throw AgentEventCodecError.oversizedPayload }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "v", value: String(AgentEventEnvelope.currentSchemaVersion)),
            URLQueryItem(name: "payload", value: payload),
        ]
        guard let url = components.url else { throw AgentEventCodecError.invalidURL }
        return url
    }

    public static func decode(
        _ url: URL,
        expectedToken: String,
        now: Date = Date()
    ) throws -> AgentEventEnvelope {
        guard url.scheme == scheme, url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AgentEventCodecError.invalidURL
        }
        let version = components.queryItems?.first(where: { $0.name == "v" })?.value
        guard version == String(AgentEventEnvelope.currentSchemaVersion) else {
            throw AgentEventCodecError.invalidVersion
        }
        guard let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value else {
            throw AgentEventCodecError.invalidPayload
        }
        guard payload.count <= maximumPayloadCharacters else { throw AgentEventCodecError.oversizedPayload }
        guard let data = Data(base64URLEncoded: payload),
              let envelope = try? JSONDecoder.agentPulse.decode(AgentEventEnvelope.self, from: data) else {
            throw AgentEventCodecError.invalidPayload
        }
        guard envelope.schemaVersion == AgentEventEnvelope.currentSchemaVersion else {
            throw AgentEventCodecError.invalidVersion
        }
        guard envelope.installationToken == expectedToken, !expectedToken.isEmpty else {
            throw AgentEventCodecError.invalidToken
        }
        guard abs(envelope.timestamp.timeIntervalSince(now)) <= 7 * 24 * 60 * 60 else {
            throw AgentEventCodecError.invalidTimestamp
        }
        guard !envelope.sessionID.isEmpty, envelope.sessionID.count <= 256,
              envelope.sourceEvent.count <= 128,
              envelope.workingDirectory.count <= 2_048 else {
            throw AgentEventCodecError.invalidIdentifier
        }
        return envelope
    }
}

@MainActor
public final class AgentActivityStore: ObservableObject {
    public static let shared = AgentActivityStore()

    @Published public var isEnabled: Bool { didSet { savePreferences() } }
    @Published public var showTaskDetailsInPopover: Bool { didSet { savePreferences() } }
    @Published public var attentionNotificationsEnabled: Bool { didSet { savePreferences() } }
    @Published public var completionNotificationsEnabled: Bool { didSet { savePreferences() } }
    @Published public private(set) var indicatorIcons: [AgentIndicatorAppearanceStatus: String] { didSet { savePreferences() } }
    @Published public private(set) var customIndicatorIconFiles: [AgentIndicatorAppearanceStatus: String] { didSet { savePreferences() } }
    @Published public private(set) var activities: [AgentActivity]
    @Published public private(set) var lastTransition: AgentActivityTransition?
    @Published public private(set) var lastEventAtByProvider: [AgentProvider: Date]

    public let installationToken: String

    private let defaults: UserDefaults
    private let now: () -> Date
    private let iconDirectory: URL
    private var customIndicatorImageCache: [AgentIndicatorAppearanceStatus: NSImage] = [:]
    private let completionIndicatorDuration: TimeInterval = 8
    private let staleInterval: TimeInterval = 12 * 60 * 60
    private let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    private let maximumActivityCount = 20
    private static let previewSessionPrefixes = ["orpyt-test-", "orpyt-preview-"]

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        applicationSupportDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.now = now
        iconDirectory = (applicationSupportDirectory ?? Self.defaultApplicationSupportDirectory())
            .appendingPathComponent("AgentPulseIcons", isDirectory: true)
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        showTaskDetailsInPopover = defaults.object(forKey: Keys.showTaskDetailsInPopover) as? Bool ?? true
        attentionNotificationsEnabled = defaults.object(forKey: Keys.attentionNotifications) as? Bool ?? true
        completionNotificationsEnabled = defaults.object(forKey: Keys.completionNotifications) as? Bool ?? true
        indicatorIcons = Self.loadIndicatorIcons(from: defaults)
        customIndicatorIconFiles = Self.loadCustomIndicatorIconFiles(from: defaults)
        if let token = defaults.string(forKey: Keys.token), !token.isEmpty {
            installationToken = token
        } else {
            let token = UUID().uuidString.lowercased()
            installationToken = token
            defaults.set(token, forKey: Keys.token)
        }
        activities = Self.normalizedActivities(
            Self.loadActivities(from: defaults).filter { activity in
                !Self.previewSessionPrefixes.contains(where: activity.sessionID.hasPrefix)
            }
        )
        lastEventAtByProvider = Self.loadLastEventDates(from: defaults)
        prune()
    }

    public var indicatorState: AgentIndicatorState {
        guard isEnabled else { return .hidden }
        if activities.contains(where: { $0.state == .needsAttention }) {
            return .attention
        }
        if activities.contains(where: { $0.state == .failed }) { return .failed }
        if activities.contains(where: { $0.state == .running }) {
            return .running
        }
        if activities.contains(where: {
            $0.state == .completed && now().timeIntervalSince($0.updatedAt) <= completionIndicatorDuration
        }) {
            return .completed
        }
        return .hidden
    }

    public func indicatorIcon(for status: AgentIndicatorAppearanceStatus) -> String {
        indicatorIcons[status] ?? status.defaultIcon
    }

    public func setIndicatorIcon(_ icon: String, for status: AgentIndicatorAppearanceStatus) {
        guard status.iconOptions.contains(icon) else { return }
        customIndicatorIconFiles.removeValue(forKey: status)
        customIndicatorImageCache.removeValue(forKey: status)
        var updated = indicatorIcons
        updated[status] = icon
        indicatorIcons = updated
    }

    public func customIndicatorImage(for status: AgentIndicatorAppearanceStatus) -> NSImage? {
        if let cached = customIndicatorImageCache[status] { return cached }
        guard let filename = customIndicatorIconFiles[status] else { return nil }
        let url = iconDirectory.appendingPathComponent(filename, isDirectory: false)
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        customIndicatorImageCache[status] = image
        return image
    }

    public func importCustomIndicatorIcon(from sourceURL: URL, for status: AgentIndicatorAppearanceStatus) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= 10 * 1_024 * 1_024 else {
            throw AgentIndicatorIconImportError.fileTooLarge
        }
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw AgentIndicatorIconImportError.unreadableImage
        }
        let pixelSize = sourceImage.representations.reduce(into: NSSize.zero) { result, representation in
            result.width = max(result.width, CGFloat(representation.pixelsWide))
            result.height = max(result.height, CGFloat(representation.pixelsHigh))
        }
        guard pixelSize.width >= 8, pixelSize.height >= 8,
              pixelSize.width <= 8_192, pixelSize.height <= 8_192 else {
            throw AgentIndicatorIconImportError.invalidDimensions
        }
        guard let pngData = Self.normalizedIconPNG(from: sourceImage, pixelSize: pixelSize) else {
            throw AgentIndicatorIconImportError.couldNotNormalize
        }

        do {
            try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
            let filename = "\(status.rawValue).png"
            let destination = iconDirectory.appendingPathComponent(filename, isDirectory: false)
            try pngData.write(to: destination, options: .atomic)
            guard let normalized = NSImage(data: pngData) else {
                throw AgentIndicatorIconImportError.couldNotNormalize
            }
            normalized.isTemplate = false
            customIndicatorImageCache[status] = normalized
            customIndicatorIconFiles[status] = filename
        } catch let error as AgentIndicatorIconImportError {
            throw error
        } catch {
            throw AgentIndicatorIconImportError.couldNotStore
        }
    }

    public func removeCustomIndicatorIcon(for status: AgentIndicatorAppearanceStatus) {
        if let filename = customIndicatorIconFiles.removeValue(forKey: status) {
            try? FileManager.default.removeItem(at: iconDirectory.appendingPathComponent(filename))
        }
        customIndicatorImageCache.removeValue(forKey: status)
    }

    public var visibleActivities: [AgentActivity] {
        activities.filter {
            $0.state == .running || $0.state == .needsAttention || $0.state == .failed ||
                ($0.state == .completed && $0.isUnread)
        }
    }

    @discardableResult
    public func ingest(_ envelope: AgentEventEnvelope) -> AgentActivityTransition? {
        guard isEnabled, envelope.installationToken == installationToken else { return nil }
        let eventDate = min(envelope.timestamp, now().addingTimeInterval(60))
        lastEventAtByProvider[envelope.provider] = eventDate

        let id = Self.activityID(provider: envelope.provider, sessionID: envelope.sessionID, turnID: envelope.turnID)
        let existingIndex = activities.firstIndex(where: {
            $0.provider == envelope.provider && $0.sessionID == envelope.sessionID
        })

        if envelope.kind == .ended {
            if let existingIndex { activities.remove(at: existingIndex) }
            persist()
            return nil
        }

        if envelope.kind == .resumed {
            guard let existingIndex, activities[existingIndex].state == .needsAttention else {
                persist()
                return nil
            }
        }

        let targetState = Self.state(for: envelope.kind)
        let projectName = Self.projectName(for: envelope.workingDirectory)
        let oldState = existingIndex.map { activities[$0].state }

        if let existingIndex {
            activities[existingIndex].state = targetState
            activities[existingIndex].updatedAt = eventDate
            activities[existingIndex].isUnread = targetState == .completed || targetState == .failed
        } else {
            activities.append(AgentActivity(
                id: id,
                provider: envelope.provider,
                sessionID: envelope.sessionID,
                turnID: envelope.turnID,
                projectName: projectName,
                workingDirectory: envelope.workingDirectory,
                terminalProgram: envelope.terminalProgram,
                state: targetState,
                startedAt: eventDate,
                updatedAt: eventDate,
                isUnread: targetState == .completed || targetState == .failed
            ))
        }

        activities.sort { $0.updatedAt > $1.updatedAt }
        prune()
        persist()

        guard oldState != targetState || existingIndex == nil else { return nil }
        guard let activity = activities.first(where: { $0.id == id }) else { return nil }
        let transition = AgentActivityTransition(activity: activity, kind: envelope.kind, occurredAt: eventDate)
        lastTransition = transition
        return transition
    }

    public func ingest(url: URL) throws -> AgentActivityTransition? {
        let envelope = try AgentEventCodec.decode(url, expectedToken: installationToken, now: now())
        return ingest(envelope)
    }

    public func simulate(_ kind: AgentEventKind, provider: AgentProvider = .codex) {
        activities.removeAll { activity in
            Self.previewSessionPrefixes.contains(where: activity.sessionID.hasPrefix)
        }
        let session = "orpyt-preview-\(provider.rawValue)-\(UUID().uuidString.lowercased())"
        let turnID = "preview-turn"
        _ = ingest(AgentEventEnvelope(
            installationToken: installationToken,
            provider: provider,
            kind: kind,
            sourceEvent: "OrpytTest",
            sessionID: session,
            turnID: turnID,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            terminalProgram: nil,
            timestamp: now()
        ))
        let activityID = Self.activityID(provider: provider, sessionID: session, turnID: turnID)
        DispatchQueue.main.asyncAfter(deadline: .now() + completionIndicatorDuration) { [weak self] in
            guard let self else { return }
            self.activities.removeAll { $0.id == activityID }
            self.persist()
        }
    }

    public func markCompletedRead() {
        var changed = false
        for index in activities.indices where activities[index].state == .completed && activities[index].isUnread {
            activities[index].isUnread = false
            changed = true
        }
        if changed { persist() }
    }

    public func clearFinished() {
        activities.removeAll { [.completed, .failed, .stale].contains($0.state) }
        persist()
    }

    public func prune() {
        let currentDate = now()
        for index in activities.indices where activities[index].state == .running || activities[index].state == .needsAttention {
            if currentDate.timeIntervalSince(activities[index].updatedAt) > staleInterval {
                activities[index].state = .stale
                activities[index].isUnread = false
            }
        }
        activities.removeAll { currentDate.timeIntervalSince($0.updatedAt) > retentionInterval }
        activities.sort { $0.updatedAt > $1.updatedAt }
        if activities.count > maximumActivityCount {
            activities = Array(activities.prefix(maximumActivityCount))
        }
    }

    public func activity(id: String) -> AgentActivity? {
        activities.first(where: { $0.id == id })
    }

    private func savePreferences() {
        defaults.set(isEnabled, forKey: Keys.enabled)
        defaults.set(showTaskDetailsInPopover, forKey: Keys.showTaskDetailsInPopover)
        defaults.set(attentionNotificationsEnabled, forKey: Keys.attentionNotifications)
        defaults.set(completionNotificationsEnabled, forKey: Keys.completionNotifications)
        let rawIcons = Dictionary(uniqueKeysWithValues: indicatorIcons.map { ($0.key.rawValue, $0.value) })
        defaults.set(rawIcons, forKey: Keys.indicatorIcons)
        let rawCustomIcons = Dictionary(uniqueKeysWithValues: customIndicatorIconFiles.map { ($0.key.rawValue, $0.value) })
        defaults.set(rawCustomIcons, forKey: Keys.customIndicatorIcons)
    }

    private func persist() {
        if let data = try? JSONEncoder.agentPulse.encode(activities) {
            defaults.set(data, forKey: Keys.activities)
        }
        let rawDates = Dictionary(uniqueKeysWithValues: lastEventAtByProvider.map { ($0.key.rawValue, $0.value) })
        defaults.set(rawDates, forKey: Keys.lastEvents)
    }

    private static func loadActivities(from defaults: UserDefaults) -> [AgentActivity] {
        guard let data = defaults.data(forKey: Keys.activities),
              let decoded = try? JSONDecoder.agentPulse.decode([AgentActivity].self, from: data) else { return [] }
        return decoded
    }

    private static func normalizedActivities(_ values: [AgentActivity]) -> [AgentActivity] {
        var latestBySession: [String: AgentActivity] = [:]
        for activity in values {
            let normalizedID = activityID(provider: activity.provider, sessionID: activity.sessionID, turnID: nil)
            guard latestBySession[normalizedID]?.updatedAt ?? .distantPast <= activity.updatedAt else { continue }
            latestBySession[normalizedID] = AgentActivity(
                id: normalizedID,
                provider: activity.provider,
                sessionID: activity.sessionID,
                turnID: activity.turnID,
                projectName: activity.projectName,
                workingDirectory: activity.workingDirectory,
                terminalProgram: activity.terminalProgram,
                state: activity.state,
                startedAt: activity.startedAt,
                updatedAt: activity.updatedAt,
                isUnread: activity.isUnread
            )
        }
        return Array(latestBySession.values)
    }

    private static func loadLastEventDates(from defaults: UserDefaults) -> [AgentProvider: Date] {
        guard let raw = defaults.dictionary(forKey: Keys.lastEvents) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let provider = AgentProvider(rawValue: key), let date = value as? Date else { return nil }
            return (provider, date)
        })
    }

    private static func loadIndicatorIcons(from defaults: UserDefaults) -> [AgentIndicatorAppearanceStatus: String] {
        let saved = defaults.dictionary(forKey: Keys.indicatorIcons) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: AgentIndicatorAppearanceStatus.allCases.map { status in
            let icon = saved[status.rawValue].flatMap { status.iconOptions.contains($0) ? $0 : nil }
            return (status, icon ?? status.defaultIcon)
        })
    }

    private static func loadCustomIndicatorIconFiles(from defaults: UserDefaults) -> [AgentIndicatorAppearanceStatus: String] {
        let saved = defaults.dictionary(forKey: Keys.customIndicatorIcons) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: saved.compactMap { rawStatus, filename in
            guard let status = AgentIndicatorAppearanceStatus(rawValue: rawStatus),
                  filename == "\(status.rawValue).png" else { return nil }
            return (status, filename)
        })
    }

    private static func defaultApplicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Orpyt", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Orpyt", isDirectory: true)
    }

    private static func normalizedIconPNG(from image: NSImage, pixelSize: NSSize) -> Data? {
        let canvasSize = 128
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvasSize,
            pixelsHigh: canvasSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
        let maximumContentSize: CGFloat = 112
        let scale = min(maximumContentSize / pixelSize.width, maximumContentSize / pixelSize.height)
        let drawSize = NSSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let drawRect = NSRect(
            x: (CGFloat(canvasSize) - drawSize.width) / 2,
            y: (CGFloat(canvasSize) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func state(for kind: AgentEventKind) -> AgentActivityState {
        switch kind {
        case .started, .resumed: return .running
        case .attention: return .needsAttention
        case .completed: return .completed
        case .failed: return .failed
        case .ended: return .stale
        }
    }

    private static func activityID(provider: AgentProvider, sessionID: String, turnID: String?) -> String {
        [provider.rawValue, sessionID].joined(separator: ":")
    }

    private static func projectName(for path: String) -> String {
        let value = URL(fileURLWithPath: path).lastPathComponent
        return value.isEmpty ? "AI task" : String(value.prefix(80))
    }

    private enum Keys {
        static let enabled = "agentPulse.enabled"
        static let showTaskDetailsInPopover = "agentPulse.showTaskDetailsInPopover"
        static let attentionNotifications = "agentPulse.attentionNotifications"
        static let completionNotifications = "agentPulse.completionNotifications"
        static let indicatorIcons = "agentPulse.indicatorIcons"
        static let customIndicatorIcons = "agentPulse.customIndicatorIcons"
        static let token = "agentPulse.installationToken"
        static let activities = "agentPulse.activities"
        static let lastEvents = "agentPulse.lastEvents"
    }
}

public enum AgentIntegrationState: Equatable, Sendable {
    case notInstalled
    case manualSetupRequired
    case installed
    case receivingEvents
    case malformedConfiguration(String)

    public var title: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .manualSetupRequired: return "Manual setup"
        case .installed: return "Installed"
        case .receivingEvents: return "Receiving events"
        case .malformedConfiguration: return "Needs manual setup"
        }
    }
}

@MainActor
public final class AgentIntegrationManager: ObservableObject {
    public static let shared = AgentIntegrationManager(activityStore: .shared)
    public static let ownerMarker = "com.orpyt.app.agent-pulse"

    @Published public private(set) var states: [AgentProvider: AgentIntegrationState] = [:]
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastErrorProvider: AgentProvider?

    private let activityStore: AgentActivityStore
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let bridgeURL: URL

    public init(
        activityStore: AgentActivityStore,
        homeDirectory: URL? = nil,
        bridgeURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.activityStore = activityStore
        self.homeDirectory = homeDirectory ?? Self.realUserHomeDirectory()
        self.fileManager = fileManager
        self.bridgeURL = bridgeURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OrpytAgentBridge")
        refresh()
    }

    public func refresh() {
        #if DIRECT_DISTRIBUTION
        for provider in AgentProvider.allCases {
            let configURL = self.configURL(for: provider)
            do {
                let root = try readRootObject(at: configURL, allowMissing: true)
                let installed = containsOwnedHook(in: root, provider: provider)
                if installed, activityStore.lastEventAtByProvider[provider] != nil {
                    states[provider] = .receivingEvents
                } else {
                    states[provider] = installed ? .installed : .notInstalled
                }
            } catch {
                states[provider] = .malformedConfiguration(error.localizedDescription)
            }
        }
        #else
        // The App Store sandbox cannot inspect hidden configuration folders.
        // Receiving an event is the reliable confirmation that a copied hook works.
        for provider in AgentProvider.allCases {
            states[provider] = activityStore.lastEventAtByProvider[provider] == nil
                ? .manualSetupRequired
                : .receivingEvents
        }
        lastError = nil
        lastErrorProvider = nil
        #endif
    }

    public var supportsAutomaticSetup: Bool {
        #if DIRECT_DISTRIBUTION
        true
        #else
        false
        #endif
    }

    @discardableResult
    public func install(_ provider: AgentProvider) -> Bool {
        #if DIRECT_DISTRIBUTION
        do {
            let url = configURL(for: provider)
            var root = try readRootObject(at: url, allowMissing: true)
            removeOwnedHooks(from: &root)
            mergeHooks(into: &root, provider: provider)
            try write(root: root, to: url, makeBackup: true)
            lastError = nil
            lastErrorProvider = nil
            refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            lastErrorProvider = provider
            refresh()
            return false
        }
        #else
        lastError = "The App Store sandbox cannot edit this file. Copy the configuration instead."
        lastErrorProvider = provider
        return false
        #endif
    }

    @discardableResult
    public func uninstall(_ provider: AgentProvider) -> Bool {
        #if DIRECT_DISTRIBUTION
        do {
            let url = configURL(for: provider)
            guard fileManager.fileExists(atPath: url.path) else { return true }
            var root = try readRootObject(at: url, allowMissing: false)
            removeOwnedHooks(from: &root)
            try write(root: root, to: url, makeBackup: true)
            lastError = nil
            lastErrorProvider = nil
            refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            lastErrorProvider = provider
            refresh()
            return false
        }
        #else
        lastError = "Remove the Orpyt hook entries from your agent configuration manually."
        lastErrorProvider = provider
        return false
        #endif
    }

    public func manualConfiguration(for provider: AgentProvider) -> String {
        var root: [String: Any] = [:]
        mergeHooks(into: &root, provider: provider)
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    public func configPath(for provider: AgentProvider) -> String {
        configURL(for: provider).path
    }

    private func configURL(for provider: AgentProvider) -> URL {
        switch provider {
        case .codex: return homeDirectory.appendingPathComponent(".codex/hooks.json")
        case .claude: return homeDirectory.appendingPathComponent(".claude/settings.json")
        }
    }

    private nonisolated static func realUserHomeDirectory() -> URL {
        if let passwordEntry = getpwuid(getuid()),
           let homePath = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func readRootObject(at url: URL, allowMissing: Bool) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            if allowMissing { return [:] }
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentIntegrationError.invalidJSON(url.path)
        }
        return object
    }

    private func containsOwnedHook(in root: [String: Any], provider: AgentProvider) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { ($0["command"] as? String)?.contains(Self.ownerMarker) == true &&
                    ($0["command"] as? String)?.contains("--provider \(provider.rawValue)") == true }
            }
        }
    }

    private func mergeHooks(into root: inout [String: Any], provider: AgentProvider) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for mapping in mappings(for: provider) {
            var groups = hooks[mapping.event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [[
                "type": "command",
                "command": command(provider: provider, mapping: mapping),
                "timeout": 5,
                "statusMessage": "Orpyt Agent Pulse",
            ]]]
            if let matcher = mapping.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[mapping.event] = groups
        }
        root["hooks"] = hooks
    }

    private func removeOwnedHooks(from root: inout [String: Any]) {
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [[String: Any]] else { continue }
            let cleanedGroups: [[String: Any]] = groups.compactMap { original in
                var group = original
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let cleaned = handlers.filter { handler in
                    guard let command = handler["command"] as? String else { return true }
                    return !command.contains(Self.ownerMarker)
                }
                guard !cleaned.isEmpty else { return nil }
                group["hooks"] = cleaned
                return group
            }
            if cleanedGroups.isEmpty { hooks.removeValue(forKey: key) }
            else { hooks[key] = cleanedGroups }
        }
        root["hooks"] = hooks
    }

    private func command(provider: AgentProvider, mapping: Mapping) -> String {
        let escapedPath = bridgeURL.path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escapedPath)' --owner \(Self.ownerMarker) --provider \(provider.rawValue) --event \(mapping.kind.rawValue) --source \(mapping.event) --token \(activityStore.installationToken)"
    }

    private func mappings(for provider: AgentProvider) -> [Mapping] {
        var values = [
            Mapping(event: "UserPromptSubmit", matcher: nil, kind: .started),
            Mapping(event: "PermissionRequest", matcher: nil, kind: .attention),
            Mapping(event: "PostToolUse", matcher: nil, kind: .resumed),
            Mapping(event: "Stop", matcher: nil, kind: .completed),
        ]
        if provider == .claude {
            values.append(Mapping(event: "Notification", matcher: "permission_prompt|idle_prompt|elicitation_dialog", kind: .attention))
            values.append(Mapping(event: "Notification", matcher: "elicitation_complete|elicitation_response", kind: .resumed))
            values.append(Mapping(event: "StopFailure", matcher: nil, kind: .failed))
            values.append(Mapping(event: "SessionEnd", matcher: nil, kind: .ended))
        }
        return values
    }

    private func write(root: [String: Any], to url: URL, makeBackup: Bool) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var permissions: NSNumber?
        if fileManager.fileExists(atPath: url.path) {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            permissions = attributes?[.posixPermissions] as? NSNumber
            if makeBackup {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let suffix = UUID().uuidString.prefix(8)
                let backup = url.appendingPathExtension("orpyt-backup-\(formatter.string(from: Date()))-\(suffix)")
                try fileManager.copyItem(at: url, to: backup)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private struct Mapping {
        let event: String
        let matcher: String?
        let kind: AgentEventKind
    }
}

public enum AgentIntegrationError: LocalizedError {
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidJSON(path): return "Orpyt did not change malformed JSON at \(path). Use manual setup or repair the file first."
        }
    }
}

private extension JSONEncoder {
    static var agentPulse: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var agentPulse: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: normalized)
    }
}
