import Foundation

public enum ReviewValueMoment: String, CaseIterable {
    case twoClocksVisible
    case weatherLoaded
    case calendarLoadedMeeting
    case todayPlanOpened
    case timeScrollerUsed
}

@MainActor
public final class ReviewPromptStore: ObservableObject {
    public static let shared = ReviewPromptStore()
    public static let suggestionsURL = URL(string: "https://github.com/aihtshamali/orpyt/discussions")!

    private enum Keys {
        static let firstSeenDate = "reviewPrompt.firstSeenDate"
        static let launchCount = "reviewPrompt.launchCount"
        static let valueMoments = "reviewPrompt.valueMoments"
        static let lastReviewPromptAttempt = "reviewPrompt.lastReviewPromptAttempt"
        static let lastSuggestionPromptDismissal = "reviewPrompt.lastSuggestionPromptDismissal"
        static let promptAttemptYear = "reviewPrompt.promptAttemptYear"
        static let yearlyPromptAttemptCount = "reviewPrompt.yearlyPromptAttemptCount"
    }

    private let defaults: UserDefaults
    private let commerceMode: AppCommerceMode
    private let now: () -> Date
    private let calendar: Calendar

    public init(
        defaults: UserDefaults = .standard,
        commerceMode: AppCommerceMode = .current,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.commerceMode = commerceMode
        self.calendar = calendar
        self.now = now

        if defaults.object(forKey: Keys.firstSeenDate) == nil {
            defaults.set(now(), forKey: Keys.firstSeenDate)
        }
    }

    public var launchCount: Int {
        defaults.integer(forKey: Keys.launchCount)
    }

    public var valueMomentCount: Int {
        valueMoments.count
    }

    public func recordLaunch() {
        if defaults.object(forKey: Keys.firstSeenDate) == nil {
            defaults.set(now(), forKey: Keys.firstSeenDate)
        }
        defaults.set(launchCount + 1, forKey: Keys.launchCount)
    }

    public func recordValueMoment(_ moment: ReviewValueMoment) {
        var moments = valueMoments
        moments.insert(moment.rawValue)
        defaults.set(Array(moments), forKey: Keys.valueMoments)
    }

    public func shouldPresentReviewPrompt(hasActiveFriction: Bool, hasActiveMeetingAlert: Bool) -> Bool {
        guard commerceMode.supportsAppStoreCommerce else { return false }
        guard launchCount >= 5 else { return false }
        guard daysSinceFirstSeen >= 3 else { return false }
        guard valueMomentCount >= 2 else { return false }
        guard !hasActiveFriction, !hasActiveMeetingAlert else { return false }
        guard daysSince(Keys.lastReviewPromptAttempt, minimumDays: 90) else { return false }
        guard daysSince(Keys.lastSuggestionPromptDismissal, minimumDays: 30) else { return false }
        return yearlyPromptAttemptCount < 3
    }

    public func recordReviewPromptAttempt() {
        normalizeYearlyPromptAttemptCount()
        defaults.set(now(), forKey: Keys.lastReviewPromptAttempt)
        defaults.set(currentYear, forKey: Keys.promptAttemptYear)
        defaults.set(yearlyPromptAttemptCount + 1, forKey: Keys.yearlyPromptAttemptCount)
    }

    public func recordPromptDismissal() {
        defaults.set(now(), forKey: Keys.lastSuggestionPromptDismissal)
    }

    private var valueMoments: Set<String> {
        Set(defaults.stringArray(forKey: Keys.valueMoments) ?? [])
    }

    private var firstSeenDate: Date {
        defaults.object(forKey: Keys.firstSeenDate) as? Date ?? now()
    }

    private var daysSinceFirstSeen: Int {
        calendar.dateComponents([.day], from: firstSeenDate, to: now()).day ?? 0
    }

    private var currentYear: Int {
        calendar.component(.year, from: now())
    }

    private var yearlyPromptAttemptCount: Int {
        normalizeYearlyPromptAttemptCount()
        return defaults.integer(forKey: Keys.yearlyPromptAttemptCount)
    }

    private func normalizeYearlyPromptAttemptCount() {
        let storedYear = defaults.integer(forKey: Keys.promptAttemptYear)
        guard storedYear == currentYear else {
            defaults.set(currentYear, forKey: Keys.promptAttemptYear)
            defaults.set(0, forKey: Keys.yearlyPromptAttemptCount)
            return
        }
    }

    private func daysSince(_ key: String, minimumDays: Int) -> Bool {
        guard let date = defaults.object(forKey: key) as? Date else { return true }
        let elapsed = calendar.dateComponents([.day], from: date, to: now()).day ?? 0
        return elapsed >= minimumDays
    }
}
