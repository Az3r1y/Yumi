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
        #expect(!plan.hookServer && !plan.modules && !plan.memory && !plan.initiative && !plan.chat && !plan.keychain && !plan.integrationPollers)
    }

    @Test func anOrdinaryRunStartsEverything() {
        let plan = LaunchPlan(studio: false)
        #expect(plan.hookServer && plan.modules && plan.memory && plan.initiative && plan.chat && plan.keychain && plan.integrationPollers)
        #expect(!plan.startsNothing)
    }

    @Test func theTestsThemselvesAreNotFilming() {
        #expect(LaunchPlan.current == LaunchPlan(studio: StudioMode.isOn))
    }
}
