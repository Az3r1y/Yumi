import AppKit
import SwiftUI

// MARK: - NSView drag destination
// Wired at the AppKit level in IslandWindowController (not via SwiftUI NSViewRepresentable)
// so it never interferes with SwiftUI hit-testing.

final class FileDropNSView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited:  (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Pass all mouse events through — drag-drop uses NSDraggingDestination, not hitTest
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExited?() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - File drop handler

enum FileDropHandler {
    /// Yumi was handed a file: he swallows it with a bounce, keeps a copy in his inbox, and
    /// the drop view asks what to do with it (summarize, send, put away).
    @MainActor
    static func handle(urls: [URL], state: AppState) {
        guard let url = urls.first else { return }
        let name = url.lastPathComponent

        // A new file is a new subject for the conversation
        IslandActions.newConversation()

        // Use the original URL first; swap to the inbox copy once the background copy finishes.
        state.droppedFile = DroppedFile(url: url, name: name)
        state.fileDragOver = false
        state.promptContext = .file(name: name, fileURL: url)
        state.contextAttached = true
        state.contextExplicit = true

        let inbox = AppIdentity.inboxDirectory
        Task.detached {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                await MainActor.run {
                    // Still the same file: the user may have dropped another one meanwhile
                    guard state.droppedFile?.url == url else { return }
                    state.droppedFile = DroppedFile(url: dest, name: name)
                    state.promptContext = .file(name: name, fileURL: dest)
                }
            }
        }

        // Drop feedback
        SoundEngine.shared.play("approve")
        IslandModel.shared.pose(.boing)

        state.view = .choose
        state.lastActivity = .now
    }
}
