import Foundation

// MARK: - Character contract
// The island tells the character what to do through these notifications; the character
// renderer listens to them. Both sides rely on this file, so neither edits it during
// the parallel work (see YUMI.md). The reference for what each value looks like is
// design/yumi/maquette/reference.html.

/// One-shot body movements. They play once and the character returns to rest.
enum YumiPose: String, CaseIterable, Sendable {
    case jump, stretch, squash, shake, celebrate
    /// Small reactions: a view change, a click on the character.
    case pop, boing
    /// Used by the launch sequence.
    case arrive, dip, wave
}

/// Lasting human habits, each with its prop and routine. Only one at a time.
enum YumiHabit: String, CaseIterable, Sendable {
    case smoke, exhausted, coffee, headphones, sunglasses, cloud, whistle, sleep
}

/// Face expressions.
enum YumiMood: String, CaseIterable, Sendable {
    case neutral, happy, curious, focused, thinking, surprised, worried, annoyed, wink, asleep
}

/// Colour of the rim light. It carries the state; the body stays black.
enum YumiRimTone: String, CaseIterable, Sendable {
    case calm, work, think, warn, error, done, joy
}

extension Notification.Name {
    /// object: `YumiPose`
    static let yumiPose  = AppIdentity.notification("yumiPose")
    /// object: `YumiHabit`, or nil to clear the habit
    static let yumiHabit = AppIdentity.notification("yumiHabit")
    /// object: `YumiMood`, or nil to follow the island state again
    static let yumiMood  = AppIdentity.notification("yumiMood")
    /// object: `YumiRimTone`, or nil to follow the island state again
    static let yumiRim   = AppIdentity.notification("yumiRim")
    /// object: `Bool`. false = unlit: only the eyes show (used by the launch sequence)
    static let yumiLit   = AppIdentity.notification("yumiLit")
    /// object: `CGPoint` in -1...1 on both axes, or nil to follow the pointer again
    static let yumiGaze  = AppIdentity.notification("yumiGaze")
}
