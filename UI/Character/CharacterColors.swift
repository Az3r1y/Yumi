import SwiftUI

/// Color tokens for the Yumi character. The single source of truth for the
/// palette — no view or renderer may hard-code a color. Kept deliberately
/// small: one body hue, one accent, ink, no neon, no permanent glow.
enum CharacterColors {
    /// Body base — soft mint-teal (the "slime" identity).
    static let bodyTop = Color(red: 0.45, green: 0.82, blue: 0.74)
    static let bodyBottom = Color(red: 0.27, green: 0.62, blue: 0.55)

    /// Accent used sparingly (state dot, highlights).
    static let accent = Color(red: 0.98, green: 0.83, blue: 0.40)

    /// Ink for eyes, brows, mouth.
    static let ink = Color(red: 0.07, green: 0.13, blue: 0.13)
}
