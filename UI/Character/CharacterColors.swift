import SwiftUI

/// Neutral color tokens for the current PLACEHOLDER renderer.
///
/// Deliberately flat and boring: the real palette will come with the final
/// art direction, as new tokens consumed by the future renderer — these three
/// may change or disappear then. No view or renderer may hard-code a color.
enum CharacterColors {
    /// Body base.
    static let body = Color(red: 0.35, green: 0.65, blue: 0.85)
    /// Ink for eyes, brows, mouth.
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.18)
    /// Accent reserved for future state indicators.
    static let accent = Color(red: 0.95, green: 0.75, blue: 0.35)
}
