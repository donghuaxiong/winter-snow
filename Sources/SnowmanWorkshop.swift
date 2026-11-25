import CoreGraphics

enum SnowmanGround {
    static func followsSupport(_ ornament: Ornament, usableHeight: CGFloat) -> Bool {
        if let follows = ornament.snowmanFollowsGround { return follows }
        // Old saves only recorded coordinates. Recognize the original default and workshop positions.
        let defaultPosition = (0..<5).contains { index in
            let offset = Double(index) * 0.052
            return abs(ornament.x - (0.77 - offset)) < 0.001 && abs(ornament.y - (0.29 + offset)) < 0.001
        }
        let oldGround = 13 + ornament.scale * (SnowmanArt.baseline - OrnamentKind.snowman.size.height / 2)
        return defaultPosition || abs(ornament.y * usableHeight - oldGround) < 6
    }

    static func foot(at x: CGFloat, screen: CGRect, dock: CGRect?) -> CGFloat {
        if let dock, dock.width > 16, (dock.minX + 8...dock.maxX - 8).contains(x) { return dock.maxY + 1 }
        return screen.minY + 1
    }

    static func frame(center: CGPoint, size: CGSize, inside display: CGRect) -> CGRect {
        let x = min(display.maxX - size.width / 2, max(display.minX + size.width / 2, center.x))
        let belowCenter = size.height * (SnowmanArt.baseline / OrnamentKind.snowman.size.height - 0.5)
        let y = min(display.maxY - size.height / 2, max(display.minY + belowCenter, center.y))
        return CGRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
    }
}

struct SnowballPlatform {
    enum ID: Hashable {
        case window(UInt32), dock(UInt32), ground(UInt32)
    }

    let id: ID
    let frame: CGRect
    let span: ClosedRange<CGFloat>
    let anchor: WindowAnchor?

    var top: CGFloat { frame.maxY }

    func inset(for radius: CGFloat) -> ClosedRange<CGFloat> {
        let margin = min(radius * 0.55, (span.upperBound - span.lowerBound) / 2)
        return (span.lowerBound + margin)...(span.upperBound - margin)
    }

    func fraction(at x: CGFloat) -> CGFloat {
        min(1, max(0, (x - frame.minX) / max(1, frame.width)))
    }
}

struct WorkshopBall {
    enum Rest: Equatable {
        case platform(SnowballPlatform.ID, fraction: CGFloat)
        case ball(Int)
    }

    let id: Int
    let radius: CGFloat
    var center: CGPoint
    var speed: CGFloat = 0
    var horizontalSpeed: CGFloat = 0
    var spin: CGFloat = 0
    var rest: Rest?
}

struct SnowmanWorkshop {
    private(set) var balls: [WorkshopBall]
    private(set) var held: Int?
    private var grabOffset = CGPoint.zero
    private var age: CGFloat = 0
    private var tumbling = false

    init(platform: SnowballPlatform, near x: CGFloat) {
        let span = platform.span
        let middle = min(span.upperBound - 59, max(span.lowerBound + 59, x))
        let widths: [CGFloat] = [-42, 2, 38]
        balls = SnowmanArt.radii.enumerated().map { id, value in
            let centerX = middle + widths[id]
            let radius = value * SnowmanArt.workshopScale
            return WorkshopBall(id: id, radius: radius, center: p(centerX, platform.top + radius),
                                rest: .platform(platform.id, fraction: platform.fraction(at: centerX)))
        }
    }

    init(knocking snowman: Ornament, from frame: CGRect, direction: CGFloat, reduced: Bool) {
        tumbling = true
        age = 1
        let velocities: [CGFloat] = [-103, 25, 158]
        let local = CGRect(origin: .zero, size: frame.size)
        balls = SnowmanArt.parts(for: snowman, in: local).enumerated().map { id, part in
            let center = p(frame.minX + part.center.x, frame.maxY - part.center.y)
            let impulse = direction * velocities[part.tone] * (reduced ? 0.58 : 1)
            return WorkshopBall(id: id, radius: part.radius, center: center,
                                speed: id == 0 ? 48 : 84, horizontalSpeed: impulse, spin: part.angle)
        }
    }

    func tone(for ball: WorkshopBall) -> Int { ball.id == balls.count - 1 ? 2 : ball.id }

    mutating func grab(_ id: Int, at point: CGPoint) {
        guard balls.indices.contains(id), revealed(id), held == nil else { return }
        held = id
        grabOffset = p(balls[id].center.x - point.x, balls[id].center.y - point.y)
        balls[id].rest = nil
        balls[id].speed = 0
        balls[id].horizontalSpeed = 0
    }

    func revealed(_ id: Int) -> Bool { age >= CGFloat(id) * 0.14 }

    mutating func drag(to point: CGPoint, platforms: [SnowballPlatform]) {
        guard let held else { return }
        let previous = balls[held].center
        let next = p(point.x + grabOffset.x, point.y + grabOffset.y)
        balls[held].center = next
        let dx = next.x - previous.x
        if abs(dx) > 0.25 {
            let direction: CGFloat = dx > 0 ? 1 : -1
            for index in balls.indices where index != held && revealed(index) {
                guard case let .platform(key, _) = balls[index].rest else { continue }
                let center = balls[index].center
                let reach = (balls[held].radius + balls[index].radius) * 0.92
                let dy = abs(next.y - center.y)
                guard dy < reach * 0.62, (center.x - previous.x) * direction > 0 else { continue }
                let contact = sqrt(reach * reach - dy * dy)
                let moved = next.x + direction * contact
                guard (moved - center.x) * direction > 0 else { continue }
                balls[index].center.x = moved
                if let platform = platforms.first(where: { $0.id == key && $0.inset(for: balls[index].radius).contains(moved) }) {
                    rest(index, on: platform)
                } else {
                    balls[index].rest = nil
                    balls[index].horizontalSpeed = direction * min(103, max(20, abs(dx) * 5))
                }
            }
        }
        for index in balls.indices { followParent(index) }
    }

    mutating func release(on platforms: [SnowballPlatform]) {
        guard let id = held else { return }
        held = nil
        if let y = stackHeight(for: id),
           (y - 12...y + 20).contains(balls[id].center.y) {
            stack(id, at: y)
        } else if let platform = edge(at: balls[id].center.x, radius: balls[id].radius,
                                     from: balls[id].center.y - balls[id].radius + 11,
                                     to: balls[id].center.y - balls[id].radius - 10, in: platforms) {
            rest(id, on: platform)
        }
    }

    mutating func advance(_ delta: CGFloat, platforms: [SnowballPlatform]) {
        age += delta
        for id in balls.indices where id != held {
            switch balls[id].rest {
            case .ball:
                followParent(id)
                continue
            case let .platform(key, fraction):
                if let platform = platforms.first(where: { $0.id == key }) {
                    balls[id].center = p(platform.frame.minX + fraction * platform.frame.width, platform.top + balls[id].radius)
                    guard tumbling, abs(balls[id].horizontalSpeed) > 3 else { continue }
                    let next = balls[id].center.x + balls[id].horizontalSpeed * delta
                    if platform.inset(for: balls[id].radius).contains(next) {
                        balls[id].spin += (next - balls[id].center.x) / balls[id].radius
                        balls[id].center.x = next
                        balls[id].horizontalSpeed *= exp(-delta * 3.6)
                        balls[id].rest = .platform(key, fraction: platform.fraction(at: next))
                        continue
                    }
                }
                balls[id].rest = nil
            case nil:
                break
            }

            let previous = balls[id].center.y
            let radius = balls[id].radius
            let horizontal = delta * balls[id].horizontalSpeed
            balls[id].center.x += horizontal
            if tumbling { balls[id].spin += horizontal / radius }
            balls[id].horizontalSpeed *= exp(-delta * 1.8)
            let x = balls[id].center.x
            balls[id].speed -= 880 * delta
            balls[id].center.y += balls[id].speed * delta
            let next = balls[id].center.y
            let shelf = edge(at: x, radius: radius, from: previous - radius, to: next - radius, in: platforms)
            if !tumbling, let tower = stackHeight(for: id), next <= tower, tower <= previous,
               tower >= (shelf?.top ?? -.greatestFiniteMagnitude) + radius {
                stack(id, at: tower)
            } else if let shelf {
                rest(id, on: shelf, rolling: tumbling)
            } else if let fallback = nearestGround(to: balls[id].center, in: platforms), next < fallback.top - 20 {
                let allowed = fallback.inset(for: radius)
                balls[id].center.x = min(allowed.upperBound, max(allowed.lowerBound, x))
                rest(id, on: fallback)
            }
        }
    }

    mutating func assemble(on platforms: [SnowballPlatform]) {
        guard held == nil else { return }
        if balls[0].rest == nil {
            guard let ground = nearestGround(to: balls[0].center, in: platforms) else { return }
            let allowed = ground.inset(for: balls[0].radius)
            balls[0].center.x = min(allowed.upperBound, max(allowed.lowerBound, balls[0].center.x))
            rest(0, on: ground)
        }
        for id in 1..<balls.count {
            let bottom = balls[id - 1]
            stack(id, at: bottom.center.y + SnowmanArt.gap(bottom.radius, balls[id].radius))
        }
    }

    mutating func rebuild(at id: Int, on platforms: [SnowballPlatform]) {
        guard balls.indices.contains(id) else { return }
        let selected = balls[id]
        let support = platforms.filter {
            $0.top <= selected.center.y && $0.inset(for: selected.radius).contains(selected.center.x)
        }.max { $0.top < $1.top }
        guard let platform = support ?? nearestGround(to: selected.center, in: platforms) else { return }
        let span = platform.inset(for: balls[0].radius)
        balls[0].center.x = min(span.upperBound, max(span.lowerBound, selected.center.x))
        rest(0, on: platform)
        assemble(on: platforms)
    }

    func completedPlatform(in platforms: [SnowballPlatform]) -> SnowballPlatform? {
        guard held == nil, case let .platform(key, _) = balls[0].rest,
              balls.dropFirst().allSatisfy({ $0.rest == .ball($0.id - 1) }) else { return nil }
        return platforms.first { $0.id == key }
    }

    private func stackHeight(for id: Int) -> CGFloat? {
        guard id > 0 else { return nil }
        let parent = balls[id - 1]
        guard parent.rest != nil, abs(balls[id].center.x - parent.center.x) <= parent.radius * 0.93 else { return nil }
        return parent.center.y + SnowmanArt.gap(parent.radius, balls[id].radius)
    }

    private mutating func stack(_ id: Int, at y: CGFloat) {
        balls[id].rest = .ball(id - 1)
        balls[id].speed = 0
        balls[id].horizontalSpeed = 0
        balls[id].center = p(balls[id - 1].center.x, y)
    }

    private mutating func followParent(_ id: Int) {
        guard case let .ball(parentID) = balls[id].rest else { return }
        let parent = balls[parentID]
        balls[id].center = p(parent.center.x, parent.center.y + SnowmanArt.gap(parent.radius, balls[id].radius))
    }

    private mutating func rest(_ id: Int, on platform: SnowballPlatform, rolling: Bool = false) {
        balls[id].speed = 0
        balls[id].horizontalSpeed *= rolling ? 0.76 : 0
        balls[id].center.y = platform.top + balls[id].radius
        balls[id].rest = .platform(platform.id, fraction: platform.fraction(at: balls[id].center.x))
    }

    private func edge(at x: CGFloat, radius: CGFloat, from high: CGFloat, to low: CGFloat,
                      in platforms: [SnowballPlatform]) -> SnowballPlatform? {
        platforms.filter { low <= $0.top && $0.top <= high && $0.inset(for: radius).contains(x) }
            .max { $0.top < $1.top }
    }

    private func nearestGround(to point: CGPoint, in platforms: [SnowballPlatform]) -> SnowballPlatform? {
        platforms.filter {
            if case .ground = $0.id { return true }
            return false
        }.min {
            hypot($0.frame.midX - point.x, $0.top - point.y) < hypot($1.frame.midX - point.x, $1.top - point.y)
        }
    }
}

struct FallingSnowman {
    var ornament: Ornament
    var rect: CGRect
    var speed: CGFloat = 0
    var sway: CGFloat

    /// Returns false once the snowman has settled or gone off screen.
    mutating func advance(_ delta: CGFloat, scene: inout DisplayScene, limit: CGFloat,
                          accumulate: Bool, reduced: Bool) -> Bool {
        let offset = rect.height * SnowmanArt.baseline / OrnamentKind.snowman.size.height
        let oldFoot = rect.minY + offset
        speed += delta * 975
        rect.origin.y += speed * delta
        rect.origin.x += sway * delta
        if !reduced { ornament.rotation += sway * delta * 1.65 }
        if let impact = scene.landing(at: rect.midX, from: oldFoot - 0.6, to: rect.minY + offset) {
            scene.shatterSnowman(at: p(rect.midX, impact.y), on: impact.surface,
                                 scale: ornament.scale, accumulate: accumulate)
            return false
        }
        return rect.minY < limit + 36
    }
}
