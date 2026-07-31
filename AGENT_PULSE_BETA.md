# Agent Pulse Labs Beta

Agent Pulse is an opt-in, local-only Orpyt feature for Codex CLI, local Codex/ChatGPT desktop tasks, and Claude Code. It shows whether an AI task is running, waiting for attention, completed, failed, or stale without reading the task's conversation or source code.

## User experience and use cases

- A running Codex or Claude turn shows an animated leading menu-bar symbol. User-level Codex hooks also cover supported local desktop turns.
- A permission request, elicitation, or idle/input notification replaces it with the higher-priority attention symbol.
- A successful stop shows a green completion check for eight seconds.
- A failed Claude stop remains visible as a failed task in the popover and can notify the user.
- Concurrent agents are aggregated with priority: attention, running, recent completion, hidden.
- The AI Tasks section shows up to three actionable or unread tasks. Selecting one activates its known terminal, or falls back to its project folder.
- Completed tasks become read when shown. Users can clear history or open the full Labs settings view.
- A missing final hook cannot animate forever: active records become stale after 12 hours.
- Relaunch restores up to 20 normalized activities, retaining no more than seven days.
- Desktop Codex tasks reopen through the documented `codex://threads/<thread-id>` deep link. Missing folders and unknown terminals degrade safely.
- Reduced Motion replaces the three-frame animation with a static running symbol.
- Users can choose a separate native SF Symbol or import a custom PNG, JPEG, HEIC, or TIFF for running, attention, completed, and failed states. Imports are validated, normalized to a compact transparent PNG, copied into Orpyt’s Application Support container, and previewed without retaining access to the original file.
- Notification denial does not affect menu-bar or popover status.
- Quitting Orpyt leaves the AI workflow untouched and the bridge does not relaunch the app.
- Background lifecycle events are delivered with app activation disabled, so task transitions never take keyboard focus from the user's current window.

Out of scope for this beta: the Claude desktop app, cloud or remote agents, subagent visualization, mobile delivery, automatic approvals, transcript analysis, and analytics.

## Integration

1. The user enables **Settings → AI Agents (Beta)**. This creates an installation-specific random token.
2. The explicit Install button merges Orpyt-owned hook handlers into `~/.codex/hooks.json` or `~/.claude/settings.json` in direct builds. Existing settings and hooks remain intact; writes are atomic and backed up.
3. Codex users inspect and trust the definitions with `/hooks`. Installation and first-event receipt are reported separately.
4. A provider hook sends JSON to the bundled `Contents/Helpers/OrpytAgentBridge` executable on stdin.
5. The bridge extracts only event name, session/turn IDs, working directory, terminal or desktop host identifier, provider, and timestamp. It size-limits and Base64URL-encodes a versioned envelope.
6. If and only if Orpyt is already running, the bridge opens `orpyt://agent-event?v=1&payload=…`. It always exits successfully and prints `{}`.
7. Orpyt verifies the URL scheme, version, token, size, timestamp, provider/event decoding, and identifier bounds before updating local state.

Uninstall removes only commands containing Orpyt's ownership marker and current bridge identity. Malformed configuration is never overwritten; the settings pane instead exposes copyable manual configuration. App Store builds provide the manual path and do not write dotfiles.

### Event mapping

| Provider hook | State |
|---|---|
| `UserPromptSubmit` | Running |
| `PermissionRequest` | Needs attention |
| Claude `Notification` for permission, idle, or elicitation | Needs attention |
| `PostToolUse` after attention | Running |
| Claude elicitation/completion response | Running |
| `Stop` | Completed |
| Claude `StopFailure` | Failed |
| Claude `SessionEnd` while active | Ended without false completion |

## Privacy boundary

Persisted state and transport envelopes contain only normalized provider, project-folder name/path, task identifiers, terminal identifier, state, and timestamps. Prompt text, assistant responses, transcript paths, tool inputs, commands, and source content are neither represented in the envelope model nor persisted. Hook input keys outside the allowlist are discarded by the bridge.

## Evaluation

Automated checks cover lifecycle transitions, concurrent priority, duplicate suppression, stale expiry, authenticated URL decoding, URL privacy, persistence behavior, menu layout migration, and idempotent installer merge/uninstall while retaining third-party hooks. The bridge is also exercised while Orpyt is unavailable to confirm `{}` and exit status zero.

Release-candidate verification:

- `swift test`
- Swift Package debug build for the app and helper
- canonical Xcode Debug build
- direct `dist/Orpyt.app` assembly
- deep code-sign verification, including the helper
- URL scheme inspection
- launch and process-liveness check

Manual acceptance matrix before wider beta:

- At least ten Codex and ten Claude turns, including permission, resume, success, failure where supported, concurrent agents, restart, and intentional Orpyt quit.
- Event-to-indicator latency under one second.
- No missed approvals and no duplicate notification banners.
- No prompt, response, transcript, command, tool input, or source content in URLs or persisted defaults.
- Idle CPU remains at baseline and active animation averages below 0.5% on the test Mac.
- Hooks behave normally when the app is absent or rejects an event.

The current local Claude executable has a Node compatibility failure, so the real Claude portion of the manual matrix must be completed after installing a working Claude Code runtime. This does not block the app, bridge, simulated events, or Codex evaluation.
