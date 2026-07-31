import AppKit
import Foundation
import Testing
@testable import OrpytCore

@Suite("Agent Pulse")
@MainActor
struct AgentPulseTests {
    private final class TestClock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private func makeStore(clock: TestClock = TestClock(Date(timeIntervalSince1970: 1_750_000_000))) -> (AgentActivityStore, UserDefaults) {
        let suite = "AgentPulseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgentActivityStore(defaults: defaults, now: { clock.date })
        store.isEnabled = true
        return (store, defaults)
    }

    private func event(
        store: AgentActivityStore,
        kind: AgentEventKind,
        provider: AgentProvider = .codex,
        session: String = "session-1",
        turn: String? = "turn-1",
        terminal: String? = "Apple_Terminal",
        date: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> AgentEventEnvelope {
        AgentEventEnvelope(
            installationToken: store.installationToken,
            provider: provider,
            kind: kind,
            sourceEvent: "test-event",
            sessionID: session,
            turnID: turn,
            workingDirectory: "/Users/test/SecretProject",
            terminalProgram: terminal,
            timestamp: date
        )
    }

    @Test("events move through running, attention, resumed, and completed")
    func stateTransitions() {
        let (store, _) = makeStore()
        #expect(store.ingest(event(store: store, kind: .started)) != nil)
        #expect(store.activities.first?.state == .running)
        #expect(store.indicatorState == .running)

        #expect(store.ingest(event(store: store, kind: .attention)) != nil)
        #expect(store.activities.first?.state == .needsAttention)
        #expect(store.indicatorState == .attention)

        #expect(store.ingest(event(store: store, kind: .resumed)) != nil)
        #expect(store.activities.first?.state == .running)

        #expect(store.ingest(event(store: store, kind: .completed)) != nil)
        #expect(store.activities.first?.state == .completed)
        #expect(store.activities.first?.isUnread == true)
        #expect(store.indicatorState == .completed)
    }

    @Test("attention has priority across concurrent agents")
    func aggregatePriority() {
        let (store, _) = makeStore()
        store.ingest(event(store: store, kind: .started, provider: .codex, session: "codex"))
        store.ingest(event(store: store, kind: .attention, provider: .claude, session: "claude"))
        #expect(store.activities.count == 2)
        #expect(store.indicatorState == .attention)
    }

    @Test("failed has its own indicator and attention remains higher priority")
    func failedIndicatorPriority() {
        let (store, _) = makeStore()
        store.ingest(event(store: store, kind: .failed, provider: .codex, session: "failed"))
        #expect(store.indicatorState == .failed)
        store.ingest(event(store: store, kind: .attention, provider: .claude, session: "attention"))
        #expect(store.indicatorState == .attention)
    }

    @Test("per-status indicator icon choices persist and reject unknown symbols")
    func indicatorIconPreferences() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_750_000_000))
        let (store, defaults) = makeStore(clock: clock)
        store.setIndicatorIcon("sparkles", for: .running)
        store.setIndicatorIcon("not.a.curated.symbol", for: .failed)
        #expect(store.indicatorIcon(for: .running) == "sparkles")
        #expect(store.indicatorIcon(for: .failed) == AgentIndicatorAppearanceStatus.failed.defaultIcon)

        let reloaded = AgentActivityStore(defaults: defaults, now: { clock.date })
        #expect(reloaded.indicatorIcon(for: .running) == "sparkles")
    }

    @Test("popover task details are visible by default and the preference persists")
    func popoverTaskDetailsPreference() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_750_000_000))
        let (store, defaults) = makeStore(clock: clock)
        #expect(store.showTaskDetailsInPopover)

        store.showTaskDetailsInPopover = false

        let reloaded = AgentActivityStore(defaults: defaults, now: { clock.date })
        #expect(!reloaded.showTaskDetailsInPopover)
    }

    @Test("custom icons are normalized into Application Support and can be removed")
    func customIconImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentIcon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.png")

        let sourceImage = NSImage(size: NSSize(width: 64, height: 32))
        sourceImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 32).fill()
        sourceImage.unlockFocus()
        let representation = try #require(sourceImage.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let sourceData = try #require(representation.representation(using: .png, properties: [:]))
        try sourceData.write(to: sourceURL)

        let suite = "AgentPulseCustomIcon.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let support = root.appendingPathComponent("ApplicationSupport")
        let store = AgentActivityStore(defaults: defaults, applicationSupportDirectory: support)
        try store.importCustomIndicatorIcon(from: sourceURL, for: .running)

        let copiedURL = support.appendingPathComponent("AgentPulseIcons/running.png")
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        #expect(store.customIndicatorImage(for: .running) != nil)

        let reloaded = AgentActivityStore(defaults: defaults, applicationSupportDirectory: support)
        #expect(reloaded.customIndicatorImage(for: .running) != nil)
        reloaded.removeCustomIndicatorIcon(for: .running)
        #expect(!FileManager.default.fileExists(atPath: copiedURL.path))
    }

    @Test("duplicate states and irrelevant resume events are suppressed")
    func deduplication() {
        let (store, _) = makeStore()
        #expect(store.ingest(event(store: store, kind: .started)) != nil)
        #expect(store.ingest(event(store: store, kind: .started)) == nil)
        #expect(store.ingest(event(store: store, kind: .resumed)) == nil)
        #expect(store.activities.count == 1)
    }

    @Test("completion reconciles the session when hook turn identifiers differ")
    func completionWithDifferentTurnIdentifier() {
        let (store, _) = makeStore()
        store.ingest(event(store: store, kind: .started, session: "shared-session", turn: "prompt-turn"))
        store.ingest(event(store: store, kind: .completed, session: "shared-session", turn: nil))

        #expect(store.activities.count == 1)
        #expect(store.activities.first?.state == .completed)
        #expect(store.indicatorState == .completed)
    }

    @Test("active tasks become stale after twelve hours")
    func staleExpiry() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_750_000_000))
        let (store, _) = makeStore(clock: clock)
        store.ingest(event(store: store, kind: .started, date: clock.date))
        clock.date = clock.date.addingTimeInterval(12 * 60 * 60 + 1)
        store.prune()
        #expect(store.activities.first?.state == .stale)
        #expect(store.indicatorState == .hidden)
    }

    @Test("indicator previews are identified as desktop-safe ephemeral records")
    func previewAndDesktopSource() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_750_000_000))
        let (store, defaults) = makeStore(clock: clock)
        store.simulate(.started)
        #expect(store.activities.count == 1)
        #expect(store.indicatorState == .running)

        let reloaded = AgentActivityStore(defaults: defaults, now: { clock.date })
        #expect(reloaded.activities.isEmpty)

        reloaded.isEnabled = true
        reloaded.ingest(event(
            store: reloaded,
            kind: .started,
            session: "desktop-thread",
            terminal: "com.openai.codex"
        ))
        #expect(reloaded.activities.first?.sourceTitle == "Codex Desktop")
        #expect(reloaded.activities.first?.originatesFromCodexDesktop == true)
    }

    @Test("URL codec authenticates and contains no conversation content")
    func codecPrivacyAndValidation() throws {
        let (store, _) = makeStore()
        let envelope = event(store: store, kind: .attention)
        let url = try AgentEventCodec.url(for: envelope)
        #expect(!url.absoluteString.contains("prompt"))
        #expect(!url.absoluteString.contains("assistant"))
        #expect(try AgentEventCodec.decode(url, expectedToken: store.installationToken, now: envelope.timestamp) == envelope)
        #expect(throws: AgentEventCodecError.invalidToken) {
            try AgentEventCodec.decode(url, expectedToken: "wrong", now: envelope.timestamp)
        }
    }

    @Test("installer preserves existing hooks and is idempotent")
    func installerMergeAndUninstall() throws {
        let (store, _) = makeStore()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AgentPulse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "/usr/bin/existing-hook"]]]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: config)

        let manager = AgentIntegrationManager(
            activityStore: store,
            homeDirectory: home,
            bridgeURL: URL(fileURLWithPath: "/Applications/Orpyt.app/Contents/Helpers/OrpytAgentBridge")
        )
        #expect(manager.install(.codex))
        let once = try Data(contentsOf: config)
        #expect(String(decoding: once, as: UTF8.self).contains(AgentIntegrationManager.ownerMarker))
        #expect(commandValues(in: once).contains("/usr/bin/existing-hook"))

        #expect(manager.install(.codex))
        let twice = try Data(contentsOf: config)
        let markerCount = String(decoding: twice, as: UTF8.self).components(separatedBy: AgentIntegrationManager.ownerMarker).count - 1
        #expect(markerCount == 4)

        #expect(manager.uninstall(.codex))
        let removedData = try Data(contentsOf: config)
        let removed = String(decoding: removedData, as: UTF8.self)
        #expect(!removed.contains(AgentIntegrationManager.ownerMarker))
        #expect(commandValues(in: removedData).contains("/usr/bin/existing-hook"))
    }

    private func commandValues(in data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        func visit(_ value: Any) -> [String] {
            if let dictionary = value as? [String: Any] {
                let own = (dictionary["command"] as? String).map { [$0] } ?? []
                return own + dictionary.values.flatMap(visit)
            }
            if let array = value as? [Any] {
                return array.flatMap(visit)
            }
            return []
        }
        return visit(root)
    }
}
