import AppKit
import SwiftUI

// When Yumi speaks first (Contracts/RemarkTypes.swift, design/yumi/voix.md): one sentence
// next to him, at most one action, and a cross. Folded, the island widens just enough for
// it. Open, the sentence sits above the rail and the activity stays where it is.

/// The sentence, its optional action and its cross.
struct RemarkLine: View {
    let remark: YumiRemark
    var lines = 2
    @ObservedObject var model: IslandModel
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(remark.text)
                .font(IslandTheme.text(12.5, .medium))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(lines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action = remark.action {
                Button { model.accept(remark) } label: {
                    Text(action)
                        .font(IslandTheme.text(11.5, .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(RoundPress())
            }
            Button { model.close(remark, ignored: false) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(hover ? Color.white : IslandTheme.muted)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        // A click anywhere else on the sentence closes it too
        .contentShape(Rectangle())
        .onTapGesture { model.close(remark, ignored: false) }
        .onHover { hover = $0 }
    }

    /// Width of a text in the font of the sentence.
    static func width(of text: String, size: CGFloat = 12.5, weight: NSFont.Weight = .medium) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 2
    }

    /// The shape the folded island takes for this remark.
    static func size(for remark: YumiRemark, minimum: CGFloat) -> Speak.Size {
        Speak.size(text: Double(width(of: remark.text)),
                   action: remark.action.map { Double(width(of: $0, size: 11.5, weight: .semibold)) + 20 } ?? 0,
                   minimum: Double(minimum))
    }
}

/// The folded island while Yumi speaks: him on the left under the notch, the sentence beside him.
struct IslandSpeakLayer: View {
    let remark: YumiRemark?
    let size: Speak.Size
    let notchHeight: CGFloat
    @ObservedObject var model: IslandModel

    var body: some View {
        Group {
            if let remark {
                RemarkLine(remark: remark, lines: size.lines, model: model)
                    .padding(.leading, Speak.lead)
                    .padding(.trailing, Speak.trail)
                    .frame(width: size.width, height: size.band)
                    .padding(.top, notchHeight - 2)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: notchHeight + size.band, alignment: .topLeading)
    }
}
