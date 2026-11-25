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
    let collection: Int

    static let collections = ["山林", "小镇", "极光", "窗景"]
    static let cabin = Wallpaper(id: 31, name: "雪夜木屋", collection: 1)
    var showsWindowView: Bool { collection == 3 }
    static let all: [Wallpaper] = [
        ["蓝松山谷", "白岭", "雾谷", "暮色林线", "银湖", "远山剪影", "深冬小径", "月下松林"],
        ["暖灯镇", "平安夜", "桥畔初雪", "山城灯火", "晚归", "雪夜屋顶", "冬日黄昏", "钟楼余晖"],
        ["薄荷极光", "北纬七十度", "绿光之海", "星原", "紫夜", "北方来信", "流光", "雪原尽头"],
        ["壁炉旁", "窗边晚灯", "木屋雪夜", "林中窗景", "冬夜微光", "红窗", "初晨"]
    ].enumerated().flatMap { collection, names in
        names.enumerated().map { index, name in
            Wallpaper(id: collection * 8 + index, name: name, collection: collection)
        }
    } + [cabin]
}

enum WinterArtwork {
    private static let cabinImage: CGImage? = {
        guard let url = Bundle.main.url(forResource: "WinterCabin", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    static func render(_ wallpaper: Wallpaper, width: Int, height: Int) -> CGImage? {
        if wallpaper.id == Wallpaper.cabin.id, let image = cabinImage {
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
        return bitmap(width: width, height: height) { ink in
            let w: CGFloat = 1200
            let h: CGFloat = 750
            let scale = max(CGFloat(width) / w, CGFloat(height) / h)
            ink.ctx.translateBy(x: (CGFloat(width) - w * scale) / 2, y: (CGFloat(height) - h * scale) / 2)
            ink.ctx.scaleBy(x: scale, y: scale)
            landscape(ink, wallpaper: wallpaper, w: w, h: h)
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

    private static func landscape(_ ink: Ink, wallpaper: Wallpaper, w: CGFloat, h: CGFloat) {
        let schemes: [[UInt32]] = [
            [0x092239, 0x2c5875, 0x9dbbd0, 0x304e68, 0x143850, 0x142c42, 0x7ca7bc],
            [0x101a3b, 0x515d83, 0xe1a09d, 0x505679, 0x363d66, 0x1d314e, 0xab9fbb],
            [0x071d30, 0x1d3e51, 0x82a3ae, 0x334d59, 0x183d47, 0x102e3c, 0x7cb1ae],
            [0x191635, 0x515077, 0xbb9daf, 0x4d5378, 0x333d69, 0x282b50, 0x9990b1],
            [0x132741, 0x52768a, 0xc5b3aa, 0x536878, 0x335162, 0x1e374e, 0xa2b9c5],
            [0x131c37, 0x33395e, 0x8599b8, 0x39465c, 0x253b58, 0x1b2c48, 0x748eae]
        ]
        let scheme = schemes[(wallpaper.id * 5 + wallpaper.collection) % schemes.count]
        var rng = SnowRandom(state: UInt64(wallpaper.id + 61) * 480_941)
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        ink.gradient(bounds, Array(scheme.prefix(3)) + [scheme[3]])

        let moon = p(rng.inRange(368, 932), rng.inRange(132, 235))
        let moonRadius = rng.inRange(25, 47)
        ink.glow(moon.x, moon.y, 153, 0xe4efff, alpha: 0.32)
        ink.circle(moon.x, moon.y, moonRadius, 0xffedc9, alpha: 0.94)
        for _ in 0..<195 {
            let x = rng.inRange(0, w)
            let y = rng.inRange(0, 410)
            let radius = rng.inRange(0.35, 1.55)
            ink.circle(x, y, radius, 0xf2f8ff, alpha: rng.inRange(0.14, 0.67))
        }

        if wallpaper.collection == 2 {
            for band in 0..<25 {
                let b = CGFloat(band)
                let points = (0...64).map { index -> CGPoint in
                    let x = CGFloat(index) * w / 64
                    let y = 214 + sin(x / 222 + CGFloat(wallpaper.id) * 0.3) * 67
                        + sin(x / 105) * 13 + b * (2.0 + 1.2 * sin(x / 312))
                    return p(x, y)
                }
                ink.line(points, band < 13 ? 0x83ffe0 : 0x82bdff, width: 5.5, alpha: 0.066)
            }
        }

        for ridge in 0..<3 {
            let base = CGFloat(372 + ridge * 63)
            var points: [CGPoint] = []
            for i in 0...16 {
                let x = CGFloat(i) * w / 16
                let y = base - rng.inRange(0, ridge == 0 ? 147 : 75) * (i.isMultiple(of: 3) ? 1.0 : 0.53)
                points.append(p(x, y))
            }
            ink.poly(points + [p(w, h), p(0, h)], scheme[ridge + 3], alpha: ridge == 0 ? 0.64 : 0.91)
            for i in 1..<(points.count - 1) where points[i].y < points[i - 1].y && points[i].y < points[i + 1].y {
                let top = points[i]
                let left = points[i - 1]
                let right = points[i + 1]
                ink.poly([p(top.x - (top.x - left.x) * 0.48, top.y + (left.y - top.y) * 0.48), top,
                          p(top.x + (right.x - top.x) * 0.55, top.y + (right.y - top.y) * 0.55),
                          p(top.x + 12, top.y + 22), p(top.x - 2, top.y + 26)],
                         scheme[2], alpha: 0.48)
            }
        }

        for layer in 0..<3 {
            let yBase = CGFloat(467 + layer * 58)
            var snowbank: [CGPoint] = []
            for i in 0...33 {
                let x = CGFloat(i) * w / 33
                snowbank.append(p(x, yBase + sin(x / 175 + CGFloat(layer)) * (14 + CGFloat(layer) * 7)))
            }
            ink.poly(snowbank + [p(w, h), p(0, h)], layer.isMultiple(of: 2) ? scheme[6] : scheme[3],
                     alpha: layer == 1 ? 0.94 : 0.76)
            let treeCount = layer == 0 ? 123 : layer == 1 ? 55 : 15
            for index in 0..<treeCount {
                let x = rng.inRange(-25, w + 25)
                let spread = wallpaper.collection == 1 ? CGFloat(145) : CGFloat(220)
                if layer == 2 && abs(x - w / 2) < spread && index > 2 { continue }
                let y = yBase + rng.inRange(-15, layer == 2 ? 156 : 50)
                let size = rng.inRange(12, CGFloat(53 + layer * layer * 25))
                pine(ink, x: x, y: y, size: size, shade: layer == 2 ? scheme[5] : scheme[4],
                     frost: scheme[6], rng: &rng)
            }
        }

        let valley = wallpaper.collection == 0 || wallpaper.collection == 2
        if valley {
            let river = [
                p(657, 508), p(715, 517), p(618, 557), p(589, 587), p(725, 641),
                p(923, h), p(552, h), p(520, 650), p(507, 617), p(521, 580), p(595, 542)
            ]
            ink.poly(river, scheme[4], alpha: 0.63)
            for _ in 0..<80 {
                let y = rng.inRange(542, h)
                let x = rng.inRange(537, 580 + (y - 540) * 1.20)
                ink.line([p(x, y), p(x + rng.inRange(5, 55), y)], scheme[2], width: rng.inRange(0.45, 1.5), alpha: 0.22)
            }
        }

        if wallpaper.collection == 1 {
            for i in 0..<10 {
                let x = 235 + CGFloat(i) * 80 + rng.inRange(-34, 34)
                let y = rng.inRange(510, 650)
                cabin(ink, x: x, y: y, size: rng.inRange(37, i == 6 ? 104 : 81), scheme: scheme,
                      tower: i == (wallpaper.id % 7))
            }
        } else {
            let side = wallpaper.id.isMultiple(of: 2) ? CGFloat(925) : 328
            cabin(ink, x: side, y: rng.inRange(568, 645), size: rng.inRange(65, 112), scheme: scheme, tower: false)
        }

        for _ in 0..<1050 {
            let x = rng.inRange(0, w)
            let y = rng.inRange(0, h)
            ink.circle(x, y, rng.inRange(0.2, 1.05), 0xe8f4ff, alpha: rng.inRange(0.05, 0.26))
        }

        if wallpaper.collection == 3 {
            ink.fill(CGRect(x: 0, y: 0, width: w, height: 59), 0x151a24)
            ink.fill(CGRect(x: 0, y: h - 96, width: w, height: 96), 0x191c27)
            ink.fill(CGRect(x: 0, y: 0, width: 79, height: h), 0x211e28)
            ink.fill(CGRect(x: w - 79, y: 0, width: 79, height: h), 0x211e28)
            for x in [CGFloat(78), w / 2, w - 78] {
                ink.fill(CGRect(x: x - 8, y: 48, width: 16, height: h - 135), 0x1d2330)
                ink.fill(CGRect(x: x + 4, y: 48, width: 2, height: h - 135), 0xae8574, alpha: 0.38)
            }
            ink.fill(CGRect(x: 72, y: 340, width: w - 144, height: 12), 0x262637)
            ink.line([p(0, h - 92), p(w, h - 92)], 0x9a746b, width: 3, alpha: 0.66)
            let candle = wallpaper.id.isMultiple(of: 2) ? w - 196 : 193
            ink.glow(candle, h - 150, 135, 0xffb264, alpha: 0.27)
            ink.rounded(CGRect(x: candle - 13, y: h - 135, width: 26, height: 39), 4, 0xefc7a1)
            ink.oval(CGRect(x: candle - 4, y: h - 156, width: 8, height: 19), 0xffdb8b)
        }
    }

    private static func pine(_ ink: Ink, x: CGFloat, y: CGFloat, size: CGFloat,
                             shade: UInt32, frost: UInt32, rng: inout SnowRandom) {
        let lean = rng.inRange(-3, 3)
        ink.line([p(x, y + size * 0.09), p(x + lean, y - size)], shade, width: max(1.2, size * 0.021))
        for row in 0..<9 {
            let t = CGFloat(row) / 9
            let yy = y - size + size * t
            let width = size * (0.055 + t * 0.24) * rng.inRange(0.76, 1.22)
            ink.poly([p(x + lean * (1 - t), yy - size * 0.1), p(x - width, yy + size * 0.2),
                      p(x - width * 0.3, yy + size * 0.14), p(x - width * 0.43, yy + size * 0.22),
                      p(x + width * 0.22, yy + size * 0.15), p(x + width, yy + size * 0.18)], shade)
            if row.isMultiple(of: 2) {
                ink.line([p(x - width * 0.74, yy + size * 0.16), p(x - width * 0.23, yy + size * 0.1),
                          p(x + width * 0.63, yy + size * 0.12)], frost, width: max(0.5, size * 0.008), alpha: 0.4)
            }
        }
    }

    private static func cabin(_ ink: Ink, x: CGFloat, y: CGFloat, size: CGFloat, scheme: [UInt32], tower: Bool) {
        let height = size * (tower ? 1.11 : 0.58)
        let left = x - size * 0.46
        let right = x + size * 0.46
        let roofY = y - height
        ink.oval(CGRect(x: x - size * 0.8, y: y - 7, width: size * 1.6, height: size * 0.18),
                 scheme[4], alpha: 0.34)
        ink.fill(CGRect(x: left, y: roofY, width: right - left, height: height), 0x2c3445)
        ink.fill(CGRect(x: x + size * 0.12, y: roofY - size * 0.32, width: size * 0.12, height: size * 0.41), 0x3e3b49)
        ink.poly([p(left - size * 0.13, roofY + 3), p(x - size * 0.04, roofY - size * 0.40),
                  p(right + size * 0.13, roofY + 3)], 0x253349)
        ink.line([p(left - size * 0.11, roofY), p(x - size * 0.04, roofY - size * 0.40),
                  p(right + size * 0.13, roofY)], scheme[2], width: max(1.7, size * 0.048), alpha: 0.92)
        for index in 0..<(tower ? 4 : 2) {
            let wx = x + (index.isMultiple(of: 2) ? -0.20 : 0.20) * size
            let wy = y - size * (index < 2 ? 0.34 : 0.77)
            ink.glow(wx, wy, size * 0.49, 0xffba71, alpha: 0.55)
            ink.rounded(CGRect(x: wx - size * 0.079, y: wy - size * 0.076,
                               width: size * 0.158, height: size * 0.15), 1.5, 0xffd285)
            ink.line([p(wx, wy - size * 0.065), p(wx, wy + size * 0.065)], 0x865645, width: 1.25)
        }
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
        guard let image = WinterArtwork.render(wallpaper, width: 360, height: 225) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: 360, height: 225))
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
