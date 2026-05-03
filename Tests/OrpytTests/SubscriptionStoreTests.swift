import Testing
@testable import OrpytCore

@Suite("SubscriptionCommerce")
struct SubscriptionCommerceTests {

    @Test("trial and active states unlock Pro access")
    func paidStatesUnlockPro() {
        #expect(SubscriptionEntitlementState.trial.hasProAccess == true)
        #expect(SubscriptionEntitlementState.active.hasProAccess == true)
        #expect(SubscriptionEntitlementState.gracePeriod.hasProAccess == true)
        #expect(SubscriptionEntitlementState.billingRetry.hasProAccess == true)
    }

    @Test("free and expired states do not unlock Pro access")
    func freeStatesStayLocked() {
        #expect(SubscriptionEntitlementState.free.hasProAccess == false)
        #expect(SubscriptionEntitlementState.expired.hasProAccess == false)
    }

    @Test("yearly plan stays the recommended launch offer")
    func yearlyPlanRecommended() {
        #expect(SubscriptionPlanID.yearly.isRecommended == true)
        #expect(SubscriptionPlanID.monthly.isRecommended == false)
    }

    @Test("direct distribution supports updates while App Store mode supports commerce")
    func commerceModesExposeExpectedCapabilities() {
        #expect(AppCommerceMode.directDistribution.supportsDirectUpdates == true)
        #expect(AppCommerceMode.directDistribution.supportsAppStoreCommerce == false)
        #expect(AppCommerceMode.appStore.supportsDirectUpdates == false)
        #expect(AppCommerceMode.appStore.supportsAppStoreCommerce == true)
    }
}
