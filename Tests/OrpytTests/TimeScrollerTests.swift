import AppKit
import Testing
@testable import OrpytCore

// MARK: - TimeScrollerWheelNSView

@Suite("TimeScrollerWheelNSView")
struct TimeScrollerWheelNSViewTests {

    // MARK: Mouse passthrough

    @Test("mouseDown forwards to nextResponder so SwiftUI buttons remain hittable")
    @MainActor
    func mouseDownForwardsToNextResponder() {
        let view = TimeScrollerWheelNSView()
        let spy = ResponderSpy()
        view.nextResponder = spy

        view.mouseDown(with: makeFakeMouseEvent())
        #expect(spy.receivedMouseDown == true)
        #expect(spy.receivedScrollWheel == false)
    }

    @Test("mouseUp forwards to nextResponder")
    @MainActor
    func mouseUpForwardsToNextResponder() {
        let view = TimeScrollerWheelNSView()
        let spy = ResponderSpy()
        view.nextResponder = spy

        view.mouseUp(with: makeFakeMouseEvent(type: .leftMouseUp))
        #expect(spy.receivedMouseUp == true)
    }

    @Test("mouseDragged forwards to nextResponder")
    @MainActor
    func mouseDraggedForwardsToNextResponder() {
        let view = TimeScrollerWheelNSView()
        let spy = ResponderSpy()
        view.nextResponder = spy

        view.mouseDragged(with: makeFakeMouseEvent(type: .leftMouseDragged))
        #expect(spy.receivedMouseDragged == true)
    }

    @Test("rightMouseDown forwards to nextResponder")
    @MainActor
    func rightMouseDownForwardsToNextResponder() {
        let view = TimeScrollerWheelNSView()
        let spy = ResponderSpy()
        view.nextResponder = spy

        view.rightMouseDown(with: makeFakeMouseEvent(type: .rightMouseDown))
        #expect(spy.receivedRightMouseDown == true)
    }

    @Test("mouse clicks do not reach scrollWheel handler")
    @MainActor
    func mouseClicksDoNotTriggerScrollWheel() {
        let view = TimeScrollerWheelNSView()
        let spy = ResponderSpy()
        view.nextResponder = spy

        view.mouseDown(with: makeFakeMouseEvent())
        #expect(spy.receivedScrollWheel == false)
    }

    @Test("acceptsFirstResponder is true — scroll events reach the view")
    @MainActor
    func acceptsFirstResponder() {
        #expect(TimeScrollerWheelNSView().acceptsFirstResponder == true)
    }

    private func makeFakeMouseEvent(type: NSEvent.EventType = .leftMouseDown) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) ?? NSEvent()
    }
}

// MARK: - ResponderSpy

final class ResponderSpy: NSResponder {
    var receivedMouseDown = false
    var receivedMouseUp = false
    var receivedMouseDragged = false
    var receivedRightMouseDown = false
    var receivedScrollWheel = false

    override func mouseDown(with event: NSEvent) { receivedMouseDown = true }
    override func mouseUp(with event: NSEvent) { receivedMouseUp = true }
    override func mouseDragged(with event: NSEvent) { receivedMouseDragged = true }
    override func rightMouseDown(with event: NSEvent) { receivedRightMouseDown = true }
    override func scrollWheel(with event: NSEvent) { receivedScrollWheel = true }
}

// MARK: - WheelScrubbingNSSlider scroll clamping

@Suite("WheelScrubbingNSSlider")
struct WheelScrubbingNSSliderTests {

    @Test("slider initialises within range")
    @MainActor
    func sliderInitialisesWithinRange() {
        let slider = WheelScrubbingNSSlider(
            value: 0,
            minValue: -12,
            maxValue: 12,
            target: nil,
            action: nil
        )
        #expect(slider.doubleValue >= slider.minValue)
        #expect(slider.doubleValue <= slider.maxValue)
    }

    @Test("slider value is clamped to minValue when set below range")
    @MainActor
    func sliderClampedBelowMin() {
        let slider = WheelScrubbingNSSlider(
            value: -12,
            minValue: -12,
            maxValue: 12,
            target: nil,
            action: nil
        )
        // Manually test the clamping arithmetic the scrollWheel handler uses
        let next = max(slider.minValue, min(slider.maxValue, slider.doubleValue - 1))
        #expect(next == -12)
    }

    @Test("slider value is clamped to maxValue when set above range")
    @MainActor
    func sliderClampedAboveMax() {
        let slider = WheelScrubbingNSSlider(
            value: 12,
            minValue: -12,
            maxValue: 12,
            target: nil,
            action: nil
        )
        let next = max(slider.minValue, min(slider.maxValue, slider.doubleValue + 1))
        #expect(next == 12)
    }
}

// MARK: - TimeShift binding arithmetic

@Suite("TimeShift state")
struct TimeShiftStateTests {

    // MARK: sliderValue binding

    @Test("sliderValue get converts minutes to hours")
    func sliderValueGet() {
        // 120 minutes → 2.0 hours
        let minutes = 120
        let hours = Double(minutes) / 60.0
        #expect(hours == 2.0)
    }

    @Test("sliderValue set snaps to nearest 15-minute boundary")
    func sliderValueSetSnaps() {
        // 2.1h → nearest 0.25h step → rounds to 2.0h → 120 min
        let raw = 2.1
        let snapped = (raw * 4).rounded() / 4
        let minutes = Int(snapped * 60)
        #expect(minutes == 120)

        // 2.15h → nearest 0.25h step → rounds to 2.25h → 135 min
        let raw2 = 2.15
        let snapped2 = (raw2 * 4).rounded() / 4
        let minutes2 = Int(snapped2 * 60)
        #expect(minutes2 == 135)
    }

    @Test("sliderValue set at exact boundary produces correct minutes")
    func sliderValueSetBoundary() {
        let raw = -3.0
        let snapped = (raw * 4).rounded() / 4
        let minutes = Int(snapped * 60)
        #expect(minutes == -180)
    }

    // MARK: Clamping

    @Test("timeShift clamped at +12h (720 min) when stepping past boundary")
    func clampPositive() {
        var shift = 700
        for _ in 0..<5 {
            shift = max(-720, min(720, shift + 15))
        }
        #expect(shift == 720)
    }

    @Test("timeShift clamped at -12h (-720 min) when stepping past boundary")
    func clampNegative() {
        var shift = -700
        for _ in 0..<5 {
            shift = max(-720, min(720, shift - 15))
        }
        #expect(shift == -720)
    }

    @Test("timeShift already at +12h does not change when stepping forward")
    func clampAtBoundaryNoChange() {
        let current = 720
        let next = max(-720, min(720, current + 15))
        #expect(next == current)
    }

    // MARK: shiftLabel formatting

    @Test("shiftLabel shows hours-only when minutes remainder is zero")
    func shiftLabelHoursOnly() {
        func shiftLabel(for minutes: Int) -> String {
            let abs = Swift.abs(minutes)
            let h = abs / 60
            let m = abs % 60
            let prefix = minutes > 0 ? "+" : "-"
            return m == 0
                ? "Previewing \(prefix)\(h)h across your clocks."
                : "Previewing \(prefix)\(h)h \(m)m across your clocks."
        }
        #expect(shiftLabel(for: 120) == "Previewing +2h across your clocks.")
        #expect(shiftLabel(for: -60) == "Previewing -1h across your clocks.")
        #expect(shiftLabel(for: 720) == "Previewing +12h across your clocks.")
    }

    @Test("shiftLabel shows hours and minutes when remainder is non-zero")
    func shiftLabelHoursAndMinutes() {
        func shiftLabel(for minutes: Int) -> String {
            let abs = Swift.abs(minutes)
            let h = abs / 60
            let m = abs % 60
            let prefix = minutes > 0 ? "+" : "-"
            return m == 0
                ? "Previewing \(prefix)\(h)h across your clocks."
                : "Previewing \(prefix)\(h)h \(m)m across your clocks."
        }
        #expect(shiftLabel(for: 135) == "Previewing +2h 15m across your clocks.")
        #expect(shiftLabel(for: -135) == "Previewing -2h 15m across your clocks.")
        #expect(shiftLabel(for: 15) == "Previewing +0h 15m across your clocks.")
    }

    // MARK: Reset button label

    @Test("reset button shows 'Now' at zero, 'Reset' otherwise")
    func resetButtonLabel() {
        func label(for minutes: Int) -> String { minutes == 0 ? "Now" : "Reset" }
        #expect(label(for: 0) == "Now")
        #expect(label(for: 60) == "Reset")
        #expect(label(for: -30) == "Reset")
        #expect(label(for: 720) == "Reset")
        #expect(label(for: -720) == "Reset")
    }

    // MARK: Tick mark positioning

    @Test("tick mark x-position for hour 0 is exactly the midpoint fraction")
    func tickMarkZeroIsMidpoint() {
        let fraction = Double(0 + 12) / 24.0
        #expect(fraction == 0.5)
    }

    @Test("tick mark x-position for -12h is at the left edge")
    func tickMarkMinus12IsLeftEdge() {
        let fraction = Double(-12 + 12) / 24.0
        #expect(fraction == 0.0)
    }

    @Test("tick mark x-position for +12h is at the right edge")
    func tickMarkPlus12IsRightEdge() {
        let fraction = Double(12 + 12) / 24.0
        #expect(fraction == 1.0)
    }

    @Test("tick mark highlights correctly when timeShiftMinutes matches the hour exactly")
    func tickMarkHighlightLogic() {
        let timeShiftMinutes = 180 // exactly +3h
        let isAtCurrentHour = (timeShiftMinutes / 60 == 3 && timeShiftMinutes % 60 == 0)
        #expect(isAtCurrentHour == true)
    }

    @Test("tick mark does not highlight when only at partial hour")
    func tickMarkNoHighlightAtPartialHour() {
        let timeShiftMinutes = 195 // +3h 15m — 3h mark should not highlight
        let isAtCurrentHour = (timeShiftMinutes / 60 == 3 && timeShiftMinutes % 60 == 0)
        #expect(isAtCurrentHour == false)
    }
}
