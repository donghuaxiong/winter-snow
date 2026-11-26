import AppKit
import CoreImage

struct ReindeerLegPose {
    let root: CGPoint
    let stifle: CGPoint?
    let joint: CGPoint
    let ankle: CGPoint
    let hoofAngle: CGFloat
    let farSide: Bool
    let planted: Bool
}

struct ReindeerPose {
    static let cycle: CGFloat = 0.71
    private static let shoulder = p(838, 550)
    private static let hip = p(333, 520)
    private static let floor: CGFloat = 934

    let body: CGAffineTransform
    let legs: [ReindeerLegPose]

    init(age: CGFloat, offset: CGFloat, reduced: Bool) {
        let agePhase = age / Self.cycle + offset
        let phase = reduced ? 0.19 : agePhase - Foundation.floor(agePhase)
        let stride = phase * 2 * .pi
        let surge = reduced ? 0 : -10 * sin(stride)
        let lift = reduced ? 0 : 19 * cos(stride * 2 + 0.52) - 8 * sin(stride)
        let pitch = reduced ? 0 : 0.059 * sin(stride + 0.51)
        let flex = reduced ? 1 : 1 + 0.031 * cos(stride * 2 - 0.71)
        let body = CGAffineTransform(translationX: 650 + surge, y: 535 + lift)
            .rotated(by: pitch)
            .scaledBy(x: flex, y: 1)
            .translatedBy(x: -650, y: -535)
        self.body = body
        // Diagonal pairs contact in staggered beats, with a brief gathered phase between them.
        legs = [
            Self.hindLeg(phase: phase, contact: 0.49, far: true, body: body, reduced: reduced),
            Self.foreleg(phase: phase, contact: 0.085, far: true, body: body, reduced: reduced),
            Self.hindLeg(phase: phase, contact: 0.00, far: false, body: body, reduced: reduced),
            Self.foreleg(phase: phase, contact: 0.59, far: false, body: body, reduced: reduced)
        ]
    }

    private static func foreleg(phase: CGFloat, contact: CGFloat, far: Bool,
                                body: CGAffineTransform, reduced: Bool) -> ReindeerLegPose {
        let x = shoulder.x + (far ? -29 : 0)
        let root = p(x, shoulder.y - (far ? 11 : 0)).applying(body)
        let ground = Self.floor - (far ? 23 : 0)
        let foot = footfall(phase - contact, center: x, floor: ground, reach: 207, trail: 172,
                            lift: 202, duty: 0.282, reduced: reduced, far: far)
        let chain = bentJoint(from: root, to: foot.position, first: 225, second: 218, bend: 1)
        return ReindeerLegPose(root: root, stifle: nil, joint: chain.joint, ankle: chain.end,
                               hoofAngle: foot.angle, farSide: far, planted: foot.planted)
    }

    private static func hindLeg(phase: CGFloat, contact: CGFloat, far: Bool,
                                body: CGAffineTransform, reduced: Bool) -> ReindeerLegPose {
        let x = hip.x + (far ? 32 : 0)
        let root = p(x, hip.y - (far ? 8 : 0)).applying(body)
        let ground = Self.floor - (far ? 23 : 0)
        let foot = footfall(phase - contact, center: x + 18, floor: ground, reach: 218, trail: 185,
                            lift: 159, duty: 0.295, reduced: reduced, far: far)
        let reaching = min(1, max(-1, (foot.position.x - x) / 215))
        let thighAngle = 0.37 + 0.41 * reaching + foot.fold * 0.18
        let stifle = p(root.x + sin(thighAngle) * 146, root.y + cos(thighAngle) * 146)
        let chain = bentJoint(from: stifle, to: foot.position, first: 166, second: 205, bend: -1)
        return ReindeerLegPose(root: root, stifle: stifle, joint: chain.joint, ankle: chain.end,
                               hoofAngle: foot.angle, farSide: far, planted: foot.planted)
    }

    private static func footfall(_ cycle: CGFloat, center: CGFloat, floor: CGFloat, reach: CGFloat, trail: CGFloat,
                                 lift: CGFloat, duty: CGFloat, reduced: Bool, far: Bool)
        -> (position: CGPoint, angle: CGFloat, planted: Bool, fold: CGFloat) {
        if reduced { return (p(center + (far ? -79 : 62), floor), 0, true, 0) }
        let phase = cycle - Foundation.floor(cycle)
        if phase < duty {
            let progress = phase / duty
            let angle = 0.31 * pow(progress, 5)
            return (p(center + reach - (reach + trail) * progress, floor - toeOffset(angle, far: far)), angle, true, 0)
        }

        let progress = (phase - duty) / (1 - duty)
        let remaining = 1 - progress
        // Follow through behind the body before the hoof folds up and reaches for the next stride.
        let behind = -trail - 68
        let forward = reach + 54
        let x = -trail * pow(remaining, 3) + 3 * behind * remaining * remaining * progress
            + 3 * forward * remaining * progress * progress + reach * pow(progress, 3)
        let arc = pow(sin(.pi * progress), 1.34) * (1.13 - 0.28 * progress)
        let angle = 0.31 * remaining + 0.91 * sin(2 * .pi * progress) * sqrt(remaining)
        return (p(center + x, floor - lift * arc - toeOffset(angle, far: far)), angle, false, arc)
    }

    private static func toeOffset(_ angle: CGFloat, far: Bool) -> CGFloat {
        (83 * sin(angle) + 60 * (cos(angle) - 1)) * (far ? 0.82 : 1)
    }

    private static func bentJoint(from root: CGPoint, to end: CGPoint, first: CGFloat, second: CGFloat, bend: CGFloat)
        -> (joint: CGPoint, end: CGPoint) {
        let dx = end.x - root.x, dy = end.y - root.y
        let distance = max(0.001, hypot(dx, dy))
        let span = min(first + second - 1, max(abs(first - second) + 1, distance))
        let x = dx / distance, y = dy / distance
        let projection = (first * first + span * span - second * second) / (2 * span)
        let excursion = bend * sqrt(max(0, first * first - projection * projection))
        let joint = p(root.x + x * projection + y * excursion, root.y + y * projection - x * excursion)
        return (joint, p(root.x + x * span, root.y + y * span))
    }
}

enum SleighFlightArt {
    private struct Sprites {
        let sleigh: CGImage
        let body: CGImage
        let thigh: CGImage
        let shoulder: CGImage
        let hoof: CGImage
    }

    private static let reindeerSheet = CGRect(x: 0, y: 0, width: 1536, height: 1024)
    private static let sprites: Sprites? = {
        let parts = SnowballAtlas.crops([
            reindeerSheet,
            CGRect(x: 275, y: 429, width: 110, height: 137),
            CGRect(x: 801, y: 548, width: 64, height: 215),
            CGRect(x: 139, y: 888, width: 126, height: 117)
        ], from: "FestiveFlightReindeer")
        guard let full = parts[0], let thigh = parts[1], let shoulder = parts[2], let hoof = parts[3],
              let sleigh = SnowballAtlas.crops([CGRect(x: 27, y: 7, width: 1470, height: 1008)], from: "FestiveFlightSleigh")[0],
              let body = maskedTorso(full) else { return nil }
        return Sprites(sleigh: sleigh, body: body, thigh: thigh, shoulder: shoulder, hoof: hoof)
    }()

    static var spritesAvailable: Bool { sprites != nil }

    private static func maskedTorso(_ original: CGImage) -> CGImage? {
        let reduced = CGRect(x: 0, y: 0, width: 1152, height: 768)
        guard let matte = WinterArtwork.bitmap(width: 1152, height: 768, draw: { ink in
            ink.ctx.scaleBy(x: 0.75, y: 0.75)
            ink.ctx.addPath(torsoOutline())
            ink.ctx.setFillColor(NSColor.white.cgColor)
            ink.ctx.fillPath()
        }) else { return nil }
        // Blend the photo's coat into the articulated thighs where the original standing legs were cropped.
        let feathered = CIImage(cgImage: matte).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8.0])
            .cropped(to: reduced)
        let alpha = CIContext().createCGImage(feathered, from: reduced) ?? matte
        return WinterArtwork.bitmap(width: 1152, height: 768) { ink in
            SnowballAtlas.draw(original, in: reduced, ink: ink)
            ink.ctx.setBlendMode(.destinationIn)
            SnowballAtlas.draw(alpha, in: reduced, ink: ink)
        }
    }

    private static func torsoOutline() -> CGPath {
        let path = CGMutablePath()
        path.move(to: p(0, 555))
        path.addLine(to: p(190, 547))
        path.addQuadCurve(to: p(238, 569), control: p(225, 550))
        path.addCurve(to: p(388, 599), control1: p(273, 609), control2: p(335, 616))
        path.addCurve(to: p(450, 649), control1: p(417, 598), control2: p(435, 629))
        path.addLine(to: p(715, 654))
        path.addCurve(to: p(870, 628), control1: p(772, 654), control2: p(837, 653))
        path.addCurve(to: p(947, 635), control1: p(902, 614), control2: p(928, 606))
        path.addQuadCurve(to: p(1100, 696), control: p(989, 685))
        path.addLine(to: p(1536, 696))
        path.addLine(to: p(1536, 0))
        path.addLine(to: p(0, 0))
        path.closeSubpath()
        return path
    }

    private struct Deer {
        let origin: CGPoint
        let scale: CGFloat
        let pose: ReindeerPose

        func mount(at anchor: CGPoint) -> CGPoint {
            let point = anchor.applying(pose.body)
            return p(origin.x + point.x * scale, origin.y + point.y * scale)
        }
    }

    private static let limbShade = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [NSColor(rgb: 0xf1d8b4, alpha: 0.22), NSColor(rgb: 0x261b20, alpha: 0),
                 NSColor(rgb: 0x221720, alpha: 0.27)].map(\.cgColor) as CFArray,
        locations: [0, 0.40, 1]
    )!

    static func draw(_ pass: SleighFlight, in size: CGSize, reduced: Bool, ink: Ink) {
        guard let sprites else { return }
        let frame = pass.frame(in: size)
        let ctx = ink.ctx
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: pass.direction > 0 ? frame.minX : frame.maxX, y: frame.minY)
        ctx.scaleBy(x: pass.direction, y: 1)

        let age = pass.age
        let bob = reduced ? 0 : 2.0 * sin(age * 7.4 - 0.25)
        let pitch = reduced ? 0 : 0.023 * sin(age * 7.4 - 0.91)
        let sled = CGAffineTransform(translationX: 89, y: 105 + bob)
            .rotated(by: pitch)
            .translatedBy(x: -89, y: -105)
        let rear = Deer(origin: p(158, 12), scale: 0.096, pose: ReindeerPose(age: age, offset: 0.0, reduced: reduced))
        let lead = Deer(origin: p(282, 8), scale: 0.092, pose: ReindeerPose(age: age, offset: 0.34, reduced: reduced))
        let hand = p(115, 45).applying(sled)
        let hitch = p(148, 91).applying(sled)
        let variation = reduced ? 0 : sin(age * 8.0)
        if !reduced { drawFrost(age, ink: ink) }

        trace(from: hitch, to: rear.mount(at: p(768, 490)), slack: 3.7 + 0.6 * variation, ink: ink)
        trace(from: rear.mount(at: p(290, 537)), to: lead.mount(at: p(768, 490)), slack: 4.0 + variation, ink: ink)
        trace(from: p(hand.x - 2, hand.y - 2.2), to: lead.mount(at: p(1150, 360)), slack: 7.0 - variation, ink: ink)
        draw(rear, sprites: sprites, ink: ink)
        draw(lead, sprites: sprites, ink: ink)
        trace(from: hand, to: rear.mount(at: p(1150, 360)), slack: 8.1 + 1.4 * variation, ink: ink)

        ctx.saveGState()
        ctx.concatenate(sled)
        let flicker = reduced ? 1 : 0.91 + 0.07 * sin(age * 13.3) + 0.04 * sin(age * 29)
        ink.glow(147, 82, 18, 0xffa649, alpha: 0.25 * flicker)
        SnowballAtlas.draw(sprites.sleigh, in: CGRect(x: 24, y: 15, width: 149, height: 102.2), ink: ink)
        ink.glow(147, 82, 6, 0xffc569, alpha: 0.27 * flicker)
        ctx.restoreGState()
    }

    private static func trace(from a: CGPoint, to b: CGPoint, slack: CGFloat, ink: Ink) {
        let width = b.x - a.x, height = b.y - a.y
        let curve = CGMutablePath()
        curve.move(to: a)
        curve.addCurve(to: b, control1: p(a.x + width * 0.27, a.y + height * 0.25 + slack),
                       control2: p(a.x + width * 0.73, a.y + height * 0.75 + slack))
        let ctx = ink.ctx
        ctx.setLineCap(.round)
        ctx.addPath(curve)
        ctx.setStrokeColor(NSColor(rgb: 0x291b1a, alpha: 0.91).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.addPath(curve)
        ctx.setStrokeColor(NSColor(rgb: 0xbf9870, alpha: 0.81).cgColor)
        ctx.setLineWidth(0.65)
        ctx.strokePath()
    }

    private static func draw(_ deer: Deer, sprites: Sprites, ink: Ink) {
        let ctx = ink.ctx
        ctx.saveGState()
        ctx.translateBy(x: deer.origin.x, y: deer.origin.y)
        ctx.scaleBy(x: deer.scale, y: deer.scale)
        for leg in deer.pose.legs {
            draw(leg, sprites: sprites, ink: ink)
        }
        ctx.concatenate(deer.pose.body)
        SnowballAtlas.draw(sprites.body, in: reindeerSheet, ink: ink)
        ctx.restoreGState()
    }

    private static func draw(_ leg: ReindeerLegPose, sprites: Sprites, ink: Ink) {
        let width: CGFloat = leg.farSide ? 0.82 : 1
        let ctx = ink.ctx
        var bones = [(point: leg.root, width: (leg.stifle == nil ? 78.0 : 101.0) * width)]
        if let stifle = leg.stifle { bones.append((stifle, 51 * width)) }
        bones.append((leg.joint, 23 * width))
        bones.append((leg.ankle, 16 * width))
        let shell = CGMutablePath()
        for (start, end) in zip(bones, bones.dropFirst()) {
            shell.addPath(outline(from: start.point, to: end.point, root: start.width, tip: end.width))
        }
        ctx.saveGState()
        ctx.addPath(shell)
        ctx.clip()
        let rect = shell.boundingBoxOfPath.insetBy(dx: -1, dy: -1)
        ink.gradient(rect, leg.farSide ? [0x68564b, 0x4a3e38, 0x392e2e] : [0x857366, 0x6c594c, 0x4d3e39])
        ctx.saveGState()
        ctx.setAlpha(leg.farSide ? 0.45 : 0.64)
        SnowballAtlas.draw(leg.stifle == nil ? sprites.shoulder : sprites.thigh, in: rect, ink: ink)
        ctx.restoreGState()
        ctx.drawLinearGradient(limbShade, start: p(rect.minX, 0), end: p(rect.maxX, 0), options: [])
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: leg.ankle.x, y: leg.ankle.y)
        ctx.rotate(by: leg.hoofAngle)
        let hoofWidth = (leg.stifle == nil ? 1 : 0.90) * width
        ctx.scaleBy(x: hoofWidth, y: width)
        SnowballAtlas.draw(sprites.hoof, in: CGRect(x: -42, y: -43, width: 126, height: 117), ink: ink)
        ctx.restoreGState()
    }

    private static func outline(from a: CGPoint, to b: CGPoint, root: CGFloat, tip: CGFloat) -> CGPath {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        let shell = CGMutablePath()
        shell.move(to: p(-root, 0))
        shell.addQuadCurve(to: p(root, 0), control: p(0, -root * 1.4))
        shell.addCurve(to: p(tip, length), control1: p(root * 0.91, length * 0.35),
                       control2: p(tip * 0.83, length * 0.76))
        shell.addQuadCurve(to: p(-tip, length), control: p(0, length + tip * 1.32))
        shell.addCurve(to: p(-root, 0), control1: p(-tip * 0.97, length * 0.73),
                       control2: p(-root * 1.12, length * 0.43))
        shell.closeSubpath()
        var transform = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(dy, dx) - .pi / 2)
        return shell.copy(using: &transform) ?? shell
    }

    private static func drawFrost(_ age: CGFloat, ink: Ink) {
        for index in 0..<24 {
            let i = CGFloat(index)
            let time = age * (0.75 + i.truncatingRemainder(dividingBy: 5) * 0.10) + i * 0.618
            let life = time - Foundation.floor(time)
            let envelope = sin(life * .pi)
            let x = 78 - life * (96 + i.truncatingRemainder(dividingBy: 4) * 9)
            let y = 104 + sin(i * 13.1) * (4 + life * 17)
            let radius = (0.32 + 0.75 * (1 - life)) * (index.isMultiple(of: 4) ? 1.42 : 1)
            ink.circle(x, y, radius, index.isMultiple(of: 3) ? 0xffcf8b : 0xd1e6ff, alpha: envelope * 0.61)
        }
    }
}
