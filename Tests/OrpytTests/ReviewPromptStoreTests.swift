import Foundation
import Testing
@testable import OrpytCore

@Suite("ReviewPromptStore")
@MainActor
struct ReviewPromptStoreTests {
    @Test("too early does not prompt even with enough launches and value")
    func tooEarlyDoesNotPrompt() {
        var now = date(day: 1)
        let store = makeStore(mode: .appStore, now: { now })

        recordLaunches(5, in: store)
        store.recordValueMoment(.twoClocksVisible)
        store.recordValueMoment(.weatherLoaded)
        now = date(day: 3)

        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: false, hasActiveMeetingAlert: false) == false)
    }

    @Test("enough launches and value moments becomes eligible")
    func enoughLaunchesAndValueBecomesEligible() {
        var now = date(day: 1)
        let store = makeStore(mode: .appStore, now: { now })

        recordLaunches(5, in: store)
        store.recordValueMoment(.twoClocksVisible)
        store.recordValueMoment(.calendarLoadedMeeting)
        now = date(day: 5)

        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: false, hasActiveMeetingAlert: false) == true)
    }

    @Test("recent prompt attempt blocks eligibility")
    func recentPromptBlocksEligibility() {
        var now = date(day: 1)
        let store = makeStore(mode: .appStore, now: { now })

        recordLaunches(5, in: store)
        store.recordValueMoment(.twoClocksVisible)
        store.recordValueMoment(.timeScrollerUsed)
        now = date(day: 5)
        store.recordReviewPromptAttempt()
        now = date(day: 30)

        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: false, hasActiveMeetingAlert: false) == false)
    }

    @Test("direct distribution never auto prompts StoreKit")
    func directDistributionNeverPrompts() {
        var now = date(day: 1)
        let store = makeStore(mode: .directDistribution, now: { now })

        recordLaunches(10, in: store)
        store.recordValueMoment(.twoClocksVisible)
        store.recordValueMoment(.calendarLoadedMeeting)
        now = date(day: 10)

        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: false, hasActiveMeetingAlert: false) == false)
    }

    @Test("friction and active meeting alerts block eligibility")
    func frictionAndMeetingAlertsBlockEligibility() {
        var now = date(day: 1)
        let store = makeStore(mode: .appStore, now: { now })

        recordLaunches(5, in: store)
        store.recordValueMoment(.twoClocksVisible)
        store.recordValueMoment(.weatherLoaded)
        now = date(day: 5)

        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: true, hasActiveMeetingAlert: false) == false)
        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: false, hasActiveMeetingAlert: true) == false)
    }

    @Test("dismissal creates a cooldown")
    func dismissalCreatesCooldown() {
        var now = date(day: 1)
        let store = makeStore(mode: .appStore, now: { now })

        recordLaunches(5, in: store)
        store.recordValueMoment(.twoClocksVisible)
        store.recordValueMoment(.todayPlanOpened)
        now = date(day: 5)
        store.recordPromptDismissal()
        now = date(day: 20)

        #expect(store.shouldPresentReviewPrompt(hasActiveFriction: false, hasActiveMeetingAlert: false) == false)
    }

    private func makeStore(mode: AppCommerceMode, now: @escaping () -> Date) -> ReviewPromptStore {
        let suiteName = "ReviewPromptStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ReviewPromptStore(defaults: defaults, commerceMode: mode, calendar: Self.calendar, now: now)
    }

    private func recordLaunches(_ count: Int, in store: ReviewPromptStore) {
        for _ in 0..<count {
            store.recordLaunch()
        }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(day: Int) -> Date {
        DateComponents(calendar: Self.calendar, year: 2026, month: 1, day: day).date!
    }
}
