import CoreGraphics

struct CursorSweep {
    let start: CGPoint
    let end: CGPoint
    let direction: CGFloat
    let strength: CGFloat

    init?(from start: CGPoint, to end: CGPoint, delta: CGFloat) {
        let dx = end.x - start.x
        let distance = hypot(dx, end.y - start.y)
        guard (1.5...120).contains(distance) else { return nil }
        self.start = start
        self.end = end
        direction = dx < 0 ? -1 : 1
        strength = min(1, max(0.16, distance / max(delta, 0.01) / 850))
    }

    var xRange: ClosedRange<CGFloat> { (min(start.x, end.x) - 15)...(max(start.x, end.x) + 15) }

    func reaches(_ surface: SnowSurface) -> Bool {
        max(start.y, end.y) >= surface.rect.minY - surface.maximumDepth - 10
            && min(start.y, end.y) <= surface.rect.minY + surface.cornerRadius * 0.6 + 6
            && xRange.overlaps(surface.rect.minX...surface.rect.maxX)
    }

    func pressure(at point: CGPoint) -> CGFloat {
        let dx = (end.x - start.x) / 15
        let dy = (end.y - start.y) / 9
        let x = (point.x - start.x) / 15
        let y = (point.y - start.y) / 9
        let along = min(1, max(0, (x * dx + y * dy) / (dx * dx + dy * dy)))
        return strength * max(0, 1 - hypot(x - along * dx, y - along * dy))
    }
}

struct LooseSnow {
    var position: CGPoint
    var velocity: CGVector
    let mass: CGFloat
    var chunkRadius: CGFloat? = nil
    var spin: CGFloat = 0
    var angle: CGFloat = 0

    var radius: CGFloat { chunkRadius ?? min(3.5, 0.65 + sqrt(mass) * 0.85) }

    mutating func advance(_ delta: CGFloat, between bounds: ClosedRange<CGFloat>) {
        position.y += (velocity.dy + 290 * delta) * delta
        velocity.dy += 580 * delta
        position.x += velocity.dx * delta
        velocity.dx *= exp(-0.8 * delta)
        angle += spin * delta
        if !bounds.contains(position.x) {
            position.x = min(bounds.upperBound, max(bounds.lowerBound, position.x))
            velocity.dx *= -0.24
        }
    }
}
