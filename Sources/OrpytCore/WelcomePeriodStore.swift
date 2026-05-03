import Foundation
import SwiftUI

@MainActor
public final class WelcomePeriodStore: ObservableObject {
    public static let shared = WelcomePeriodStore()

    private let defaults = UserDefaults.standard
    private let firstLaunchKey = "orpyt.firstLaunchDate"
    private let debugOverrideKey = "orpyt.debug.welcomeDayOverride"
    private let welcomeDays = 14

    private let firstLaunchDate: Date

    @Published public private(set) var daysRemaining: Int
    @Published public private(set) var isInWelcomePeriod: Bool
    @Published public private(set) var hasExpired: Bool

    private init() {
        let stored = defaults.object(forKey: firstLaunchKey) as? Date
        let date = stored ?? Date()
        if stored == nil {
            defaults.set(date, forKey: firstLaunchKey)
        }
        firstLaunchDate = date

        let remaining = Self.computeRemaining(
            firstLaunchDate: date,
            welcomeDays: 14,
            defaults: UserDefaults.standard,
            debugOverrideKey: "orpyt.debug.welcomeDayOverride"
        )
        daysRemaining = remaining
        isInWelcomePeriod = remaining > 0
        hasExpired = remaining == 0
    }

    public func refresh() {
        let remaining = Self.computeRemaining(
            firstLaunchDate: firstLaunchDate,
            welcomeDays: welcomeDays,
            defaults: defaults,
            debugOverrideKey: debugOverrideKey
        )
        daysRemaining = remaining
        isInWelcomePeriod = remaining > 0
        hasExpired = remaining == 0
    }

    /// Debug only — simulate being on a specific day (1 = first day, 14 = last day, 15 = expired).
    /// Pass nil to clear the override and use real elapsed time.
    public func debugSetDay(_ day: Int?) {
        #if DEBUG
        if let day {
            defaults.set(day, forKey: debugOverrideKey)
        } else {
            defaults.removeObject(forKey: debugOverrideKey)
        }
        refresh()
        #endif
    }

    private static func computeRemaining(
        firstLaunchDate: Date,
        welcomeDays: Int,
        defaults: UserDefaults,
        debugOverrideKey: String
    ) -> Int {
        #if DEBUG
        if let override = defaults.object(forKey: debugOverrideKey) as? Int {
            // day 1 = 14 remaining, day 14 = 1 remaining, day 15+ = 0
            return max(0, welcomeDays - (override - 1))
        }
        #endif
        let elapsed = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
        return max(0, welcomeDays - elapsed)
    }

    public var shouldShowPopoverReminder: Bool {
        // Silent first 3 days — let them enjoy Pro without pressure
        let dayNumber = 14 - daysRemaining + 1
        return dayNumber >= 4 || hasExpired
    }

    public var popoverReminderText: String {
        if hasExpired {
            return "✦  Your free trial ended — subscribe to keep Pro"
        }
        switch daysRemaining {
        case 1: return "✦  Last day of free access"
        case 2, 3: return "✦  \(daysRemaining) days left — keep Orpyt Pro?"
        case 4, 5, 6, 7: return "✦  \(daysRemaining) days of free Pro left"
        default:
            let day = 14 - daysRemaining + 1
            return "✦  Pro access — Day \(day) of 14"
        }
    }

    public var popoverReminderPillText: String? {
        if hasExpired { return "Subscribe →" }
        if daysRemaining <= 4 { return "Keep it →" }
        return nil
    }

    public var popoverReminderColor: PopoverReminderColor {
        if hasExpired { return .red }
        switch daysRemaining {
        case 1, 2: return .orange
        case 3, 4: return .warning
        default: return .accent
        }
    }

    public enum PopoverReminderColor {
        case accent, warning, orange, red
    }

    public func bannerMessage(yearlyPrice: String = "$1.67/mo") -> String {
        switch daysRemaining {
        case 0:
            return "Free trial ended. Keep Pro from \(yearlyPrice) — cancel any time."
        case 1:
            return "Last day free. Keep everything from \(yearlyPrice) — cancel any time."
        case 2, 3:
            return "\(daysRemaining) days left. Keep Pro from \(yearlyPrice) — cancel in one tap."
        default:
            return "Day \(14 - daysRemaining + 1) of 14 — enjoying Pro free. From \(yearlyPrice)."
        }
    }

    public var urgencyLevel: UrgencyLevel {
        switch daysRemaining {
        case 0: return .expired
        case 1, 2: return .critical
        case 3, 4, 5: return .warning
        default: return .neutral
        }
    }

    public enum UrgencyLevel {
        case neutral, warning, critical, expired
    }
}
