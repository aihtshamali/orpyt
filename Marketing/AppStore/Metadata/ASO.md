# Orpyt App Store Metadata

Apple product page guidance currently lists a 30-character subtitle and 170-character promotional text limit. Keep keywords concise and do not duplicate words already present in the app name when avoidable.

Source: https://developer.apple.com/app-store/product-page/

## App Name
`Orpyt: Menu Bar World Clock`

## Subtitle
`Time zones for remote work`

## Category
`Productivity`

Secondary fit, if needed: `Utilities`

## Promotional Text
`New: meeting alerts, Today’s Plan, join links, calendar refresh, country search, weather, and time scroller planning.`

## Keywords
`meeting planner,timezone converter,calendar,weather,city time,global teams,scheduler,travel,agenda`

## Description
Orpyt is a native macOS menu bar clock with calendar intelligence for people working across time zones.

Keep two cities visible in your menu bar, see upcoming meeting context at a glance, open Today’s Plan, and plan across hours without leaving your current workflow. Orpyt is built to feel calm, glanceable, and useful during real work: remote standups, client calls, travel planning, and everyday coordination across cities.

Free features:
- Dual clocks in the macOS menu bar
- Search cities, countries, and time zones
- 12-hour and 24-hour formats
- Optional seconds, weekday, date, time zone abbreviation, and GMT offset
- Custom labels for each clock
- One-clock or two-clock menu bar layouts
- Launch at login
- Native macOS settings

Orpyt Pro adds:
- Live weather for each clock
- Read-only calendar context for your next meeting
- Meeting alerts in the menu bar
- Today’s Plan for the rest of your day
- Join and copy meeting links when available
- Manual calendar refresh from the menu
- Time Scroller for previewing future or past hours across both clocks
- Advanced appearance controls

Calendar access is read-only. Orpyt uses it to show upcoming meeting context and join links when available. It does not create, edit, or upload your calendar events.

Weather is based on your configured clock locations, so you can understand the people and places you work with before you message, schedule, or join.

Orpyt is for anyone who wants time zones to feel less like mental math and more like a quiet part of the Mac.

## What’s New
New calendar intelligence for cross-time-zone work:

- Added menu bar meeting alerts for upcoming meetings
- Added Today’s Plan in the popover
- Added quick join and copy-link actions for calendar meetings
- Added a calendar refresh action
- Added faster country search for matching cities
- Improved meeting indicator hover behavior and spacing
- Added a warmer, Apple-compliant feedback and review flow
- Added a Suggest a Feature link to GitHub Discussions
- Fixed calendar permission refresh behavior after access changes in System Settings
- Improved time zone search result limits for a cleaner picker

## App Review Notes
Orpyt is a menu bar app. After launch, it appears in the macOS menu bar rather than as a Dock-window-first app.

Suggested review flow:
1. Launch Orpyt.
2. Click the Orpyt menu bar item to open the popover.
3. Open Settings from the popover or menu.
4. Try changing the two clock locations.
5. Enable Calendar access to view read-only next meeting context.
6. Use the time scroller to preview another hour across both clocks.
7. Open Settings > Overview to find Suggest a Feature.

Calendar usage:
- Orpyt requests calendar access only to read upcoming events.
- Calendar data stays on device.
- Orpyt does not create, edit, delete, or upload calendar events.

Subscriptions:
- Subscription group: `Orpyt Pro`
- Monthly product: `com.orpyt.pro.monthly`
- Yearly product: `com.orpyt.pro.yearly`
- Monthly price: `$1.99/month` in the United States
- Yearly upfront price: `$14.99/year` in the United States
- Both products include a 7-day free trial.

Notes for direct-download builds:
- Direct-download builds use Sparkle for updates.
- App Store builds use StoreKit commerce and Apple’s system review prompt.
- Source builds include the free feature set; Orpyt Pro is distributed through the Mac App Store version.
- Feature suggestions open GitHub Discussions: https://github.com/aihtshamali/orpyt/discussions

## App Privacy Draft
Use this only if the app still has no analytics, no developer server, no account system, and no third-party tracking.

Data collected by developer: `None`

Data not collected:
- Calendar events are read locally for upcoming meeting context.
- Configured time zone and weather locations are app settings.
- Weather requests use Apple WeatherKit for configured locations.
- Subscription state is handled through StoreKit.

Tracking: `No`

## Support And URLs
Support URL:
`https://github.com/aihtshamali/orpyt/discussions`

Marketing URL:
`https://github.com/aihtshamali/orpyt`

Privacy Policy URL:
`Publish Marketing/AppStore/Metadata/PrivacyPolicy.md and paste the public URL here before submission.`

## Screenshot Captions
1. `Two time zones, always visible`
2. `Plan meetings across cities`
3. `Weather and meeting context`
4. `Today’s Plan at a glance`
5. `Native settings for your workflow`

## Subscription Localization
### Orpyt Pro Monthly
Display name:
`Orpyt Pro Monthly`

Description:
`Flexible monthly access to Orpyt Pro with all features.`

### Orpyt Pro Yearly
Display name:
`Orpyt Pro Yearly`

Description:
`Best value for time-zone work with weather, calendar context, meeting alerts, and planning tools.`

## Production Checklist
- Confirm App Store Connect has `com.orpyt.pro.monthly` and `com.orpyt.pro.yearly`.
- Confirm yearly is sold as `1 Year Upfront`; avoid enabling `Monthly with 12-Month Commitment` while a separate monthly product exists.
- Confirm WeatherKit capability is enabled for `com.orpyt.app`.
- Confirm Calendar entitlement is enabled.
- Confirm privacy policy URL before final submission.
- Confirm screenshots match the latest meeting alert and Today’s Plan UI.
- Archive from Xcode using the `Orpyt` scheme and `Release` configuration.
- Validate and upload from Xcode Organizer.
