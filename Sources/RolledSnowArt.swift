import AppKit
import ImageIO

enum SnowballAtlas {
    static func crops(_ regions: [CGRect], from name: String) -> [CGImage?] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return Array(repeating: nil, count: regions.count)
        }
        return regions.map { image.cropping(to: $0) }
    }

    static func draw(_ image: CGImage, in rect: CGRect, ink: Ink) {
        let ctx = ink.ctx
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }
}

enum RolledSnowArt {
    private static let photos = SnowballAtlas.crops([
        CGRect(x: 20, y: 279, width: 478, height: 491),
        CGRect(x: 527, y: 280, width: 479, height: 489),
        CGRect(x: 1032, y: 281, width: 487, height: 485)
    ], from: "RolledSnowballs")

    static var photosAvailable: Bool { photos.allSatisfy { $0 != nil } }

    private static let shadow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [0.37, 0.17, 0].map { NSColor(rgb: 0x273d57, alpha: $0).cgColor } as CFArray,
        locations: [0, 0.61, 1]
    )!

    static func bounds(of ball: RolledSnowball) -> CGRect {
        let body = CGRect(around: ball.center, radius: ball.radius * 1.22 + 3)
        return SnowballPropArt.bounds(of: ball, including: body)
    }

    static func draw(_ ball: RolledSnowball, reduced: Bool, ink: Ink) {
        let radius = ball.radius
        let squeeze = reduced ? 0 : ball.compression
        let ctx = ink.ctx
        if case .surface = ball.rest {
            ctx.saveGState()
            ctx.translateBy(x: ball.center.x + radius * 0.1, y: ball.center.y + radius * 0.96)
            ctx.scaleBy(x: radius * 1.14, y: max(1, radius * 0.19))
            ctx.drawRadialGradient(shadow, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                   endRadius: 1, options: [.drawsBeforeStartLocation])
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: ball.center.x, y: ball.center.y + radius * squeeze * 0.13)
        ctx.scaleBy(x: 1 + 0.10 * squeeze, y: 1 - 0.17 * squeeze)
        let variant = Int(ball.id.uuid.0) % photos.count
        if let photo = photos[variant] {
            ctx.rotate(by: ball.rotation.remainder(dividingBy: .pi * 2))
            SnowballAtlas.draw(photo, in: CGRect(around: .zero, radius: radius * 1.028), ink: ink)
        } else {
            SnowmanArt.ball(.zero, radius: radius, ink: ink, tone: variant)
        }
        ctx.restoreGState()
        if !ball.props.isEmpty { SnowballPropArt.draw(on: ball, ink: ink) }
    }
}
