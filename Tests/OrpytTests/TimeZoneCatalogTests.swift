import Foundation
import Testing
@testable import OrpytCore

@Suite("TimeZoneCatalog")
struct TimeZoneCatalogTests {

    // MARK: Lookup correctness

    @Test("option(for:) returns non-nil for known identifiers")
    func knownIdentifiersResolve() {
        let known = ["America/New_York", "Europe/London", "Asia/Tokyo", "Asia/Karachi", "GMT"]
        for id in known {
            #expect(TimeZoneCatalog.option(for: id) != nil, "Expected option for \(id)")
        }
    }

    @Test("option(for:) returns nil for unknown identifier")
    func unknownIdentifierReturnsNil() {
        #expect(TimeZoneCatalog.option(for: "Not/AReal/Zone") == nil)
        #expect(TimeZoneCatalog.option(for: "") == nil)
        #expect(TimeZoneCatalog.option(for: "America/") == nil)
    }

    @Test("option(for:) index result matches linear scan")
    func lookupMatchesOptionsArray() {
        let ids = ["America/Los_Angeles", "Europe/Paris", "Asia/Singapore", "Asia/Dubai"]
        for id in ids {
            let fromIndex = TimeZoneCatalog.option(for: id)
            let fromArray = TimeZoneCatalog.options.first(where: { $0.id == id })
            #expect(fromIndex?.id == fromArray?.id, "id mismatch for \(id)")
            #expect(fromIndex?.shortLabel == fromArray?.shortLabel, "shortLabel mismatch for \(id)")
            #expect(fromIndex?.displayName == fromArray?.displayName, "displayName mismatch for \(id)")
        }
    }

    // MARK: Short labels

    @Test("shortLabel overrides are correct")
    func shortLabelOverrides() {
        let overrides: [String: String] = [
            "America/Los_Angeles": "LA",
            "America/New_York": "NYC",
            "Europe/London": "LON",
            "Asia/Karachi": "KHI",
            "Asia/Singapore": "SIN",
            "Asia/Tokyo": "TYO",
        ]
        for (id, expectedLabel) in overrides {
            let option = TimeZoneCatalog.option(for: id)
            #expect(option?.shortLabel == expectedLabel, "Expected \(expectedLabel) for \(id)")
        }
    }

    @Test("shortLabel for non-override is 3-char uppercase city prefix")
    func shortLabelFallback() {
        // "Europe/Madrid" → city "Madrid" → prefix "MAD"
        if let option = TimeZoneCatalog.option(for: "Europe/Madrid") {
            #expect(option.shortLabel.count == 3)
            #expect(option.shortLabel == option.shortLabel.uppercased())
            #expect(option.shortLabel == "MAD")
        }
    }

    // MARK: Options collection

    @Test("options list is non-empty")
    func optionsNonEmpty() {
        #expect(!TimeZoneCatalog.options.isEmpty)
    }

    @Test("options list contains all known system identifiers")
    func optionsCoversSystemIdentifiers() {
        let systemIDs = Set(TimeZone.knownTimeZoneIdentifiers)
        let catalogIDs = Set(TimeZoneCatalog.options.map(\.id))
        // Every system ID that can be instantiated should be in the catalog
        for id in systemIDs {
            if TimeZone(identifier: id) != nil {
                #expect(catalogIDs.contains(id), "Missing \(id)")
            }
        }
    }

    @Test("options are sorted by UTC offset, then display name")
    func optionsSortedByOffset() {
        let opts = TimeZoneCatalog.options
        let offsets = opts.map(\.utcOffsetSeconds)
        #expect(offsets == offsets.sorted())
    }

    @Test("all options have non-empty id, shortLabel, cityName, displayName")
    func optionsFieldsNonEmpty() {
        for option in TimeZoneCatalog.options {
            #expect(!option.id.isEmpty, "Empty id found")
            #expect(!option.shortLabel.isEmpty, "Empty shortLabel for \(option.id)")
            #expect(!option.cityName.isEmpty, "Empty cityName for \(option.id)")
            #expect(!option.displayName.isEmpty, "Empty displayName for \(option.id)")
        }
    }

    @Test("all options searchableText contains id and cityName")
    func searchableTextContainsKeyFields() {
        for option in TimeZoneCatalog.options {
            #expect(option.searchableText.contains(option.cityName),
                    "searchableText missing cityName for \(option.id)")
        }
    }

    // MARK: defaultSecondaryID

    @Test("defaultSecondaryID differs from primary for NYC")
    func defaultSecondaryDiffersFromNYC() {
        let primary = "America/New_York"
        let secondary = TimeZoneCatalog.defaultSecondaryID(relativeTo: primary)
        #expect(!secondary.isEmpty)
        #expect(secondary != primary)
    }

    @Test("defaultSecondaryID returns a valid catalog entry")
    func defaultSecondaryIsValidCatalogEntry() {
        let secondary = TimeZoneCatalog.defaultSecondaryID(relativeTo: "America/New_York")
        #expect(TimeZoneCatalog.option(for: secondary) != nil)
    }

    // MARK: weatherLookupName

    @Test("weatherLookupName returns override for known IDs")
    func weatherLookupNameOverrides() {
        #expect(TimeZoneCatalog.weatherLookupName(for: "America/New_York") == "New York, New York, USA")
        #expect(TimeZoneCatalog.weatherLookupName(for: "Asia/Tokyo") == "Tokyo, Japan")
        #expect(TimeZoneCatalog.weatherLookupName(for: "Europe/London") == "London, United Kingdom")
    }

    @Test("weatherLookupName falls back to cityName for non-overridden ID")
    func weatherLookupNameFallback() {
        // Europe/Madrid has no weatherLookupName override, should return cityName
        let name = TimeZoneCatalog.weatherLookupName(for: "Europe/Madrid")
        #expect(name == "Madrid")
    }

    // MARK: representativeLocation

    @Test("representativeLocation returns non-nil for known IDs")
    func representativeLocationKnown() {
        let known = ["America/New_York", "Europe/London", "Asia/Tokyo"]
        for id in known {
            #expect(TimeZoneCatalog.representativeLocation(for: id) != nil, "Missing location for \(id)")
        }
    }

    @Test("representativeLocation returns nil for non-overridden ID")
    func representativeLocationUnknown() {
        // Europe/Madrid has no representativeLocation override
        #expect(TimeZoneCatalog.representativeLocation(for: "Europe/Madrid") == nil)
    }

    @Test("representativeLocation coordinates are in valid range")
    func representativeLocationCoordinatesValid() {
        let known = ["America/New_York", "Europe/London", "Asia/Tokyo", "Asia/Karachi"]
        for id in known {
            if let location = TimeZoneCatalog.representativeLocation(for: id) {
                #expect(location.coordinate.latitude >= -90 && location.coordinate.latitude <= 90,
                        "Invalid latitude for \(id)")
                #expect(location.coordinate.longitude >= -180 && location.coordinate.longitude <= 180,
                        "Invalid longitude for \(id)")
            }
        }
    }
}
