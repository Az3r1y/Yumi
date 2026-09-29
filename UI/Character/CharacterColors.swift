import SwiftUI

/// Color tokens for the Yumi character (per the official DA sheet):
/// bright blue body, pink/purple rim light, huge white eyes with navy pupils.
/// The single source of truth — no view or renderer may hard-code a color.
enum CharacterColors {
    /// Body base — vivid blue (DA "Principal").
    static let bodyTop = Color(red: 0.45, green: 0.63, blue: 1.00)
    static let bodyBottom = Color(red: 0.20, green: 0.34, blue: 0.93)

    /// Rim lights (DA "Secondaire" + "Accent") — drawn behind the body,
    /// offset, so they halo the edges: pink lower-left, purple upper-right.
    static let rimPink = Color(red: 0.97, green: 0.48, blue: 0.72)
    static let rimPurple = Color(red: 0.55, green: 0.44, blue: 0.98)

    /// Accent used sparingly (state dot, highlights).
    static let accent = Color(red: 0.99, green: 0.80, blue: 0.35)

    /// Ink for pupils, brows, mouth (DA "Yeux" — deep navy, not black).
    static let ink = Color(red: 0.09, green: 0.12, blue: 0.32)
}
