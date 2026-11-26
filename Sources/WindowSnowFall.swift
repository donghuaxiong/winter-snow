import CoreGraphics

struct WindowSnowClump {
    private struct CornerSlide {
        let window: UInt32
        let left: Bool
        let radius: CGFloat
        let duration: CGFloat
        var elapsed: CGFloat = 0

        var direction: CGFloat { left ? -1 : 1 }
    }

    private(set) var center: CGPoint
    private(set) var angle: CGFloat
    let width: CGFloat
    let thickness: CGFloat
    let mass: CGFloat
    let shape: CGFloat
    var pendingWindow: UInt32?

    private var velocity: CGVector
    private let spin: CGFloat
    private var delay: CGFloat
    private var slide: CornerSlide?

    var overflowSource: SurfaceID? { slide.map { .window($0.window) } }
    var followsCorner: Bool { slide.map { $0.elapsed < $0.duration } ?? false }

    private init(center: CGPoint, width: CGFloat, thickness: CGFloat, mass: CGFloat,
                 velocity: CGVector, spin: CGFloat, delay: CGFloat, shape: CGFloat, pendingWindow: UInt32?) {
        self.center = center
        self.width = width
        self.thickness = thickness
        self.mass = mass
        self.velocity = velocity
        self.spin = spin
        self.delay = delay
        self.shape = shape
        self.pendingWindow = pendingWindow
        angle = 0
    }

    var contact: CGPoint {
        let half = width / 2
        let depth = thickness / 2
        let sine = sin(angle)
        let cosine = cos(angle)
        let reach = hypot(half * sine, depth * cosine)
        let offset = (half * half - depth * depth) * sine * cosine / reach
        return p(center.x + offset, center.y + reach)
    }

    static func detach(_ drift: SnowDrift, from surface: SnowSurface, horizontalSpeed: CGFloat,
                       reduced: Bool, pendingWindow: UInt32?, random: inout SnowRandom) -> [Self] {
        let origin = surface.rect.minX
        let spacing = SnowDrift.spacing
        var pieces: [Self] = []
        for span in surface.visible {
            let start = max(0, Int((span.lowerBound - origin) / spacing))
            let end = min(drift.heights.count - 1, Int((span.upperBound - origin) / spacing))
            guard start <= end else { continue }
            var index = start
            while index <= end {
                if drift.heights[index] < 0.18 {
                    index += 1
                    continue
                }
                let first = index
                let columns = Int(random.inRange(2, 6))
                let left = max(span.lowerBound, origin + CGFloat(first) * spacing)
                var crossSection: CGFloat = 0
                var maxDepth: CGFloat = 0
                while index <= end, index - first < columns, drift.heights[index] >= 0.18 {
                    let binLeft = origin + CGFloat(index) * spacing
                    let binRight = min(surface.rect.maxX, binLeft + spacing)
                    let sliver = max(0, min(span.upperBound, binRight) - max(span.lowerBound, binLeft))
                    crossSection += sliver * drift.heights[index]
                    maxDepth = max(maxDepth, drift.heights[index])
                    index += 1
                }
                let right = min(span.upperBound, origin + CGFloat(index) * spacing, surface.rect.maxX)
                let length = right - left
                guard crossSection > 0, length > 0 else { continue }
                let thickness = max(1.0, min(maxDepth, crossSection / length * 1.12))
                let x = (left + right) * 0.5
                let sideways = horizontalSpeed * random.inRange(0.48, 0.83) + random.inRange(-26, 26)
                pieces.append(Self(center: p(x, surface.rect.minY - thickness * 0.5),
                                   width: length, thickness: thickness, mass: crossSection / spacing,
                                   velocity: CGVector(dx: sideways, dy: random.inRange(3, 32)),
                                   spin: reduced ? 0 : random.inRange(-2.5, 2.5),
                                   delay: reduced ? 0 : random.inRange(0, 0.11),
                                   shape: random.inRange(0, 1), pendingWindow: pendingWindow))
            }
        }
        return pieces
    }

    static func spill(window: UInt32, edge: CGPoint, radius: CGFloat, left: Bool, mass: CGFloat,
                      reduced: Bool, random: inout SnowRandom) -> Self {
        let slide = CornerSlide(window: window, left: left, radius: radius, duration: reduced ? 0.16 : 0.31)
        let width = min(13, 6 + mass * 0.75)
        let thickness = min(5.2, max(2.5, mass * SnowDrift.spacing / width * 0.86))
        var clump = Self(center: p(edge.x - slide.direction * radius, edge.y - thickness * 0.48),
                         width: width, thickness: thickness, mass: mass,
                         velocity: CGVector(dx: slide.direction * random.inRange(14, 27), dy: 65),
                         spin: reduced ? 0 : slide.direction * random.inRange(1.2, 2.6),
                         delay: 0, shape: random.inRange(0, 1), pendingWindow: nil)
        clump.slide = slide
        return clump
    }

    mutating func advanceAlongCorner(_ delta: CGFloat, on surface: SnowSurface?, floor: CGRect, reduced: Bool) -> Bool {
        guard var slide, slide.elapsed < slide.duration else { return false }
        guard let edge = surface?.overflowCorner(left: slide.left, on: floor) else {
            slide.elapsed = slide.duration
            self.slide = slide
            return false
        }
        slide.elapsed = min(slide.duration, slide.elapsed + delta)
        self.slide = slide
        let progress = slide.elapsed / slide.duration
        let turn = (0.64 * progress + 0.36 * progress * progress) * .pi / 2
        let shell = slide.radius + thickness * 0.48
        center = p(edge.x + slide.direction * (shell * sin(turn) - slide.radius),
                   edge.y + slide.radius - shell * cos(turn))
        if !reduced { angle = slide.direction * turn }
        return true
    }

    mutating func advance(_ delta: CGFloat, within width: CGFloat) {
        let active = max(0, delta - delay)
        delay = max(0, delay - delta)
        guard active > 0 else { return }
        let gravity: CGFloat = 1_370
        center.y += (velocity.dy + gravity * active / 2) * active
        velocity.dy += gravity * active
        center.x += velocity.dx * active
        velocity.dx *= exp(-0.55 * active)
        angle += spin * active

        let margin = min(3, width / 2)
        let clamped = min(width - margin, max(margin, center.x))
        if center.x != clamped {
            center.x = clamped
            velocity.dx *= -0.27
        }
    }
}
