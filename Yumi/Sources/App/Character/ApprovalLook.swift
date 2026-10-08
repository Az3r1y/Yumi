import Foundation

/// How Yumi looks while a permission waits: surprised for a moment when it arrives, then
/// the warning rim (orange) for as long as it waits, over whatever the island asked for.
enum ApprovalLook {
    /// Seconds of the surprised face when a permission is asked.
    static let startle = 1.0

    /// The rim to draw: `warn` while a permission waits, `otherwise` the rest of the time.
    static func rim<Tone>(waiting: Bool, warn: Tone, otherwise: @autoclosure () -> Tone) -> Tone {
        waiting ? warn : otherwise()
    }
}
