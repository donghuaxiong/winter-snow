import CoreGraphics

struct WindowSnowClump {
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
