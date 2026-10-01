// Renders the app icon and the menu bar icon with YumiSkin, the drawing code of the app.
// Not compiled into the app: run design/yumi/outils/icones.sh, which pairs this file with
// the YumiSkin block of BotEngine.swift.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
enum Icones {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("usage: icones <path to Assets.xcassets>")
            exit(1)
        }
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        try writeAppIcon(to: assets.appendingPathComponent("AppIcon.appiconset"))
        try writeMenuBarIcon(to: assets.appendingPathComponent("MenuBarIcon.imageset"))
    }

    // MARK: - Bitmaps

    /// RGBA bitmap with the origin at the top left, like the canvases of the app.
    static func bitmap(_ w: Int, _ h: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        return ctx
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - App icon

    /// Yumi on a dark tile, lit from below by its own rim colours. Laid out on a 1024 grid.
    static func appIcon(_ px: Int) -> CGImage {
        let ctx = bitmap(px, px)
        let s = CGFloat(px) / 1024

        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 186, cornerHeight: 186, transform: nil)

        // Tile with the usual soft shadow under it (shadow offsets are in pixels, y up)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 22 * s, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(tile)
        ctx.setFillColor(YumiSkin.ink.cg())
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(tile)
        ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let top = YumiSkin.ink.mix(YumiSkin.indigo, 0.42), bottom = YumiSkin.ink.mix(YumiRGB(0, 0, 0), 0.3)
        let back = CGGradient(colorsSpace: cs, colors: [top.cg(), bottom.cg()] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(back, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

        // Light pooled on the floor: blue on the left, pink on the right, like the rim
        for (colour, x) in [(YumiSkin.blue, CGFloat(380)), (YumiSkin.violet, 512), (YumiSkin.rose, 650)] {
            let pool = CGGradient(colorsSpace: cs, colors: [colour.cg(0.42), colour.cg(0)] as CFArray, locations: [0, 1])!
            ctx.saveGState()
            ctx.translateBy(x: x, y: 770)
            ctx.scaleBy(x: 1, y: 0.34)
            ctx.drawRadialGradient(pool, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 300, options: [])
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // The character is drawn in pixels, not on the grid, so that the small sizes get the
        // same treatment as in the app (bigger eyes, rim never thinner than a pixel).
        ctx.translateBy(x: 512 * s, y: 548 * s)
        YumiSkin.drawFigure(ctx, R: 262 * s, glow: 1)
        return ctx.makeImage()!
    }

    static func writeAppIcon(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var images: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
                try writePNG(appIcon(size * scale), to: folder.appendingPathComponent(name))
                images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
            }
        }
        try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]],
                      to: folder.appendingPathComponent("Contents.json"))
    }

    // MARK: - Menu bar icon

    /// Template image, 24 × 18 pt (the size AppDelegate gives it): the silhouette is opaque,
    /// the whites of the eyes are holes, the pupils are opaque again.
    static func menuBarIcon(scale: Int) -> CGImage {
        let w = 24 * scale, h = 18 * scale
        let R: CGFloat = 9.4
        let body = YumiSkin.bodyPath(hw: R * YumiSkin.bodyHW, hh: R * YumiSkin.bodyHH)

        func layer(_ draw: (CGContext) -> Void) -> [UInt8] {
            let ctx = bitmap(w, h)
            ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            ctx.translateBy(x: 12, y: 9.2)
            draw(ctx)
            return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
        }
        // Coverage of the body, in the alpha channel
        let silhouette = layer { ctx in
            ctx.addPath(body)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
        }
        // The eyes as the app draws them, on black: white where the icon must be see-through
        let face = layer { ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: -50, y: -50, width: 100, height: 100))
            ctx.addPath(body)
            ctx.clip()
            YumiSkin.drawEyes(ctx, R: R, eyes: YumiEyes())
        }

        let out = bitmap(w, h)
        let px = out.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(w * h) {
            let alpha = Double(silhouette[i * 4 + 3]) * (1 - Double(face[i * 4]) / 255)
            px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0
            px[i * 4 + 3] = UInt8(max(0, min(255, alpha.rounded())))
        }
        return out.makeImage()!
    }

    static func writeMenuBarIcon(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var images: [[String: String]] = []
        for scale in [1, 2, 3] {
            let name = scale == 1 ? "menubar.png" : "menubar@\(scale)x.png"
            try writePNG(menuBarIcon(scale: scale), to: folder.appendingPathComponent(name))
            images.append(["idiom": "universal", "scale": "\(scale)x", "filename": name])
        }
        try writeJSON(["images": images, "info": ["author": "xcode", "version": 1],
                       "properties": ["template-rendering-intent": "template"]],
                      to: folder.appendingPathComponent("Contents.json"))
    }
}
