# Orpyt Calendar Intelligence V1

## Summary

Orpyt should become smarter around meetings without turning into a full calendar app. The goal is to make the existing calendar feature more actionable in the popover and more useful directly from the menu bar, while keeping the app lightweight, native, and calm.

## 1. Calendar Data Layer

- Extend the calendar store so it exposes both the next meeting and a same-day agenda.
- Keep `MeetingSnapshot` as the base event model.
- Add a container snapshot with:
  - `nextMeeting`
  - `todayAgenda`
  - `hasJoinableMeeting`
- Continue using read-only EventKit access only.
- Preserve join-link extraction from calendar events.

## 2. Next Meeting Card

- Upgrade the current next-meeting card with a native 3-dot menu.
- Main card tap should:
  - join the meeting directly if a join URL exists
  - otherwise open the event in Calendar
- 3-dot menu should include:
  - `Join Meeting` or `Open in Calendar`
  - `New Meeting`
  - `Today’s Plan`
  - `Open Calendar`
- `Today’s Plan` should expand inline under the card.
- Agenda should show:
  - meeting title
  - start time
  - relative time / live state
  - optional join action
- Agenda should stay compact and not feel like a second app.
- If there are many meetings, cap the visible rows and offer `Show remaining in Calendar`.

## 3. Menu Bar Meeting Indicator

- Add a meeting warning layer to the menu bar.
- Only show it when there is a next meeting inside the configured warning window.
- Support these styles:
  - `Off`
  - `Tiny Badge`
  - `Imminent Pill`
  - `Full Replace`
- Default should be `Imminent Pill`.
- Warning phases:
  - early warning
  - critical warning
- Default timing:
  - early: `10 min`
  - critical: `5 min`
- If a meeting is already live, keep critical behavior until it ends.
- Hovering the indicator should temporarily replace the time title with the meeting title.
- Clicking the indicator area should open the meeting directly.
- Clicking the rest of the menu bar item should still open the Orpyt popover.

## 4. Settings UX

- Keep all meeting-related controls in the existing `Calendar` pane.
- Add a `Meeting Alerts` section with:
  - indicator style
  - warning timing mode
  - preset values
  - advanced custom minute controls
- Add a `Today’s Plan` note so users understand the 3-dot menu behavior.
- Keep calendar privacy messaging clear:
  - Orpyt reads upcoming events only
  - Orpyt does not create or edit calendar data directly
  - Calendar app handles event creation flow

## 5. Pro / Access Rules

- These features remain within the existing calendar / Orpyt Pro capability family.
- Free users should still see a clean app and a clear upgrade path.
- Premium features should be visible but gated gracefully, not hidden in a confusing way.

## 6. Stability / UX Expectations

- The popover must resize and scroll correctly when `Today’s Plan` expands.
- Long meeting titles must truncate safely in the menu bar.
- Changing meeting warning presets must never crash or recurse.
- Calendar-denied and no-event states must stay graceful.
- The menu bar behavior should remain readable and non-intrusive.

## 7. What We Also Fixed During This Work

- Restored the direct-download build define regression.
- Moved agenda expansion ownership to the popover so layout can respond correctly.
- Fixed the recursive crash in the meeting warning preset flow.

## 8. Next Good Additions After This

- provider badges for Zoom / Meet / Teams
- `Starts in 4m` / `Live now` countdown chip in popover
- working-hours awareness across time zones
