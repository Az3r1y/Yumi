import AppKit
import SwiftUI

// The folded island shows what is live right now: on the right of the notch, the colour and
// the `live` text of the module with the highest priority (Contracts/ModuleTypes.swift), and,
// while the pointer is on the island, its buttons. Yumi stays in the left ear. With nothing
// live, the right ear is empty.

/// What the folded island needs to draw and to size itself, worked out once per update.
struct FoldedContent: Equatable {
    var module: ModuleSnapshot?
    var hover = false

    var live: ModuleLive? { module?.live }

    /// "Two at most."
    var controls: [ModuleControl] { hover ? Array((live?.controls ?? []).prefix(2)) : [] }

    private var controlsWidth: CGFloat {
        let count = CGFloat(controls.count)
        return count == 0 ? 0 : IslandConst.foldedGap + count * IslandConst.foldedControl + (count - 1) * IslandConst.foldedControlGap
    }

    /// Room the text is given: its own width, up to `foldedTextMax`.
    var textWidth: CGFloat {
        guard let live else { return 0 }
        return min(Self.width(of: live.text), IslandConst.foldedTextMax)
    }

    /// Width the right ear would like: paddings, dot, text, buttons.
    var wantedEar: CGFloat {
        guard live != nil else { return IslandConst.compactExtra / 2 }
        return IslandConst.foldedLeading + IslandConst.foldedDot + IslandConst.foldedGap + textWidth
            + controlsWidth + IslandConst.foldedTrailing
    }

    /// The ear the island takes: never narrower than the mock-up's, and the folded island
    /// never wider than the open one.
    func ear(notchWidth: CGFloat) -> CGFloat {
        CGFloat(FoldedIsland.ear(content: Double(wantedEar),
                                 minimum: Double(IslandConst.compactExtra / 2),
                                 notchWidth: Double(notchWidth),
                                 openWidth: Double(IslandConst.expandedWidth * IslandConst.openScale)))
    }

    /// Yumi puts his headphones on while music plays (`activity`), not for a paused track.
    var musicPlaying: Bool {
        guard let module, let live else { return false }
        return IslandModel.isMusic(module.id) && live.priority >= ModuleLivePriority.activity
    }

    /// Room left for the text once the ear has its final width: a text too long is cut.
    func textSlot(ear: CGFloat) -> CGFloat {
        let around = IslandConst.foldedLeading + IslandConst.foldedDot + IslandConst.foldedGap
            + controlsWidth + IslandConst.foldedTrailing
        return max(0, min(textWidth, ear - around))
    }

    /// Width of a text in the font of `.mini` in the mock-up: 700 12px, rounded.
    static func width(of text: String) -> CGFloat {
        let base = NSFont.systemFont(ofSize: 12, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
        // Figures are drawn at a fixed width, a little wider than their natural one
        let figures = CGFloat(text.filter(\.isNumber).count)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2 + figures * 1.5
    }
}

// MARK: - Compact island (`.compact`): Yumi in the left ear, what is live in the right one

struct IslandCompactLayer: View {
    let content: FoldedContent
    let ear: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: IslandConst.foldedGap) {
            if let module = content.module, let live = content.live {
                Circle()
                    .fill(Color(hex: module.colorHex))
                    .frame(width: IslandConst.foldedDot, height: IslandConst.foldedDot)
                    .transition(.opacity)

                FoldedLine(moduleID: module.id, text: live.text)
                    .frame(width: content.textSlot(ear: ear), height: height)

                if !content.controls.isEmpty {
                    HStack(spacing: IslandConst.foldedControlGap) {
                        ForEach(content.controls) { control in
                            FoldedControl(control: control) {
                                IslandActions.liveControl(module.id, control.id)
                            }
                        }
                    }
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(.leading, IslandConst.foldedLeading)
        .padding(.trailing, IslandConst.foldedTrailing)
        // What is behind the notch is not seen: everything stays in the right ear, against
        // the right edge of the island, whatever width the island has at this instant.
        .frame(width: ear, height: height, alignment: .trailing)
        .clipped()
        .animation(.islandSpring(0.4), value: content.controls)
        .animation(.islandEase(0.25), value: content.module?.id)
    }
}

/// The live text, on one line. Too long, it is cut with an ellipsis. When it becomes another
/// line (the next track, another module) the old one slides out upwards and the new one
/// slides in from below; a text that only ticks (a countdown) changes in place.
private struct FoldedLine: View {
    let moduleID: String
    let text: String

    /// The text on screen. It follows `text`, one update later, so that the line going out
    /// still shows what it said.
    @State private var shown: String
    /// Changes only when there is something new to read.
    @State private var generation = 0

    init(moduleID: String, text: String) {
        self.moduleID = moduleID
        self.text = text
        _shown = State(initialValue: text)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(shown)
                .font(IslandTheme.round(12, .bold))
                .monospacedDigit()
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .id(generation)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)))
        }
        .clipped()
        .onChange(of: [moduleID, text]) { old, new in
            if old[0] != new[0] || FoldedIsland.isNewLine(old[1], new[1]) {
                withAnimation(.islandSpring(0.45)) {
                    shown = new[1]
                    generation += 1
                }
            } else {
                shown = new[1]
            }
        }
    }
}

/// A button of the folded island, drawn with its SF Symbol.
private struct FoldedControl: View {
    let control: ModuleControl
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: control.symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(IslandTheme.fg)
                .frame(width: IslandConst.foldedControl, height: IslandConst.foldedControl)
                .background(Circle().fill(hover ? IslandTheme.raise : IslandTheme.surface))
                .contentShape(Circle())
        }
        .buttonStyle(RoundPress())
        .onHover { hover = $0 }
        .accessibilityLabel(control.label)
        .help(control.label)
    }
}

// MARK: - The bubble of the second activity

/// A second activity lives in a bubble that detaches from the folded island like a drop
/// (`#goo`, `#bub` in the mock-up): the two black shapes are blurred then thresholded
/// together, so that they pull on each other while the bubble leaves.
struct FoldedBubble: View {
    let module: ModuleSnapshot?
    /// Size of the folded island, and where its middle is in the panel.
    let island: CGSize
    let middle: CGFloat

    var body: some View {
        let on = module != nil
        ZStack(alignment: .topLeading) {
            GooWidth(width: island.width, height: island.height, middle: middle, out: on ? 1 : 0)
                .animation(.islandSpring(), value: island.width)

            // `#bubc`: what the bubble holds
            BubbleSlide(out: on ? 1 : 0, islandRight: middle + island.width / 2, height: island.height) {
                Group {
                    if let module {
                        if IslandModel.isMusic(module.id), (module.live?.priority ?? 0) >= ModuleLivePriority.activity {
                            WaveBars(color: module.color)
                        } else {
                            Image(systemName: module.glyph)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(module.color)
                        }
                    }
                }
                .opacity(on ? 1 : 0)
                .animation(.islandEase(0.25), value: on)
            }
            .animation(.islandSpring(0.7), value: on)
            .animation(.islandSpring(), value: island.width)
        }
        .allowsHitTesting(false)
    }
}

/// Where the bubble is: hidden inside the island's right end, or `bubbleGap` away from it.
private func bubbleLeft(islandRight: CGFloat, out: CGFloat) -> CGFloat {
    islandRight - IslandConst.bubbleWidth + (IslandConst.bubbleWidth + IslandConst.bubbleGap) * out
}

/// The island's width follows its own spring; the bubble inside follows another.
private struct GooWidth: View, Animatable {
    var width: CGFloat
    let height: CGFloat
    let middle: CGFloat
    let out: CGFloat

    nonisolated var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    var body: some View {
        GooShapes(width: width, height: height, middle: middle, out: out)
            .animation(.islandSpring(0.7), value: out)
    }
}

private struct GooShapes: View, Animatable {
    let width: CGFloat
    let height: CGFloat
    let middle: CGFloat
    var out: CGFloat

    nonisolated var animatableData: CGFloat {
        get { out }
        set { out = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            // `feGaussianBlur stdDeviation="5"` then alpha × 22 − 10
            context.addFilter(.alphaThreshold(min: 0.455, color: .black))
            context.addFilter(.blur(radius: 5))
            context.drawLayer { layer in
                // The island, a little inside its crisp shape, and taller than the screen
                // so that its top edge is not eaten by the blur
                let body = CGRect(x: middle - width / 2 + 2, y: -24, width: width - 4, height: height + 24 - 1)
                layer.fill(Path(roundedRect: body, cornerRadius: IslandConst.roundedCorner), with: .color(.black))
                let left = bubbleLeft(islandRight: middle + width / 2, out: out)
                let bubble = CGRect(x: left, y: 0, width: IslandConst.bubbleWidth, height: height)
                layer.fill(Path(roundedRect: bubble, cornerRadius: height / 2), with: .color(.black))
            }
        }
    }
}

private struct BubbleSlide<Content: View>: View, Animatable {
    var out: CGFloat
    var islandRight: CGFloat
    let height: CGFloat
    let content: Content

    init(out: CGFloat, islandRight: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.out = out
        self.islandRight = islandRight
        self.height = height
        self.content = content()
    }

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(out, islandRight) }
        set { out = newValue.first; islandRight = newValue.second }
    }

    var body: some View {
        content
            .frame(width: IslandConst.bubbleWidth, height: height)
            .position(x: bubbleLeft(islandRight: islandRight, out: out) + IslandConst.bubbleWidth / 2, y: height / 2)
    }
}
