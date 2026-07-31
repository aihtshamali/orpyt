import AppKit
import Foundation
import OrpytCore

private func argument(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func finish() -> Never {
    // Codex Stop hooks require valid JSON on stdout. An empty object is also
    // harmless for Claude and guarantees this side-effect-only hook never
    // changes, blocks, or adds context to an agent turn.
    FileHandle.standardOutput.write(Data("{}\n".utf8))
    exit(EXIT_SUCCESS)
}

let arguments = CommandLine.arguments
guard argument("--owner", in: arguments) == AgentIntegrationManager.ownerMarker,
      let providerValue = argument("--provider", in: arguments),
      let provider = AgentProvider(rawValue: providerValue),
      let eventValue = argument("--event", in: arguments),
      let kind = AgentEventKind(rawValue: eventValue),
      let token = argument("--token", in: arguments),
      !token.isEmpty else {
    finish()
}

// Never relaunch an app the user intentionally quit.
guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.orpyt.app").isEmpty else {
    finish()
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard input.count <= 64 * 1_024,
      let json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
    finish()
}

guard let sessionID = json["session_id"] as? String, !sessionID.isEmpty else {
    finish()
}

let workingDirectory = (json["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    ?? FileManager.default.currentDirectoryPath
let environment = ProcessInfo.processInfo.environment
let originatingProgram = environment["TERM_PROGRAM"] ?? environment["__CFBundleIdentifier"]
let envelope = AgentEventEnvelope(
    installationToken: token,
    provider: provider,
    kind: kind,
    sourceEvent: argument("--source", in: arguments) ?? (json["hook_event_name"] as? String ?? "unknown"),
    sessionID: sessionID,
    turnID: json["turn_id"] as? String,
    workingDirectory: workingDirectory,
    terminalProgram: originatingProgram,
    timestamp: Date()
)

if let url = try? AgentEventCodec.url(for: envelope),
   let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.orpyt.app").first,
   let appURL = runningApp.bundleURL {
    // Deliver the URL to the existing app without activating it. A normal
    // NSWorkspace.open(url) makes a menu-bar app frontmost and steals keyboard
    // focus from the editor or terminal whenever a background task changes.
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = false
    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, _ in }
}

finish()
