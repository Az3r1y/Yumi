import Testing
import Foundation

@Suite struct StudioModeTests {
    @Test func theVariableTurnsItOn() {
        #expect(StudioMode.isOn(in: ["YUMI_STUDIO": "1"]))
        #expect(StudioMode.isOn(in: ["YUMI_STUDIO": "true"]))
        for off in [[:], ["YUMI_STUDIO": ""], ["YUMI_STUDIO": "0"], ["YUMI_STUDIO": "false"], ["YUMI_STUDIO": " No "], ["OTHER": "1"]] {
            #expect(!StudioMode.isOn(in: off), "\(off)")
        }
        #expect(StudioMode.variable == "YUMI_STUDIO")
    }

    @Test func whileFilmingNothingStarts() {
        let plan = LaunchPlan(studio: true)
        #expect(plan.startsNothing)
        #expect(!plan.hookServer && !plan.modules && !plan.memory && !plan.initiative && !plan.chat && !plan.keychain && !plan.context)
    }

    @Test func anOrdinaryRunStartsEverything() {
        let plan = LaunchPlan(studio: false)
        #expect(plan.hookServer && plan.modules && plan.memory && plan.initiative && plan.chat && plan.keychain && plan.context)
        #expect(!plan.startsNothing)
    }

    @Test func theTestsThemselvesAreNotFilming() {
        #expect(LaunchPlan.current == LaunchPlan(studio: StudioMode.isOn))
    }
}

// Cues played on demand while filming: a fake approval, the break remark, a GitHub scene.
@Suite struct StudioCueTests {
    @Test func eachCueHasItsOwnKey() {
        #expect(StudioCue.forKey(0) == .approval)
        #expect(StudioCue.forKey(35) == .breakRemark)
        #expect(StudioCue.forKey(5) == .githubScene)
        #expect(StudioCue.forKey(49) == nil)
        #expect(Set(StudioCue.allCases.map(\.keyCode)).count == StudioCue.allCases.count)
        // The shots' keys (1 to 0, -, =, ], o, [), Space, Escape and R stay theirs
        let taken: Set<UInt16> = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 33, 30, 42, 49, 53, 15]
        #expect(StudioCue.allCases.allSatisfy { !taken.contains($0.keyCode) })
    }

    @Test func theFakeApprovalAsksForAForcePush() {
        #expect(StudioFakes.approvalTool == "Bash")
        #expect(StudioFakes.approvalCommand == "git push --force main")
        #expect(StudioFakes.isFake(requestID: StudioFakes.approvalID))
        #expect(!StudioFakes.isFake(requestID: "r1"))
        #expect(!StudioFakes.isFake(requestID: nil))
    }

    @Test func answeringTheFakeApprovalOnlyMovesYumi() {
        #expect(StudioFakes.celebrates(after: "allow"))
        #expect(StudioFakes.celebrates(after: "always"))
        #expect(!StudioFakes.celebrates(after: "deny"))
    }

    @Test func theBreakRemarkIsTheInitiativesOwn() {
        let remark = StudioFakes.breakRemark(name: "Alex")
        let expected = InitiativePhrases.variants(for: .longStretch(hours: 2), Surroundings(now: .now, name: "Alex")).first
        #expect(remark.text == expected?.text)
        #expect(!remark.text.isEmpty)
        #expect(remark.id.hasPrefix("studio"))
        #expect(remark.action != nil)
    }

    @Test func githubScenesTakeTurns() {
        #expect(StudioFakes.scene(after: nil) == .star)
        #expect(StudioFakes.scene(after: .star) == .merge)
        #expect(StudioFakes.scene(after: StudioFakes.scenes.last) == .star)
        #expect(StudioFakes.scene(after: .commit) == .star)
    }
}
