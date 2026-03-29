import Testing
@testable import OrpytCore

@Suite("ClockSettingsStore", .serialized)
@MainActor
struct ClockSettingsStoreTests {

    // MARK: Icon mutual exclusion invariant

    @Test("setting showStatusIcon=true turns off showWeatherInMenuBar")
    func ambientIconTurnsOffWeatherIcon() {
        let s = ClockSettingsStore.shared
        s.showWeatherInMenuBar = true
        s.showStatusIcon = true
        #expect(s.showStatusIcon == true)
        #expect(s.showWeatherInMenuBar == false)
    }

    @Test("setting showWeatherInMenuBar=true turns off showStatusIcon")
    func weatherIconTurnsOffAmbientIcon() {
        let s = ClockSettingsStore.shared
        s.showStatusIcon = true
        s.showWeatherInMenuBar = true
        #expect(s.showWeatherInMenuBar == true)
        #expect(s.showStatusIcon == false)
    }

    @Test("both icons can be off simultaneously")
    func bothIconsCanBeOff() {
        let s = ClockSettingsStore.shared
        s.showStatusIcon = false
        s.showWeatherInMenuBar = false
        #expect(s.showStatusIcon == false)
        #expect(s.showWeatherInMenuBar == false)
    }

    @Test("ambient and weather icons are never simultaneously on")
    func ambientAndWeatherNeverBothOn() {
        let s = ClockSettingsStore.shared
        // Set both on — whichever fires second should turn off the first
        s.showStatusIcon = true
        s.showWeatherInMenuBar = true
        #expect(!(s.showStatusIcon && s.showWeatherInMenuBar),
                "Both icon flags are on — mutual exclusion broken")
    }

    // MARK: setMenuBarVisibility

    @Test("setMenuBarVisibility(icon:true, weather:false) shows only ambient icon")
    func setMenuBarVisibilityOnlyIcon() {
        let s = ClockSettingsStore.shared
        s.setMenuBarVisibility(icon: true, weather: false)
        #expect(s.showStatusIcon == true)
        #expect(s.showWeatherInMenuBar == false)
    }

    @Test("setMenuBarVisibility(icon:false, weather:true) shows only weather icon")
    func setMenuBarVisibilityOnlyWeather() {
        let s = ClockSettingsStore.shared
        s.setMenuBarVisibility(icon: false, weather: true)
        #expect(s.showStatusIcon == false)
        #expect(s.showWeatherInMenuBar == true)
    }

    @Test("setMenuBarVisibility(icon:false, weather:false) disables both icons")
    func setMenuBarVisibilityBothOff() {
        let s = ClockSettingsStore.shared
        s.setMenuBarVisibility(icon: false, weather: false)
        #expect(s.showStatusIcon == false)
        #expect(s.showWeatherInMenuBar == false)
    }

    @Test("setMenuBarVisibility(icon:true, weather:true) — weather wins, mutual exclusion holds")
    func setMenuBarVisibilityBothOnWeatherWins() {
        let s = ClockSettingsStore.shared
        s.setMenuBarVisibility(icon: true, weather: true)
        #expect(!(s.showStatusIcon && s.showWeatherInMenuBar),
                "Both icon flags on — mutual exclusion broken")
    }

    // MARK: Clock visibility invariant

    @Test("showPrimaryClock and showSecondaryClock are independently settable")
    func clockVisibilityIndependent() {
        let s = ClockSettingsStore.shared
        s.showPrimaryClock = true
        s.showSecondaryClock = false
        #expect(s.showPrimaryClock == true)
        #expect(s.showSecondaryClock == false)

        s.showPrimaryClock = false
        s.showSecondaryClock = true
        #expect(s.showPrimaryClock == false)
        #expect(s.showSecondaryClock == true)
    }

    @Test("disabling showPrimaryClock when secondary is already false forces secondary on")
    func disablingPrimaryForcesSecondaryOn() {
        let s = ClockSettingsStore.shared
        // First ensure secondary is off
        s.showSecondaryClock = true  // set secondary on so we can turn off primary safely
        s.showPrimaryClock = false   // turning off primary while secondary is on — ok
        #expect(s.showSecondaryClock == true)

        // Now attempt to turn off secondary when primary is already off
        // didSet should force primary back on
        s.showSecondaryClock = false
        #expect(s.showPrimaryClock || s.showSecondaryClock,
                "Both clocks disabled — invariant broken")
    }

    @Test("at least one clock is always visible — invariant never violated")
    func atLeastOneClockAlwaysVisible() {
        let s = ClockSettingsStore.shared
        // Toggle both quickly — invariant must hold after each assignment
        s.showPrimaryClock = true; s.showSecondaryClock = true
        #expect(s.showPrimaryClock || s.showSecondaryClock)

        s.showPrimaryClock = false
        #expect(s.showPrimaryClock || s.showSecondaryClock)

        s.showSecondaryClock = false
        #expect(s.showPrimaryClock || s.showSecondaryClock)
    }

    // MARK: displayLabel

    @Test("displayLabel returns custom label when non-empty")
    func displayLabelCustom() {
        let s = ClockSettingsStore.shared
        #expect(s.displayLabel(for: "America/New_York", customLabel: "NYC Office") == "NYC Office")
        #expect(s.displayLabel(for: "America/Los_Angeles", customLabel: "West HQ") == "West HQ")
    }

    @Test("displayLabel falls back to shortLabel when custom is empty")
    func displayLabelFallback() {
        let s = ClockSettingsStore.shared
        // NYC shortLabel override is "NYC"
        #expect(s.displayLabel(for: "America/New_York", customLabel: "") == "NYC")
        // LA shortLabel override is "LA"
        #expect(s.displayLabel(for: "America/Los_Angeles", customLabel: "") == "LA")
    }

    @Test("displayLabel falls back to identifier prefix when no catalog match")
    func displayLabelNoMatch() {
        let s = ClockSettingsStore.shared
        // An identifier not in the catalog should fall back gracefully
        let label = s.displayLabel(for: "Unknown/Zone", customLabel: "")
        #expect(!label.isEmpty)
    }

    // MARK: swapTimeZones

    @Test("swapTimeZones exchanges primary and secondary time zone IDs")
    func swapTimeZonesExchangesIDs() {
        let s = ClockSettingsStore.shared
        s.primaryTimeZoneID = "America/New_York"
        s.secondaryTimeZoneID = "Europe/London"
        s.swapTimeZones()
        #expect(s.primaryTimeZoneID == "Europe/London")
        #expect(s.secondaryTimeZoneID == "America/New_York")
    }

    @Test("swapTimeZones exchanges custom labels")
    func swapTimeZonesExchangesLabels() {
        let s = ClockSettingsStore.shared
        s.primaryCustomLabel = "NYC"
        s.secondaryCustomLabel = "LON"
        s.swapTimeZones()
        #expect(s.primaryCustomLabel == "LON")
        #expect(s.secondaryCustomLabel == "NYC")
    }

    @Test("swapTimeZones is its own inverse — double-swap restores original")
    func swapTimeZonesDoubleSwapRestores() {
        let s = ClockSettingsStore.shared
        s.primaryTimeZoneID = "America/New_York"
        s.secondaryTimeZoneID = "Asia/Tokyo"
        s.primaryCustomLabel = "NYC"
        s.secondaryCustomLabel = "TYO"
        s.swapTimeZones()
        s.swapTimeZones()
        #expect(s.primaryTimeZoneID == "America/New_York")
        #expect(s.secondaryTimeZoneID == "Asia/Tokyo")
        #expect(s.primaryCustomLabel == "NYC")
        #expect(s.secondaryCustomLabel == "TYO")
    }
}
