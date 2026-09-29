import Foundation
import CoreGraphics

/// Gives the character freedom of position: it rests at spots inside a
/// container and, from time to time, hops to another one on its own.
/// Time-based and deterministic once a move is scheduled — the view reads
/// `frame(at:)` every display tick, no timers of its own.
@MainActor
final class CharacterWander {
    private let spots: [CGPoint]
    private let moveDuration: TimeInterval
    private let restRange: ClosedRange<TimeInterval>
    private let hopHeight: CGFloat

    private var currentIndex: Int
    private var restingAt: CGPoint
    private var move: (from: CGPoint, start: TimeInterval)?
    private var nextMoveAt: TimeInterval

    init(spots: [CGPoint],
         initialIndex: Int = 0,
         now: TimeInterval,
         restRange: ClosedRange<TimeInterval> = 5...12,
         moveDuration: TimeInterval = 0.55,
         hopHeight: CGFloat = 10) {
        precondition(!spots.isEmpty)
        self.spots = spots
        self.currentIndex = max(0, min(initialIndex, spots.count - 1))
        self.restingAt = spots[self.currentIndex]
        self.restRange = restRange
        self.moveDuration = moveDuration
        self.hopHeight = hopHeight
        self.nextMoveAt = now + TimeInterval.random(in: restRange)
    }

    /// The current visual frame: interpolated position while moving,
    /// rest position otherwise, plus the hop arc offset.
    func frame(at now: TimeInterval) -> WanderFrame {
        if let move {
            let t = (now - move.start) / moveDuration
            if t >= 1 {
                restingAt = spots[currentIndex]
                self.move = nil
                nextMoveAt = now + TimeInterval.random(in: restRange)
                return WanderFrame(position: restingAt, hopY: 0, isMoving: false)
            }
            let p = CharacterEasing.inOut.apply(CGFloat(max(0, t)))
            let target = spots[currentIndex]
            let x = move.from.x + (target.x - move.from.x) * p
            let y = move.from.y + (target.y - move.from.y) * p
            let hop = -sin(CGFloat(t) * .pi) * hopHeight
            return WanderFrame(position: CGPoint(x: x, y: y), hopY: hop, isMoving: true)
        }

        if now >= nextMoveAt && spots.count > 1 {
            startMove(at: now)
        }
        return WanderFrame(position: restingAt, hopY: 0, isMoving: false)
    }

    /// Immediately hops to the given spot (tests, scripted behaviors).
    func moveTo(_ index: Int, at now: TimeInterval) {
        guard spots.indices.contains(index), move == nil, spots[index] != restingAt else { return }
        currentIndex = index
        move = (from: restingAt, start: now)
    }

    private func startMove(at now: TimeInterval) {
        var candidate = Int.random(in: spots.indices)
        if spots.count > 1 {
            while spots[candidate] == restingAt {
                candidate = Int.random(in: spots.indices)
            }
        }
        currentIndex = candidate
        move = (from: restingAt, start: now)
    }
}

/// One tick of the wander: where the character is and whether it is hopping.
struct WanderFrame: Equatable {
    var position: CGPoint
    var hopY: CGFloat
    var isMoving: Bool
}
