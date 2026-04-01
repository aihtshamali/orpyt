import Testing
import Foundation
@testable import OrpytCore

@Suite("TimeZoneSearchProvider")
struct TimeZoneSearchProviderTests {

    // MARK: results(for:suggestions:)

    @Test("empty query returns suggested cities from identifiers")
    func emptyQueryReturnsSuggestions() {
        let suggestions = ["America/New_York", "Asia/Karachi"]
        let results = TimeZoneSearchProvider.results(for: "", suggestions: suggestions)
        #expect(!results.isEmpty)
        #expect(results.contains { $0.id == "America/New_York" })
        #expect(results.contains { $0.id == "Asia/Karachi" })
    }

    @Test("whitespace-only query is treated as empty")
    func whitespaceQueryTreatedAsEmpty() {
        let suggestions = ["America/New_York"]
        let withSpaces = TimeZoneSearchProvider.results(for: "   ", suggestions: suggestions)
        let empty = TimeZoneSearchProvider.results(for: "", suggestions: suggestions)
        #expect(withSpaces.map(\.id) == empty.map(\.id))
    }

    @Test("query matching a city name returns that city")
    func queryMatchesCityName() {
        let results = TimeZoneSearchProvider.results(for: "Karachi", suggestions: [])
        #expect(results.contains { $0.id == "Asia/Karachi" })
    }

    @Test("query is case-insensitive")
    func queryIsCaseInsensitive() {
        let lower = TimeZoneSearchProvider.results(for: "karachi", suggestions: [])
        let upper = TimeZoneSearchProvider.results(for: "KARACHI", suggestions: [])
        #expect(lower.map(\.id) == upper.map(\.id))
    }

    @Test("limit caps result count")
    func limitCapsResults() {
        let results = TimeZoneSearchProvider.results(for: "a", suggestions: [], limit: 3)
        #expect(results.count <= 3)
    }

    @Test("default limit is 8")
    func defaultLimitIsEight() {
        let results = TimeZoneSearchProvider.results(for: "a", suggestions: [])
        #expect(results.count <= 8)
    }

    @Test("nonsense query returns empty results")
    func nonsenseQueryReturnsEmpty() {
        let results = TimeZoneSearchProvider.results(for: "zzzzzzzznotacity", suggestions: [])
        #expect(results.isEmpty)
    }

    @Test("query matching timezone identifier works")
    func queryMatchesIdentifier() {
        let results = TimeZoneSearchProvider.results(for: "Asia/Dubai", suggestions: [])
        #expect(results.contains { $0.id == "Asia/Dubai" })
    }

    // MARK: suggested(from:)

    @Test("suggested deduplicates repeated identifiers")
    func suggestedDeduplicates() {
        let suggestions = ["America/New_York", "America/New_York", "Asia/Karachi"]
        let results = TimeZoneSearchProvider.suggested(from: suggestions)
        let ids = results.map(\.id)
        #expect(ids.filter { $0 == "America/New_York" }.count == 1)
    }

    @Test("suggested skips unknown identifiers gracefully")
    func suggestedSkipsUnknown() {
        let suggestions = ["Not/AReal/Zone", "America/New_York"]
        let results = TimeZoneSearchProvider.suggested(from: suggestions)
        #expect(results.contains { $0.id == "America/New_York" })
        #expect(!results.contains { $0.id == "Not/AReal/Zone" })
    }

    @Test("suggested preserves input order")
    func suggestedPreservesOrder() {
        let suggestions = ["Asia/Tokyo", "Europe/London", "America/Chicago"]
        let results = TimeZoneSearchProvider.suggested(from: suggestions)
        let ids = results.map(\.id)
        let tokyoIdx = ids.firstIndex(of: "Asia/Tokyo") ?? Int.max
        let londonIdx = ids.firstIndex(of: "Europe/London") ?? Int.max
        let chicagoIdx = ids.firstIndex(of: "America/Chicago") ?? Int.max
        #expect(tokyoIdx < londonIdx)
        #expect(londonIdx < chicagoIdx)
    }

    @Test("empty suggestions list returns empty array")
    func emptySuggestionsReturnsEmpty() {
        let results = TimeZoneSearchProvider.suggested(from: [])
        #expect(results.isEmpty)
    }
}
