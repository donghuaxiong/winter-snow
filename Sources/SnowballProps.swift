import AppKit

enum SnowballPropKind: String, Codable {
    case carrot, coal, eye, leftTwig, rightTwig, feltHat, woolHat, scarf

    var title: String {
        switch self {
        case .carrot: "胡萝卜鼻子"
        case .coal: "煤块"
        case .eye: "煤球眼睛"
        case .leftTwig: "左树枝手臂"
        case .rightTwig: "右树枝手臂"
        case .feltHat: "黑毡礼帽"
        case .woolHat: "针织毛球帽"
        case .scarf: "红色针织围巾"
        }
    }

    var exclusive: Bool { self != .coal && self != .eye }
    var slot: Self { self == .woolHat ? .feltHat : self }

    fileprivate var sprite: Int {
        switch self {
        case .carrot: 0
        case .coal, .eye: 1
        case .leftTwig, .rightTwig: 2
        case .feltHat: 3
        case .scarf: 4
        case .woolHat: 5
        }
    }

    fileprivate var anchorInImage: CGPoint {
        switch self {
        case .carrot: p(0.10, 0.51)
        case .coal, .eye: p(0.49, 0.53)
        case .leftTwig, .rightTwig: p(0.10, 0.91)
        case .feltHat: p(0.50, 0.85)
        case .woolHat: p(0.50, 0.94)
        case .scarf: p(0.44, 0.26)
        }
    }

    fileprivate var widthInRadii: CGFloat {
        switch self {
        case .carrot: 1.00
        case .coal: 0.17
        case .eye: 0.245
        case .leftTwig, .rightTwig: 1.26
        case .feltHat: 1.63
        case .woolHat: 1.60
        case .scarf: 1.83
        }
    }

    fileprivate var depth: Int {
        switch self {
        case .leftTwig, .rightTwig: 0
        case .scarf: 1
        case .feltHat, .woolHat: 3
        default: 2
        }
    }

    fileprivate func constrain(_ point: CGPoint) -> CGPoint {
        switch self {
        case .feltHat, .woolHat:
            return p(min(0.58, max(-0.58, point.x)), min(-0.48, max(-0.90, point.y)))
        case .scarf:
            return p(min(0.24, max(-0.24, point.x)), min(0.89, max(0.22, point.y)))
        case .leftTwig, .rightTwig:
            let direction: CGFloat = self == .leftTwig ? -1 : 1
            return p(direction * min(0.90, max(0.41, point.x * direction)), min(0.42, max(-0.62, point.y)))
        case .carrot, .coal, .eye:
            let distance = hypot(point.x, point.y)
            let scale = distance > 0.77 ? 0.77 / distance : 1
            return p(point.x * scale, point.y * scale)
        }
    }
}

enum SnowballPropChoice: CaseIterable {
    case eyes, carrot, coal, leftTwig, rightTwig, feltHat, woolHat, scarf

    var kind: SnowballPropKind {
        switch self {
        case .eyes: .eye
        case .carrot: .carrot
        case .coal: .coal
        case .leftTwig: .leftTwig
        case .rightTwig: .rightTwig
        case .feltHat: .feltHat
        case .woolHat: .woolHat
        case .scarf: .scarf
        }
    }

    func mount(on ball: RolledSnowball, near point: CGPoint) -> [SnowballProp] {
        let x = (point.x - ball.center.x) / ball.radius
        let y = (point.y - ball.center.y) / ball.radius
        let orientation = -ball.rotation
        if self == .eyes {
            let center = min(0.28, max(-0.28, x * 0.54))
            let row = min(-0.16, max(-0.59, y))
            return [
                SnowballProp(kind: .eye, anchor: p(center - 0.29, row), orientation: orientation, tilt: -0.30, scale: 1.05),
                SnowballProp(kind: .eye, anchor: p(center + 0.30, row + 0.025), orientation: orientation, tilt: 0.31, scale: 0.89)
            ]
        }
        let anchor: CGPoint
        let angle: CGFloat
        switch kind {
        case .eye, .coal:
            anchor = p(x, y)
            angle = x * 0.8 + y
        case .carrot:
            anchor = p(x * 0.61 - 0.14, y * 0.68 + 0.05)
            angle = 0.10
        case .leftTwig, .rightTwig:
            let direction: CGFloat = kind == .leftTwig ? -1 : 1
            anchor = p(direction * 0.78, y * 0.48)
            angle = direction * (kind == .leftTwig ? 0.24 : 0.15)
        case .feltHat, .woolHat:
            anchor = p(x * 0.69, -0.78)
            angle = x * 0.31 + (kind == .feltHat ? -0.13 : 0.09)
        case .scarf:
            anchor = p(x * 0.48, 0.66)
            angle = -0.07
        }
        return [SnowballProp(kind: kind, anchor: kind.constrain(anchor), orientation: orientation, tilt: angle, scale: 1)]
    }
}

struct SnowballProp: Identifiable, Codable, Equatable {
    var id = UUID()
    let kind: SnowballPropKind
    private(set) var anchor: CGPoint
    // This is the material orientation at the time the piece was pushed into the snow.
    let orientation: CGFloat
    let tilt: CGFloat
    let scale: CGFloat

    func worldAnchor(on ball: RolledSnowball) -> CGPoint {
        let turn = CGAffineTransform(rotationAngle: ball.rotation + orientation)
        let offset = anchor.applying(turn)
        return p(ball.center.x + offset.x * ball.radius, ball.center.y + offset.y * ball.radius)
    }

    mutating func move(to point: CGPoint, on ball: RolledSnowball) {
        let unturn = CGAffineTransform(rotationAngle: -(ball.rotation + orientation))
        let relative = p((point.x - ball.center.x) / ball.radius, (point.y - ball.center.y) / ball.radius)
        anchor = kind.constrain(relative.applying(unturn))
    }
}

enum SnowballPropArt {
    private struct Sprite {
        let image: CGImage
        let preview: NSImage
        let mask: [UInt8]
        static let sampleSide = 40

        init(_ image: CGImage) {
            self.image = image
            let fit = min(18 / CGFloat(image.width), 18 / CGFloat(image.height))
            preview = NSImage(size: CGSize(width: 18, height: 18), flipped: false) { bounds in
                let width = fit * CGFloat(image.width), height = fit * CGFloat(image.height)
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height))
                return true
            }
            let side = Self.sampleSide
            var rgba = [UInt8](repeating: 0, count: side * side * 4)
            rgba.withUnsafeMutableBytes { pixels in
                guard let context = CGContext(data: pixels.baseAddress, width: side, height: side,
                                              bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                                | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            mask = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        }

        func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
            guard rect.contains(point) else { return false }
            let side = Self.sampleSide
            let x = min(side - 1, max(0, Int((point.x - rect.minX) / rect.width * CGFloat(side))))
            let y = min(side - 1, max(0, Int((point.y - rect.minY) / rect.height * CGFloat(side))))
            return mask[y * side + x] > 68
        }
    }

    private struct Pose {
        let transform: CGAffineTransform
        let frame: CGRect
        var bounds: CGRect { frame.applying(transform).insetBy(dx: -3, dy: -3) }
    }

    private static let sprites: [Sprite?] = {
        let crops = [
            CGRect(x: 34, y: 170, width: 449, height: 161),
            CGRect(x: 615, y: 140, width: 280, height: 246),
            CGRect(x: 1083, y: 47, width: 415, height: 388),
            CGRect(x: 25, y: 574, width: 464, height: 378),
            CGRect(x: 549, y: 550, width: 449, height: 444),
            CGRect(x: 1085, y: 553, width: 404, height: 394)
        ]
        return SnowballAtlas.crops(crops, from: "RolledSnowballProps").map { $0.map(Sprite.init) }
    }()

    static var isAvailable: Bool { sprites.allSatisfy { $0 != nil } }

    static func thumbnail(for kind: SnowballPropKind) -> NSImage? { sprites[kind.sprite]?.preview }

    private static func pose(for prop: SnowballProp, on ball: RolledSnowball, sprite: Sprite) -> Pose {
        let anchor = prop.worldAnchor(on: ball)
        let width = max(2, ball.radius * prop.kind.widthInRadii * prop.scale)
        let height = width * CGFloat(sprite.image.height) / CGFloat(sprite.image.width)
        let pivot = prop.kind.anchorInImage
        let frame = CGRect(x: -pivot.x * width, y: -pivot.y * height, width: width, height: height)
        let transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .rotated(by: ball.rotation + prop.orientation + prop.tilt)
            .scaledBy(x: prop.kind == .leftTwig ? -1 : 1, y: 1)
        return Pose(transform: transform, frame: frame)
    }

    private static func ordered(_ props: [SnowballProp]) -> [SnowballProp] {
        props.enumerated().sorted {
            if $0.element.kind.depth == $1.element.kind.depth { return $0.offset < $1.offset }
            return $0.element.kind.depth < $1.element.kind.depth
        }.map(\.element)
    }

    static func bounds(of ball: RolledSnowball, including body: CGRect) -> CGRect {
        ball.props.reduce(body) { bounds, prop in
            guard let sprite = sprites[prop.kind.sprite] else { return bounds }
            return bounds.union(pose(for: prop, on: ball, sprite: sprite).bounds)
        }
    }

    static func hit(at point: CGPoint, on ball: RolledSnowball) -> (id: UUID, frame: CGRect)? {
        for prop in ordered(ball.props).reversed() {
            guard let sprite = sprites[prop.kind.sprite] else { continue }
            let pose = pose(for: prop, on: ball, sprite: sprite)
            if sprite.contains(point.applying(pose.transform.inverted()), in: pose.frame) {
                let rect = CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)
                return (prop.id, rect)
            }
        }
        return nil
    }

    static func draw(on ball: RolledSnowball, ink: Ink) {
        let ctx = ink.ctx
        for prop in ordered(ball.props) {
            guard let sprite = sprites[prop.kind.sprite] else { continue }
            let pose = pose(for: prop, on: ball, sprite: sprite)
            if prop.kind.depth == 0 || prop.kind.depth == 2 {
                let anchor = prop.worldAnchor(on: ball)
                let reach = max(1.1, ball.radius * (prop.kind == .carrot ? 0.19 : prop.kind.widthInRadii * 0.54))
                ink.glow(anchor.x + reach * 0.29, anchor.y + reach * 0.37, reach, 0x354553, alpha: 0.41)
            }
            ctx.saveGState()
            ctx.concatenate(pose.transform)
            SnowballAtlas.draw(sprite.image, in: pose.frame, ink: ink)
            ctx.restoreGState()
        }
    }
}
