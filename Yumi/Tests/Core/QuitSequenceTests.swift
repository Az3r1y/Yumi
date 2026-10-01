import Testing
import Foundation

@Suite struct QuitSequenceTests {
    @Test func quittingSaysGoodbyeFirstThenEnds() {
        var quit = QuitSequence()
        let first = quit.request(systemReason: nil)
        #expect(first == .sayGoodbye)
        #expect(quit.isSayingGoodbye)
        // The island is done: the app is ended once, and the request that follows goes through.
        let ended = quit.finish()
        let second = quit.request(systemReason: nil)
        #expect(ended)
        #expect(second == .endNow)
    }

    @Test func theSafetyTimerAndTheIslandCannotEndTheAppTwice() {
        var quit = QuitSequence()
        _ = quit.request(systemReason: nil)
        let once = quit.finish()
        let twice = quit.finish()
        #expect(once && !twice)
    }

    @Test func nothingToFinishWhenNobodyQuit() {
        var quit = QuitSequence()
        let ended = quit.finish()
        #expect(!ended)
        #expect(!quit.isSayingGoodbye)
    }

    @Test func aSessionEndingIsNeverDelayed() {
        // 'logo', 'rest', 'shut', 'rlgo': the reasons macOS sends with log out, restart and shut down.
        for reason: UInt32 in [0x6C6F676F, 0x72657374, 0x73687574, 0x726C676F] {
            var quit = QuitSequence()
            let answer = quit.request(systemReason: reason)
            let ended = quit.finish()
            #expect(answer == .endNow)
            #expect(!ended)
        }
        var quit = QuitSequence()
        let answer = quit.request(systemReason: 0)
        #expect(answer == .sayGoodbye)
    }

    @Test func quittingAgainDuringTheGoodbyeEndsAtOnce() {
        var quit = QuitSequence()
        _ = quit.request(systemReason: nil)
        let again = quit.request(systemReason: nil)
        let ended = quit.finish()
        #expect(again == .endNow)
        #expect(!ended)
    }

    @Test func aShutdownDuringTheGoodbyeEndsAtOnce() {
        var quit = QuitSequence()
        _ = quit.request(systemReason: nil)
        let answer = quit.request(systemReason: 0x73687574)
        #expect(answer == .endNow)
    }

    @Test func theGoodbyeIsHeldSixSecondsAtMost() {
        #expect(QuitSequence.patience == 6)
    }
}
