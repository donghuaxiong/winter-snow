import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Ink {
    let ctx: CGContext

    func fill(_ rect: CGRect, _ color: UInt32, alpha: CGFloat = 1) {
        ctx.setFillColor(NSColor(rgb: color, alpha: alpha).cgColor)
        ctx.fill(rect)
    }

    func oval(_ rect: CGRect, _ color: UInt32, alpha: CGFloat = 1) {
        ctx.setFillColor(NSColor(rgb: color, alpha: alpha).cgColor)
        ctx.fillEllipse(in: rect)
    }

    func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: UInt32, alpha: CGFloat = 1) {
        oval(CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), color, alpha: alpha)
    }

    func rounded(_ rect: CGRect, _ radius: CGFloat, _ color: UInt32, alpha: CGFloat = 1) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(NSColor(rgb: color, alpha: alpha).cgColor)
        ctx.fillPath()
    }

    func poly(_ points: [CGPoint], _ color: UInt32, alpha: CGFloat = 1) {
        guard let first = points.first else { return }
        ctx.beginPath()
        ctx.move(to: first)
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.setFillColor(NSColor(rgb: color, alpha: alpha).cgColor)
        ctx.fillPath()
    }

    func line(_ points: [CGPoint], _ color: UInt32, width: CGFloat = 1, alpha: CGFloat = 1) {
        guard points.count > 1 else { return }
        ctx.beginPath()
        ctx.addLines(between: points)
        ctx.setStrokeColor(NSColor(rgb: color, alpha: alpha).cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    func gradient(_ rect: CGRect, _ colors: [UInt32]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors.map { NSColor(rgb: $0).cgColor } as CFArray,
                                        locations: nil) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    func glow(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: UInt32, alpha: CGFloat = 0.5) {
        let colors = [NSColor(rgb: color, alpha: alpha).cgColor, NSColor(rgb: color, alpha: 0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors as CFArray, locations: [0, 1]) else { return }
        let point = CGPoint(x: x, y: y)
        ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                               endCenter: point, endRadius: radius, options: [])
    }

    func star(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: UInt32, points: Int = 5) {
        poly((0..<(points * 2)).map { index in
            let angle = CGFloat(index) * .pi / CGFloat(points) - .pi / 2
            let length = index.isMultiple(of: 2) ? radius : radius * 0.39
            return CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length)
        }, color)
    }

    func text(_ value: String, at point: CGPoint, size: CGFloat, color: UInt32, weight: NSFont.Weight = .medium) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(rgb: color)
        ]
        let string = NSAttributedString(string: value, attributes: attributes)
        let bounds = string.size()
        string.draw(at: CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

struct SnowRandom {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 2862933555777941757 &+ 3037000493
        return CGFloat(state >> 40) / 16_777_216
    }

    mutating func inRange(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        lower + (upper - lower) * next()
    }
}

struct Wallpaper: Identifiable {
    let id: Int
    let name: String
    let fileName: String
    private var subdirectory: String? = "Wallpapers"

    // Keep the cabin's original ID. The generated winter collection starts after the retired IDs.
    static let cabin = Wallpaper(id: 31, name: "雪夜木屋", fileName: "WinterCabin", subdirectory: nil)
    static let winter: [Wallpaper] = [
        cabin,
        Wallpaper(id: 32, name: "雪岭晨曦", fileName: "alpine-dawn"),
        Wallpaper(id: 33, name: "雪后镜湖", fileName: "frost-lake"),
        Wallpaper(id: 34, name: "白桦静雪", fileName: "birch-hush"),
        Wallpaper(id: 35, name: "雪岸潮声", fileName: "frost-coast"),
        Wallpaper(id: 36, name: "雪町灯火", fileName: "snow-village"),
        Wallpaper(id: 37, name: "北境极光", fileName: "north-lights"),
        Wallpaper(id: 38, name: "月照雪松", fileName: "moon-cedars")
    ]
    static let christmas: [Wallpaper] = [
        Wallpaper(id: 39, name: "林间鹿影", fileName: "reindeer-lanterns"),
        Wallpaper(id: 40, name: "圣诞夜来客", fileName: "santa-rooftop"),
        Wallpaper(id: 41, name: "雪镇圣诞树", fileName: "christmas-square"),
        Wallpaper(id: 42, name: "星夜归途", fileName: "sleigh-under-stars")
    ]
    static let all = winter + christmas

    static func isRetired(_ id: Int?) -> Bool {
        guard let id else { return false }
        return (0..<cabin.id).contains(id)
    }

    var resourceURL: URL? {
        Bundle.main.url(forResource: fileName, withExtension: "jpg", subdirectory: subdirectory)
    }
}

enum WinterArtwork {
    static func render(_ wallpaper: Wallpaper, width: Int, height: Int) -> CGImage? {
        guard let url = wallpaper.resourceURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return bitmap(width: width, height: height) { ink in
            let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
            let w = CGFloat(image.width) * scale
            let h = CGFloat(image.height) * scale
            ink.ctx.translateBy(x: 0, y: CGFloat(height))
            ink.ctx.scaleBy(x: 1, y: -1)
            ink.ctx.interpolationQuality = .high
            ink.ctx.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2,
                                           y: (CGFloat(height) - h) / 2, width: w, height: h))
        }
    }

    static func bitmap(width: Int, height: Int, draw: (Ink) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(Ink(ctx: context))
        return context.makeImage()
    }
}

@MainActor
final class WallpaperService: ObservableObject {
    private weak var model: SnowModel?
    private let thumbnails = NSCache<NSNumber, NSImage>()
    private let workspace = NSWorkspace.shared
    private let folder = URL.applicationSupportDirectory.appending(path: "Snowglow/Wallpapers", directoryHint: .isDirectory)

    init(model: SnowModel) { self.model = model }

    func thumbnail(_ wallpaper: Wallpaper) -> NSImage? {
        if let existing = thumbnails.object(forKey: NSNumber(value: wallpaper.id)) { return existing }
        guard let image = WinterArtwork.render(wallpaper, width: 480, height: 270) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: 480, height: 270))
        thumbnails.setObject(result, forKey: NSNumber(value: wallpaper.id))
        return result
    }

    func apply(_ index: Int) {
        guard let model, let wallpaper = Wallpaper.all.first(where: { $0.id == index }) else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        var previous = model.originals
        var changed = 0
        for screen in screens {
            do {
                let url = try file(for: wallpaper, screen: screen)
                let id = screen.snowScreenID
                let current = workspace.desktopImageURL(for: screen)
                let currentOptions = workspace.desktopImageOptions(for: screen)
                let needsBackup = previous[id] == nil && current?.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL
                let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true
                ]
                try workspace.setDesktopImageURL(url, for: screen, options: options)
                if needsBackup, let current {
                    previous[id] = OriginalWallpaper(url: current,
                                                     scaling: currentOptions?[.imageScaling] as? Int,
                                                     clipping: currentOptions?[.allowClipping] as? Bool)
                }
                changed += 1
            } catch {
                NSLog("Snowglow wallpaper: %@", error.localizedDescription)
            }
        }
        if changed > 0 {
            model.originals = previous
            model.settings.wallpaper = index
            model.persist()
        }
        model.feedback = changed == screens.count ? "已设为壁纸 · \(wallpaper.name)"
            : changed == 0 ? "无法更换壁纸，请在系统设置中重试。" : "已更新 \(changed) 台显示器的壁纸。"
    }

    func restore() {
        guard let model else { return }
        let screens = NSScreen.screens
        var restored = 0
        for screen in screens {
            let id = screen.snowScreenID
            guard let old = model.originals[id] else { continue }
            do {
                var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
                if let scaling = old.scaling { options[.imageScaling] = scaling }
                if let clipping = old.clipping { options[.allowClipping] = clipping }
                try workspace.setDesktopImageURL(old.url, for: screen, options: options)
                model.originals.removeValue(forKey: id)
                restored += 1
            } catch {
                NSLog("Snowglow wallpaper restore: %@", error.localizedDescription)
            }
        }
        if model.originals.isEmpty { model.settings.wallpaper = nil }
        model.persist()
        model.feedback = restored == 0 ? "未找到可恢复的壁纸。" : "已恢复 \(restored) 台显示器的原壁纸。"
    }

    private func file(for wallpaper: Wallpaper, screen: NSScreen) throws -> URL {
        let size = screen.frame.size
        let aspect = size.width / max(size.height, 1)
        let width = Int(min(3840, 2400 * aspect))
        let height = Int(min(3840, CGFloat(width) / max(aspect, 0.1)))
        let url = folder.appending(path: "\(wallpaper.id)-\(width)x\(height).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let image = WinterArtwork.render(wallpaper, width: width, height: height),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.91] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (data as Data).write(to: url, options: .atomic)
        return url
    }
}
