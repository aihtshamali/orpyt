# Orpyt Handoff Summary

Last updated: 2026-05-24

## Product Snapshot

Orpyt is a native macOS menu bar app for people working across time zones. The core value is helping users choose the right time to message, meet, and plan without doing timezone math.

Current positioning direction:

> Orpyt is a native Mac menu bar world clock for remote teams, helping you choose the right time to message, meet, and plan across time zones.

Primary audience:
- Remote workers
- Founders and freelancers
- Executive assistants
- Distributed teams
- Digital nomads
- People coordinating with family, clients, or teammates abroad

Core free value:
- Two clean world clocks in the Mac menu bar
- City/country/time zone search
- 12h/24h format
- Launch at login
- Native macOS design

Pro value:
- Meeting alerts
- Today’s Plan
- Time Scroller for cross-time-zone planning
- Weather context for each city
- Advanced menu bar customization/reordering

## Current Pricing Direction

Early-growth pricing should stay low and easy to accept:

- Monthly: `$0.99/month`
- Yearly: `$9.99/year`

Present annual first where possible:

> Orpyt Pro: $9.99/year, or $0.99/month

Important: App Store metadata should avoid hardcoding prices in promotional text/description because regional pricing varies.

## App Store Metadata Recommendation

App Store URL:
https://apps.apple.com/us/app/orpyt/id6765900155?mt=12

Recommended app name:

```text
Orpyt: Menu Bar World Clock
```

Recommended subtitle:

```text
Time Zones for Remote Teams
```

Recommended promotional text:

```text
Stop guessing time zones. See teammates’ local time from your Mac menu bar and plan meetings before you message at the wrong hour.
```

Recommended keyword field:

```text
timezone,converter,meeting,schedule,calendar,weather,cities,utc,gmt,overlap,planner,travel
```

Reasoning:
- App name/subtitle should carry search terms.
- Promotional text does not affect search ranking, so use it for conversion.
- Do not repeat words already in title/subtitle, such as `world`, `clock`, `menu`, `bar`, `remote`, `teams`.

## App Store Description Opening

Use this style:

```text
Working across time zones should not require mental math.

Orpyt keeps the people, places, and meetings you care about visible from your Mac menu bar, so you know the right time to message, meet, and plan your day.
```

Then list Free and Pro clearly.

Free section:

```text
FREE
- Two clean world clocks in your Mac menu bar
- Search cities, countries, and time zones
- 12h/24h format
- Launch at login
- Native macOS design
```

Pro section:

```text
ORPYT PRO
- Meeting alerts and Today’s Plan
- Time Scroller for cross-time-zone planning
- Weather context for each city
- Advanced menu bar customization
```

## Screenshot Strategy

The screenshot sequence should sell the pain and outcome, not just the UI.

Recommended sequence:

1. `Know when it’s the right time`
   - Show menu bar clocks clearly.
   - This is the hero screenshot.

2. `Don’t ping people after hours`
   - Show one city in work hours and another late at night.

3. `Find the best time to meet`
   - Show Time Scroller or overlap planning.

4. `See meetings in everyone’s time`
   - Show calendar alert, Today’s Plan, join/copy actions.

5. `Plan your global day at a glance`
   - Show clocks, weather, meetings, and Today’s Plan together.

6. `Customize your menu bar clocks`
   - Show Menu Bar settings/reorder UI.

Avoid:
- Generic “World Clock” screenshots.
- Leading with settings.
- Abstract space/gradient images that hide the real app.
- Overpromising phrases like “Never miss a meeting again.”

Better emotional phrases:
- `Don’t ping people after hours`
- `Know before you send`
- `Message at the right time`
- `Find the best time to meet`

## Recent Implemented Features / Fixes

### Calendar and Meeting Work

Implemented or worked through:
- Meeting alert pill behavior.
- Hover/title behavior discussions.
- Join/copy meeting actions in Today’s Plan.
- Copy feedback animation/overlay.
- Calendar refresh action in the three-dot menu.
- Clickable meetings.
- Avoiding unstable hover layout shifts.

Important behavior decision:
- The actual menu bar meeting pill should respect the user’s configured click action:
  - reveal title
  - open calendar
  - open meeting
- In Settings preview only, clicking the imminent/Now pill opens Calendar settings.

### Review and Feedback Flow

Implemented plan:
- Apple-compliant review pre-prompt.
- StoreKit review prompt only for App Store builds.
- Manual `Suggest a Feature` action.
- Debug/local testing option for feedback flow.

Suggestions URL was updated from GitHub Issues to GitHub Discussions:

```text
https://github.com/aihtshamali/orpyt/discussions
```

Recommended review prompt copy:

Title:

```text
Enjoying Orpyt?
```

Body:

```text
Your valuable feedback helps motivate us to keep improving Orpyt and bring more thoughtful features for people working across time zones.
```

Buttons:
- `Rate on the App Store`
- `Not now`
- `Suggest a Feature`

### Visual Polish

Implemented or planned:
- Colored labels and meeting accents.
- Primary clock purple accent.
- Secondary clock blue accent.
- Meeting rows rotate through purple, blue, green, amber.
- Clock/weather icons tinted by accent.
- Next Meeting card has accent wash.
- Today’s Plan rows have colored bars/dots.

Scrollbar issue:
- User disliked visible right scrollbar in popover.
- Direction was to use native behavior and show only when scrolling.

Sticky toolbar:
- Popover top toolbar/search/filter/power row should use a native macOS sticky/header feel with subtle shadow.

### Menu Bar Customization

Recent request:
- Redesign Menu Bar settings to feel more native.
- Restore drag-to-reorder because arrow controls felt worse.
- Make preview sticky so changes are visible immediately.
- Do not append random controls; structure settings around what already exists.
- Meeting/imminent pill preview should open Calendar settings.

Current source direction:
- `MenuBarPane` has sticky `PowerMenuBarPreview`.
- Layout rows are drag/drop.
- Display controls are split into proper rows:
  - Zone labels
  - 24-hour time
  - Seconds
  - Icon mode
  - Separator
  - Spacing
- Calendar Indicator card links to Calendar settings.

Important build note:
- `swift build` updates `.build/debug/Orpyt`, but the user was opening `.build/Orpyt.app`, which was stale.
- Use `./build-app.sh` to rebuild the actual `.app` bundle.
- Then open:

```sh
open -n /Users/aihtsham/Documents/dataflow-finance/macos/Orpyt/.build/Orpyt.app
```

Last known verification:
- `swift test` passed with 112 tests.
- `git diff --check` passed.
- `./build-app.sh` completed and rebuilt `.build/Orpyt.app` and `dist/Orpyt.app`.

## App Store / Release Notes Context

Versioning:
- Apple rejected a new build with `CFBundleShortVersionString` still at `1.0.0`.
- Need version higher than previously approved.
- User asked why `1.2` not `1.0.2`; use semantic versioning based on release importance.
- Calendar/menu bar customization release could reasonably be `1.1` or `1.2`.

User is building/uploading from Xcode.

The app initially appeared paid because the app-level price schedule was set to a non-free price (`£1.99` / equivalent), even though subscriptions existed separately. If the app should be free with Pro subscriptions, app-level pricing must be Free in Pricing and Availability.

Subscriptions:
- It is okay that “In-App Purchases” separate create area is empty if Auto-Renewable Subscriptions already exist.
- Subscriptions live under subscription groups.

## Reddit / Launch Messaging

Reddit post was filtered/removed. Likely causes:
- New/low-trust account.
- Direct App Store link.
- Promotional/pricing language.
- Too-polished supportive comments.
- Subreddit self-promo rules.

Moderator message drafted:

```text
Hi mods,

My post about a Mac menu bar app I built for remote workers was removed by Reddit’s filters. I’m the developer, and my goal was to get genuine feedback from people who work across time zones, not to spam the community.

I’m happy to edit the post, remove the App Store link, avoid pricing, or repost it as a feedback-only discussion if that fits the rules.

Could you please let me know what would be acceptable for r/remotework?

Thanks.
```

Short reply to a skeptical commenter:

```text
Fair call to be skeptical. It’s a real Mac app I built, not a bot post, but I get why promo posts can feel noisy. If you’re open to it, have a quick look and come back with genuine feedback or criticism. I’d rather hear what feels off than pretend everything is perfect.
```

Recommended public launch angle:

```text
I built a Mac menu bar app for people who live across time zones and meetings.
```

Avoid:

```text
I built a productivity app with weather and customization.
```

## Growth Diagnosis

Current App Store Connect numbers discussed:
- First-time downloads: `1`
- Conversion rate: `4.76%`
- Daily average impressions: `51`
- Product page views: `12`
- Monetization: not enough data

Interpretation:
- Discovery is low but expected for a new app.
- Product page views show some curiosity.
- Conversion is weak because the listing does not yet make the problem/value obvious enough.

Core issue:

> The app is good, but the listing currently sells “timezone utility” instead of “avoid awkward timing mistakes across remote work.”

Do not over-optimize paywall yet. The first job is more qualified free downloads, then reviews, then gentle Pro conversion.

## Recommended Next Actions

1. Update App Store title/subtitle/promotional text/keywords.
2. Replace first screenshots with pain-led sequence.
3. Rebuild screenshots from current UI, not the older blurred App Store screenshots.
4. Make the free value obvious in App Store copy and onboarding.
5. Keep Pro pricing low for now.
6. Ask real users for App Store reviews only after repeated value moments.
7. Post on Reddit/Indie Hackers/Product Hunt only after listing and screenshots are stronger.
8. For local app verification, always run `./build-app.sh` before opening `.build/Orpyt.app`.

## Important Local Repo Notes

Repository:

```text
/Users/aihtsham/Documents/dataflow-finance/macos/Orpyt
```

AGENTS instruction:
- Always use code-review-graph MCP tools before grep/read/exploration.

Known local worktree has multiple modified and added files from ongoing work. Do not revert unrelated changes.

Useful commands:

```sh
swift test
git diff --check
./build-app.sh
pkill -x Orpyt
open -n /Users/aihtsham/Documents/dataflow-finance/macos/Orpyt/.build/Orpyt.app
```

Key files recently touched:
- `Sources/OrpytCore/SettingsViews.swift`
- `Sources/OrpytCore/Stores.swift`
- `Sources/OrpytCore/Utilities.swift`
- `Sources/App/OrpytApp.swift`
- `Sources/OrpytCore/SubscriptionStore.swift`
- `Tests/OrpytTests/ClockFormatterTests.swift`
- `Tests/OrpytTests/ClockSettingsStoreTests.swift`
- `Marketing/AppStore/Screenshots/generate_appstore_screenshots.py`
- Generated screenshot PNGs under `Marketing/AppStore/Screenshots/Generated/`

