import AppKit

struct SleighFlight {
    let direction: CGFloat
    var age: CGFloat = 0
    var dropped = 0
    static let duration: CGFloat = 9
    static let size = CGSize(width: 416, height: 125)

    func frame(in display: CGSize) -> CGRect {
        let t = age / Self.duration
        let x = -Self.size.width + (display.width + Self.size.width * 2) * t
        let y = min(150, display.height * 0.17) + 11 * sin(t * .pi * 2.4)
        return CGRect(origin: p(direction > 0 ? x : display.width - x - Self.size.width, y), size: Self.size)
    }

    func paintBounds(in display: CGSize) -> CGRect {
        frame(in: display).insetBy(dx: -54, dy: -11)
    }

    func giftAnchor(in display: CGSize) -> CGPoint {
        let frame = frame(in: display)
        return p(frame.minX + (direction > 0 ? 50 : frame.width - 50), frame.minY + 76)
    }
}

struct SleighGift: Identifiable {
    let id = UUID()
    let color: UInt32
    var center: CGPoint
    var velocity: CGVector
    var age: CGFloat = 0
    var openedAt: CGFloat?
    var rest: SurfaceID?
    var restFraction: CGFloat = 0

    var frame: CGRect { CGRect(around: center, radius: 15) }
    var bounds: CGRect { CGRect(around: center, radius: openedAt == nil ? 22 : 42) }
}

struct FestiveTraffic {
    private(set) var flight: SleighFlight?
    private(set) var gifts: [SleighGift] = []
    private var nextDirection: CGFloat = 1
    private var untilNext: CGFloat = 36

    var active: Bool { flight != nil || !gifts.isEmpty }

    mutating func launch() {
        guard flight == nil else { return }
        flight = SleighFlight(direction: nextDirection)
        nextDirection *= -1
        untilNext = 66
    }

    mutating func open(_ id: UUID) {
        guard let index = gifts.firstIndex(where: { $0.id == id }), gifts[index].openedAt == nil else { return }
        gifts[index].openedAt = gifts[index].age
    }

    mutating func step(_ delta: CGFloat, size: CGSize, snow: DisplayScene, automatic: Bool, reduced: Bool) {
        if let current = flight {
            var pass = current
            pass.age += delta
            let releasePositions: [CGFloat] = [0.23, 0.50, 0.75]
            let anchor = pass.giftAnchor(in: size)
            let forward = pass.direction > 0 ? anchor.x : size.width - anchor.x
            while pass.dropped < releasePositions.count, forward >= size.width * releasePositions[pass.dropped] {
                if (20...(max(20, size.width - 20))).contains(anchor.x), gifts.count < 12 {
                    let colors: [UInt32] = [0xbf3f53, 0x27847b, 0x735cb0]
                    gifts.append(SleighGift(color: colors[pass.dropped], center: anchor,
                                           velocity: CGVector(dx: pass.direction * 35, dy: 20)))
                }
                pass.dropped += 1
            }
            flight = pass.age < SleighFlight.duration ? pass : nil
        } else if automatic && !reduced {
            untilNext -= delta
            if untilNext <= 0 { launch() }
        }
        for index in gifts.indices {
            var gift = gifts[index]
            gift.age += delta
            if let rest = gift.rest {
                if let surface = snow.surfaces.first(where: { $0.id == rest }) {
                    let x = surface.rect.minX + gift.restFraction * surface.rect.width
                    if surface.visible.contains(where: { $0.contains(x) }) {
                        gift.center = p(x, surface.settlingY(at: x, depth: surface.snowDepth(snow.drift(on: rest), at: x)) - 11)
                        gifts[index] = gift
                        continue
                    }
                }
                gift.rest = nil
            }
            let x = max(15, min(size.width - 15, gift.center.x + gift.velocity.dx * delta))
            let y = gift.center.y + (gift.velocity.dy + 280 * delta) * delta
            gift.velocity.dy += 560 * delta
            gift.velocity.dx *= exp(-0.85 * delta)
            if let hit = snow.landing(at: x, from: gift.center.y + 10, to: y + 11) {
                gift.center = p(x, hit.y - 11)
                gift.rest = hit.surface.id
                gift.restFraction = (x - hit.surface.rect.minX) / hit.surface.rect.width
                gift.velocity = .zero
            } else {
                gift.center = p(x, min(size.height - 12, y))
            }
            gifts[index] = gift
        }
        gifts.removeAll { gift in
            if let opened = gift.openedAt { return gift.age - opened > 1.7 }
            return gift.age > 48
        }
    }
}

enum FestiveTrafficArt {
    static func draw(_ pass: SleighFlight, in size: CGSize, reduced: Bool, ink: Ink) {
        SleighFlightArt.draw(pass, in: size, reduced: reduced, ink: ink)
    }

    static func draw(_ gift: SleighGift, reduced: Bool, ink: Ink) {
        let x = gift.center.x, y = gift.center.y
        let opening = gift.openedAt.map { gift.age - $0 }
        let lift = opening.map { min(12, $0 * 45) } ?? 0
        let fade = opening.map { max(0, 1 - $0 / 1.7) } ?? 1
        let ctx = ink.ctx
        ctx.saveGState()
        ctx.setAlpha(fade)
        ink.oval(CGRect(x: x - 15, y: y + 9, width: 30, height: 5), 0x102337, alpha: 0.4)
        ink.rounded(CGRect(x: x - 12, y: y - 6, width: 24, height: 18), 3, gift.color)
        ink.rounded(CGRect(x: x - 14, y: y - 9 - lift, width: 28, height: 6), 2.3, gift.color)
        ink.fill(CGRect(x: x - 2.3, y: y - 6, width: 4.6, height: 18), 0xfadd9b)
        ink.line([p(x, y - 8 - lift), p(x - 7, y - 15 - lift), p(x - 8, y - 10 - lift), p(x, y - 8 - lift),
                  p(x + 7, y - 15 - lift), p(x + 8, y - 11 - lift), p(x, y - 8 - lift)], 0xffde98, width: 1.5)
        if let opening {
            let radius = min(32, opening * 53)
            for index in 0..<(reduced ? 4 : 9) {
                let angle = CGFloat(index) * 2.4
                ink.star(x + cos(angle) * radius, y - 10 + sin(angle) * radius, 2.7, 0xffe6a7, points: 4)
            }
        }
        ctx.restoreGState()
    }
}

struct TreeBranchSnow {
    private(set) var loads: [CGFloat] = [0, 0, 0, 0]
    private var shakeAge: CGFloat = 2
    private var side: CGFloat = 1

    var animating: Bool { shakeAge < 0.85 }
    var rotation: CGFloat { animating ? side * 2.1 * sin(shakeAge * 30) * exp(-shakeAge * 6) : 0 }

    mutating func step(_ delta: CGFloat, density: CGFloat) {
        shakeAge += delta
        for index in loads.indices {
            loads[index] = min(1, loads[index] + delta * density * (0.067 + CGFloat(index) * 0.023))
        }
    }

    mutating func shake(at trigger: CGPoint, in rect: CGRect) -> [(CGPoint, CGFloat)] {
        guard shakeAge > 0.93, loads.max() ?? 0 > 0.20 else { return [] }
        shakeAge = 0
        side = trigger.x < rect.midX ? -1 : 1
        return loads.indices.compactMap { index in
            let amount = loads[index] * (0.53 + CGFloat(index) * 0.045)
            guard amount > 0.14 else { return nil }
            loads[index] -= amount
            let branch = Self.point(index, side: side, in: rect)
            return (branch, amount)
        }
    }

    static func point(_ index: Int, side: CGFloat, in rect: CGRect) -> CGPoint {
        p(rect.midX + side * rect.width * (0.11 + CGFloat(index) * 0.071),
          rect.minY + rect.height * (0.29 + CGFloat(index) * 0.16))
    }

    func paint(in rect: CGRect, ink: Ink) {
        for (index, load) in loads.enumerated() where load > 0.04 {
            for sign in [-1.0, 1.0] {
                let tip = Self.point(index, side: sign, in: rect)
                let inner = p(tip.x - sign * rect.width * (0.059 + CGFloat(index) * 0.012), tip.y - rect.height * 0.017)
                let middle = p((tip.x + inner.x) / 2, (tip.y + inner.y) / 2 - 1.45)
                let depth = load * (2.1 + CGFloat(index) * 0.49) * rect.width / 154
                let path = CGMutablePath()
                path.move(to: inner)
                path.addQuadCurve(to: tip, control: p(middle.x, middle.y - depth))
                path.addQuadCurve(to: inner, control: p(middle.x, middle.y + depth * 0.68))
                path.closeSubpath()
                ink.ctx.setFillColor(NSColor(rgb: 0xe9f5ff, alpha: min(0.98, load + 0.23)).cgColor)
                ink.ctx.addPath(path)
                ink.ctx.fillPath()
            }
        }
    }
}
