import Foundation
import UniformTypeIdentifiers
import Vision

/// The text of an image, read on the Mac by Vision: a screenshot, a photo of a page. Nothing is
/// sent anywhere.
enum ImageText {
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// The lines read, top to bottom; nil when there is no text or the file is not an image.
    static func read(_ url: URL) async -> String? {
        guard isImage(url) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            guard (try? VNImageRequestHandler(url: url).perform([request])) != nil else { return nil }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.value
    }
}
