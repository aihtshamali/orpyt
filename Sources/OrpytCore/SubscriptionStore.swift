import AppKit
import Foundation
import StoreKit
import SwiftUI

public enum AppCommerceMode: String, Codable, Equatable {
    case directDistribution
    case appStore

    public static var current: AppCommerceMode {
        #if DIRECT_DISTRIBUTION
        return .directDistribution
        #else
        return .appStore
        #endif
    }

    public var supportsDirectUpdates: Bool {
        self == .directDistribution
    }

    public var supportsAppStoreCommerce: Bool {
        self == .appStore
    }
}

public enum OrpytProFeature: String, CaseIterable, Identifiable, Codable {
    case weather
    case calendar
    case timeScroller
    case appearance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weather:
            return "Live Weather"
        case .calendar:
            return "Calendar Context"
        case .timeScroller:
            return "Time Scroller"
        case .appearance:
            return "Advanced Appearance"
        }
    }

    public var symbolName: String {
        switch self {
        case .weather:
            return "cloud.sun.fill"
        case .calendar:
            return "calendar"
        case .timeScroller:
            return "clock.arrow.circlepath"
        case .appearance:
            return "sparkles"
        }
    }

    public var summary: String {
        switch self {
        case .weather:
            return "Weather on clock cards and menu bar status icons."
        case .calendar:
            return "Read-only next meeting context in the popover."
        case .timeScroller:
            return "Scrub forward or backward across time zones."
        case .appearance:
            return "Custom visual themes, polish, and premium controls."
        }
    }
}

public enum SubscriptionEntitlementState: String, Codable, CaseIterable, Identifiable {
    case free
    case trial
    case active
    case gracePeriod
    case billingRetry
    case expired

    public var id: String { rawValue }

    public var hasProAccess: Bool {
        switch self {
        case .trial, .active, .gracePeriod, .billingRetry:
            return true
        case .free, .expired:
            return false
        }
    }

    public var title: String {
        switch self {
        case .free:
            return "Free"
        case .trial:
            return "Trial"
        case .active:
            return "Active"
        case .gracePeriod:
            return "Grace Period"
        case .billingRetry:
            return "Billing Retry"
        case .expired:
            return "Expired"
        }
    }
}

public enum SubscriptionPlanID: String, CaseIterable, Identifiable, Codable {
    case monthly = "com.orpyt.pro.monthly"
    case yearly = "com.orpyt.pro.yearly"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }

    public var marketingTitle: String {
        switch self {
        case .monthly:
            return "Orpyt Pro Monthly"
        case .yearly:
            return "Orpyt Pro Yearly"
        }
    }

    public var subtitle: String {
        switch self {
        case .monthly:
            return "Flexible access with a 7-day free trial."
        case .yearly:
            return "Best value for everyday cross-time-zone work."
        }
    }

    public var isRecommended: Bool {
        self == .yearly
    }

    public var fallbackPriceText: String {
        switch self {
        case .monthly:
            return "$2.99 / month"
        case .yearly:
            return "$19.99 / year"
        }
    }
}

public struct SubscriptionPlanDescriptor: Identifiable, Equatable {
    public let id: SubscriptionPlanID
    public let title: String
    public let subtitle: String
    public let priceText: String
    public let isRecommended: Bool

    public init(id: SubscriptionPlanID, title: String, subtitle: String, priceText: String, isRecommended: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.priceText = priceText
        self.isRecommended = isRecommended
    }
}

@MainActor
public final class SubscriptionStore: ObservableObject {
    public static let shared = SubscriptionStore()

    @Published public private(set) var commerceMode: AppCommerceMode
    @Published public private(set) var entitlementState: SubscriptionEntitlementState
    @Published public private(set) var activePlanID: SubscriptionPlanID?
    @Published public private(set) var renewalDate: Date?
    @Published public private(set) var expirationDate: Date?
    @Published public private(set) var willAutoRenew = false
    @Published public private(set) var statusMessage: String
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var isLoadingProducts = false
    @Published public private(set) var isProcessingPurchase = false
    @Published public private(set) var availablePlans: [SubscriptionPlanDescriptor]
    @Published public var highlightedFeature: OrpytProFeature?
    @Published public var showProSheet = false
    @Published public private(set) var yearlyMonthlyEquivalent: String = "$1.67/mo"

    private let defaults = UserDefaults.standard
    private var products: [SubscriptionPlanID: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    private enum PersistenceKeys {
        static let entitlementState = "subscription.entitlementState"
        static let activePlanID = "subscription.activePlanID"
        static let renewalDate = "subscription.renewalDate"
        static let expirationDate = "subscription.expirationDate"
        static let willAutoRenew = "subscription.willAutoRenew"
        static let statusMessage = "subscription.statusMessage"
    }

    private init() {
        commerceMode = AppCommerceMode.current
        entitlementState = .free
        statusMessage = "Free during trial, then Orpyt Pro."
        availablePlans = SubscriptionPlanID.allCases.map {
            SubscriptionPlanDescriptor(
                id: $0,
                title: $0.marketingTitle,
                subtitle: $0.subtitle,
                priceText: $0.fallbackPriceText,
                isRecommended: $0.isRecommended
            )
        }

        loadPersistedSnapshot()

        if commerceMode == .directDistribution {
            applyDirectDistributionState()
        } else {
            updateStatusMessage()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func prepareForLaunch() {
        guard commerceMode.supportsAppStoreCommerce else {
            applyDirectDistributionState()
            return
        }

        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                await self?.listenForTransactions()
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    public func hasAccess(to feature: OrpytProFeature) -> Bool {
        if commerceMode == .directDistribution { return true }
        if entitlementState.hasProAccess { return true }
        return WelcomePeriodStore.shared.isInWelcomePeriod
    }

    public var supportsDirectUpdates: Bool {
        commerceMode.supportsDirectUpdates
    }

    public var shouldShowUpgradeActions: Bool {
        commerceMode.supportsAppStoreCommerce
    }

    public var displayPlanName: String {
        activePlanID?.title ?? "Orpyt Pro"
    }

    public var entitlementSummary: String {
        if commerceMode == .directDistribution {
            return "Direct download build"
        }
        return entitlementState.title
    }

    public func focus(on feature: OrpytProFeature?) {
        highlightedFeature = feature
        if feature != nil { showProSheet = true }
    }

    public func purchase(planID: SubscriptionPlanID) async {
        guard commerceMode.supportsAppStoreCommerce else {
            #if DEBUG
            lastErrorMessage = "StoreKit is unavailable in this build. Use the App Store version to subscribe."
            #else
            applyDirectDistributionState()
            #endif
            return
        }

        if products[planID] == nil {
            await loadProducts()
        }

        guard let product = products[planID] else {
            lastErrorMessage = "Could not load this subscription from the App Store. Please check your internet connection and try again. If the problem persists, the subscription may not yet be approved in App Store Connect."
            return
        }

        isProcessingPurchase = true
        lastErrorMessage = nil
        defer { isProcessingPurchase = false }

        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                guard let transaction = verified(verification) else {
                    lastErrorMessage = "The App Store couldn’t verify your purchase."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                statusMessage = "Purchase is pending approval."
            @unknown default:
                statusMessage = "Purchase is still being processed."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func restorePurchases() async {
        guard commerceMode.supportsAppStoreCommerce else {
            applyDirectDistributionState()
            return
        }

        isProcessingPurchase = true
        lastErrorMessage = nil
        defer { isProcessingPurchase = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = entitlementState.hasProAccess
                ? "Your Orpyt Pro access has been restored."
                : "No active Orpyt Pro subscription was found for this Apple Account."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func manageSubscriptions() {
        guard commerceMode.supportsAppStoreCommerce,
              let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func redeemOfferCode() {
        guard commerceMode.supportsAppStoreCommerce,
              let url = URL(string: "https://apps.apple.com/redeem?ctx=offercodes") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func refundSupport() {
        guard let url = URL(string: "https://support.apple.com/en-gb/118223") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func refreshEntitlements() async {
        guard commerceMode.supportsAppStoreCommerce else {
            applyDirectDistributionState()
            return
        }

        lastErrorMessage = nil

        if products.isEmpty {
            await loadProducts()
        }

        let statuses = await collectStatuses()
        if let status = pickBestStatus(from: statuses) {
            apply(status: status)
            return
        }

        var newestTransaction: StoreKit.Transaction?
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard let transaction = verified(entitlement),
                  let planID = SubscriptionPlanID(rawValue: transaction.productID) else {
                continue
            }

            if newestTransaction == nil || (transaction.expirationDate ?? .distantPast) > (newestTransaction?.expirationDate ?? .distantPast) {
                newestTransaction = transaction
                activePlanID = planID
            }
        }

        if let transaction = newestTransaction {
            activePlanID = SubscriptionPlanID(rawValue: transaction.productID)
            expirationDate = transaction.expirationDate
            renewalDate = transaction.expirationDate
            willAutoRenew = transaction.revocationDate == nil
            entitlementState = (transaction.expirationDate ?? .distantFuture) > Date() ? .active : .expired
            updateStatusMessage()
            persistSnapshot()
            return
        }

        activePlanID = nil
        renewalDate = nil
        expirationDate = nil
        willAutoRenew = false
        entitlementState = .free
        updateStatusMessage()
        persistSnapshot()
    }

    private func loadPersistedSnapshot() {
        if let rawState = defaults.string(forKey: PersistenceKeys.entitlementState),
           let persistedState = SubscriptionEntitlementState(rawValue: rawState) {
            entitlementState = persistedState
        }

        if let rawPlan = defaults.string(forKey: PersistenceKeys.activePlanID) {
            activePlanID = SubscriptionPlanID(rawValue: rawPlan)
        }

        renewalDate = defaults.object(forKey: PersistenceKeys.renewalDate) as? Date
        expirationDate = defaults.object(forKey: PersistenceKeys.expirationDate) as? Date
        willAutoRenew = defaults.object(forKey: PersistenceKeys.willAutoRenew) as? Bool ?? false
        if let persistedMessage = defaults.string(forKey: PersistenceKeys.statusMessage), !persistedMessage.isEmpty {
            statusMessage = persistedMessage
        }
    }

    private func persistSnapshot() {
        defaults.set(entitlementState.rawValue, forKey: PersistenceKeys.entitlementState)
        defaults.set(activePlanID?.rawValue, forKey: PersistenceKeys.activePlanID)
        defaults.set(renewalDate, forKey: PersistenceKeys.renewalDate)
        defaults.set(expirationDate, forKey: PersistenceKeys.expirationDate)
        defaults.set(willAutoRenew, forKey: PersistenceKeys.willAutoRenew)
        defaults.set(statusMessage, forKey: PersistenceKeys.statusMessage)
    }

    private func applyDirectDistributionState() {
        activePlanID = .yearly
        renewalDate = nil
        expirationDate = nil
        willAutoRenew = false
        entitlementState = .active
        statusMessage = "Direct download builds stay fully unlocked while App Store subscriptions are being rolled out."
        lastErrorMessage = nil
        persistSnapshot()
    }

    private func loadProducts() async {
        guard commerceMode.supportsAppStoreCommerce else { return }
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetchedProducts = try await Product.products(for: SubscriptionPlanID.allCases.map(\.rawValue))
            var mappedProducts: [SubscriptionPlanID: Product] = [:]
            for product in fetchedProducts {
                guard let planID = SubscriptionPlanID(rawValue: product.id) else { continue }
                mappedProducts[planID] = product
            }
            products = mappedProducts
            availablePlans = SubscriptionPlanID.allCases.map { planID in
                SubscriptionPlanDescriptor(
                    id: planID,
                    title: planID.marketingTitle,
                    subtitle: planID.subtitle,
                    priceText: mappedProducts[planID]?.displayPrice ?? planID.fallbackPriceText,
                    isRecommended: planID.isRecommended
                )
            }
            if let yearlyProduct = mappedProducts[.yearly] {
                let monthlyEquiv = yearlyProduct.price / 12
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = yearlyProduct.priceFormatStyle.locale
                if let formatted = formatter.string(from: NSDecimalNumber(decimal: monthlyEquiv)) {
                    yearlyMonthlyEquivalent = "\(formatted)/mo"
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func collectStatuses() async -> [Product.SubscriptionInfo.Status] {
        var statuses: [Product.SubscriptionInfo.Status] = []
        for planID in SubscriptionPlanID.allCases {
            guard let subscription = products[planID]?.subscription else { continue }
            if let currentStatuses = try? await subscription.status {
                statuses.append(contentsOf: currentStatuses)
            }
        }
        return statuses
    }

    private func pickBestStatus(from statuses: [Product.SubscriptionInfo.Status]) -> Product.SubscriptionInfo.Status? {
        statuses.sorted {
            let lhsDate = verified($0.transaction)?.expirationDate ?? .distantPast
            let rhsDate = verified($1.transaction)?.expirationDate ?? .distantPast
            let lhsRank = stateRank(for: $0.state)
            let rhsRank = stateRank(for: $1.state)
            if lhsRank == rhsRank {
                return lhsDate > rhsDate
            }
            return lhsRank < rhsRank
        }.first
    }

    private func stateRank(for state: Product.SubscriptionInfo.RenewalState) -> Int {
        switch state {
        case .subscribed:
            return 0
        case .inGracePeriod:
            return 1
        case .inBillingRetryPeriod:
            return 2
        case .expired:
            return 3
        default:
            return 4
        }
    }

    private func apply(status: Product.SubscriptionInfo.Status) {
        let transaction = verified(status.transaction)

        activePlanID = transaction.flatMap { SubscriptionPlanID(rawValue: $0.productID) }
        renewalDate = transaction?.expirationDate
        expirationDate = transaction?.expirationDate
        willAutoRenew = status.state == .subscribed || status.state == .inGracePeriod || status.state == .inBillingRetryPeriod

        switch status.state {
        case .subscribed:
            if transaction?.offerType == .introductory {
                entitlementState = .trial
            } else {
                entitlementState = .active
            }
        case .inGracePeriod:
            entitlementState = .gracePeriod
        case .inBillingRetryPeriod:
            entitlementState = .billingRetry
        case .expired:
            entitlementState = .expired
        default:
            entitlementState = .free
        }

        updateStatusMessage()
        persistSnapshot()
    }

    private func listenForTransactions() async {
        for await update in StoreKit.Transaction.updates {
            guard let transaction = verified(update) else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func updateStatusMessage() {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        switch entitlementState {
        case .free:
            statusMessage = "Start a 7-day free trial, then continue with Orpyt Pro."
        case .trial:
            if let renewalDate {
                statusMessage = "Your free trial renews \(formatter.localizedString(for: renewalDate, relativeTo: Date()))."
            } else {
                statusMessage = "Your free trial is active."
            }
        case .active:
            if let renewalDate {
                statusMessage = willAutoRenew
                    ? "Orpyt Pro renews \(formatter.localizedString(for: renewalDate, relativeTo: Date()))."
                    : "Orpyt Pro stays active until \(formatted(date: renewalDate))."
            } else {
                statusMessage = "Orpyt Pro is active."
            }
        case .gracePeriod:
            if let renewalDate {
                statusMessage = "Billing needs attention. Access stays on until \(formatted(date: renewalDate))."
            } else {
                statusMessage = "Billing needs attention. Orpyt Pro is in grace period."
            }
        case .billingRetry:
            statusMessage = "Apple is retrying your renewal. Access may pause if billing isn’t resolved."
        case .expired:
            if let expirationDate {
                statusMessage = "Your Orpyt Pro access expired \(formatter.localizedString(for: expirationDate, relativeTo: Date()))."
            } else {
                statusMessage = "Your Orpyt Pro access has expired."
            }
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case let .verified(value):
            return value
        case .unverified:
            return nil
        }
    }
}
