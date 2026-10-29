import Testing
import CoreGraphics

@Suite struct IslandLayoutTests {

    /// The open island of the work tab, Yumi seated in the card of an agent that finished.
    private func seated() -> IslandLayout {
        var layout = IslandLayout(notchWidth: 185, notchHeight: 38, hasNotch: true)
        layout.openWidth = 748
        layout.openSlot = CGRect(x: 30, y: 60, width: 70, height: 59)
        layout.compactEar = 120
        layout.speakWidth = 300
        layout.speakBand = 40
        return layout
    }

    @Test func aScreenChangeKeepsYumisSeat() {
        let before = seated()
        var after = before
        after.fit(notchWidth: 185, notchHeight: 38, hasNotch: true)
        // Nothing the screen decides changed: the layout is the same, Yumi stays in his card
        #expect(after == before)
        #expect(after.seat(.open) == before.seat(.open))
    }

    @Test func anotherScreenTakesItsNotchAndKeepsWhatTheViewsMeasured() {
        let before = seated()
        var after = before
        after.fit(notchWidth: 200, notchHeight: 32, hasNotch: false)
        #expect(after.notchWidth == 200)
        #expect(after.notchHeight == 32)
        #expect(after.hasNotch == false)
        #expect(after.openSlot == before.openSlot)
        #expect(after.openWidth == before.openWidth)
        #expect(after.compactEar == before.compactEar)
        #expect(after.speakWidth == before.speakWidth)
        #expect(after.speakBand == before.speakBand)
    }

    @Test func theOpenSeatIsTheSlotNotTheDefault() {
        let layout = seated()
        let seat = layout.seat(.open)
        let slot = layout.openSlot!
        #expect(seat.x == slot.midX - layout.openWidth / 2)
        #expect(seat.y == slot.midY)
        #expect(seat.scale == slot.width / 100)
    }
}
