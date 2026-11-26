import CoreGraphics
import Foundation

struct RolledSnowball: Identifiable {
    enum Rest: Equatable {
        case surface(SurfaceID, fraction: CGFloat)
        case ball(UUID, offset: CGFloat)

        var parent: UUID? {
            if case let .ball(id, _) = self { return id }
            return nil
        }
    }

    struct LedgeTravel {
        let originY: CGFloat
        let excluding: SurfaceID?
    }

    static let maximumRadius: CGFloat = 72
    static let maximumMass = pow(maximumRadius - 4, 2) / 9.1

    let id = UUID()
    var center: CGPoint
    var mass: CGFloat
    var velocity = CGVector.zero
    var rotation: CGFloat = 0
    var spin: CGFloat = 0
    var compression: CGFloat = 0
    var rest: Rest?
    var ledgeTravel: LedgeTravel?
    var freeStack = false
    var props: [SnowballProp] = []
    var pitchedDown = false

    var radius: CGFloat { min(Self.maximumRadius, 4 + sqrt(max(0, mass) * 9.1)) }

    func grabFrame(at point: CGPoint) -> CGRect? {
        guard mass > 0, hypot(point.x - center.x, point.y - center.y) < radius else { return nil }
        let top = max(center.y - radius, point.y - 2)
        let bottom = min(center.y + radius, point.y + 2)
        let reach = sqrt(max(0, radius * radius - pow(max(abs(top - center.y), abs(bottom - center.y)), 2)))
        let left = min(point.x, center.x - reach)
        return CGRect(x: left, y: top, width: max(1, max(point.x, center.x + reach) - left), height: bottom - top)
    }
}

struct RolledSnow {
    private struct Grip {
        let offset: CGVector
        let radius: CGFloat

        func center(under point: CGPoint, radius newRadius: CGFloat) -> CGPoint {
            p(point.x + offset.dx, point.y + offset.dy - (newRadius - radius))
        }
    }

    private struct Sample {
        let point: CGPoint
        let time: Double
    }

    private(set) var balls: [RolledSnowball] = []
    private(set) var held: UUID?
    private(set) var pointer = CGPoint.zero
    private(set) var plowed: [PlowedSnowball] = []
    private var grip: Grip?
    private var samples: [Sample] = []

    var isEmpty: Bool { balls.isEmpty && plowed.isEmpty }

    var animating: Bool {
        held != nil || !plowed.isEmpty || balls.contains {
            $0.rest == nil || abs($0.velocity.dx) > 0.3 || $0.compression > 0.02
        }
    }

    var paintedBalls: [RolledSnowball] {
        balls.enumerated().sorted {
            if $0.element.center.y == $1.element.center.y { return $0.offset < $1.offset }
            return $0.element.center.y > $1.element.center.y
        }.map(\.element)
    }

    func ball(_ id: UUID) -> RolledSnowball? { balls.first { $0.id == id } }

    mutating func take(at point: CGPoint, time: Double, snow: inout DisplayScene, preferred: UUID? = nil) {
        let target = preferred ?? paintedBalls.last(where: { $0.grabFrame(at: point) != nil })?.id
        if let index = balls.firstIndex(where: { $0.id == target }) {
            let ball = balls[index]
            held = ball.id
            grip = Grip(offset: ball.center - point, radius: ball.radius)
            if ball.rest?.parent != nil { balls[index].rest = nil }
            balls[index].ledgeTravel = nil
            balls[index].velocity = .zero
            balls[index].spin = 0
            balls[index].pitchedDown = false
        } else {
            guard balls.count < 32 else { return }
            grip = nil
            let mass = snow.harvestSnow(from: point, to: point)
            guard mass > 0 else { return }
            let ball = RolledSnowball(center: point, mass: mass)
            held = ball.id
            balls.append(ball)
            if let support = snow.rollingSupport(near: point) {
                placeOnSurface(balls.count - 1, at: point.x, y: support.y, on: support.surface)
            } else {
                balls[balls.count - 1].center.y -= ball.radius
            }
        }
        pointer = point
        samples = [Sample(point: point, time: time)]
    }

    mutating func roll(to point: CGPoint, time: Double, snow: inout DisplayScene,
                       within size: CGSize? = nil, reduced: Bool = false) {
        guard let index = balls.firstIndex(where: { $0.id == held }) else { return }
        let slice = point - pointer
        guard hypot(slice.dx, slice.dy) > 0.25 else { return }

        let ball = balls[index]
        let press = grip ?? Grip(offset: CGVector(dx: 0, dy: -ball.radius), radius: ball.radius)
        let hand = press.center(under: point, radius: ball.radius)
        let foot = p(horizontalPosition(hand.x, radius: ball.radius, size: size), hand.y + ball.radius)
        let previousHand = press.center(under: pointer, radius: ball.radius)
        let previousFoot = p(ball.center.x, previousHand.y + ball.radius)
        let exit = pushedOffLedge(ball, from: previousFoot, to: foot, snow: snow)
        let limit = RolledSnowball.maximumMass - ball.mass
        if limit > 0, abs(slice.dx) > 0.25 {
            balls[index].mass += snow.harvestSnow(from: previousFoot, to: exit?.point ?? foot,
                                                 radius: ball.radius, limit: limit)
        }
        trackPointer(point, at: time)

        if let exit {
            let speed = max(24, exit.direction * throwVelocity(at: time).dx * 0.86)
            leaveLedge(index, at: exit.point, from: exit.surface, speed: exit.direction * speed, reduced: reduced)
            endGrip()
            _ = followSupports()
            return
        }

        let radius = balls[index].radius
        var center = press.center(under: point, radius: radius)
        center.x = horizontalPosition(center.x, radius: radius, size: size)
        let contact = p(center.x, foot.y)
        if let support = snow.rollingSupport(near: contact) {
            placeOnSurface(index, at: contact.x, y: support.y, on: support.surface)
            if !reduced {
                balls[index].rotation += (center.x - ball.center.x) / radius
            }
        } else {
            balls[index].rest = nil
            if let size {
                let margin = min(radius, size.height / 2)
                center.y = min(size.height - margin, max(margin, center.y))
            }
            balls[index].center = center
        }
        _ = followSupports()
    }

    private func horizontalPosition(_ x: CGFloat, radius: CGFloat, size: CGSize?) -> CGFloat {
        guard let size else { return x }
        let margin = min(radius, size.width / 2)
        return min(size.width - margin, max(margin, x))
    }

    private func pushedOffLedge(_ ball: RolledSnowball, from start: CGPoint, to end: CGPoint, snow: DisplayScene)
        -> (point: CGPoint, surface: SurfaceID, direction: CGFloat)? {
        guard case let .surface(id, _) = ball.rest,
              let surface = snow.surfaces.first(where: { $0.id == id }),
              let edge = crossedEdge(of: surface, from: start.x, to: end.x) else { return nil }
        let fraction = (edge - start.x) / (end.x - start.x)
        let contactY = start.y + (end.y - start.y) * fraction
        let height = snow.supportHeight(surface, at: edge)
        // The hand can still lift a ball clear of a ledge and carry or throw it normally.
        guard contactY >= height - DisplayScene.rollingTolerance else { return nil }
        return (p(edge, height), id, end.x > start.x ? 1 : -1)
    }

    private func crossedEdge(of surface: SnowSurface, from oldX: CGFloat, to x: CGFloat) -> CGFloat? {
        guard !surface.floor, let span = surface.visible.first(where: { $0.contains(oldX) }), !span.contains(x) else { return nil }
        return x < oldX ? span.lowerBound : span.upperBound
    }

    private mutating func trackPointer(_ point: CGPoint, at time: Double) {
        pointer = point
        samples.append(Sample(point: point, time: max(time, (samples.last?.time ?? time) + 0.001)))
        while samples.count > 2 && (samples.count > 16 || time - samples[1].time > 0.12) {
            samples.removeFirst()
        }
    }

    private mutating func endGrip() {
        held = nil
        grip = nil
        samples.removeAll(keepingCapacity: true)
    }

    private mutating func leaveLedge(_ index: Int, at foot: CGPoint, from id: SurfaceID, speed: CGFloat, reduced: Bool) {
        let ball = balls[index]
        let horizontal = min(580, max(-580, speed))
        balls[index].center = p(foot.x, foot.y - ball.radius)
        if !reduced { balls[index].rotation += (foot.x - ball.center.x) / ball.radius }
        balls[index].rest = nil
        balls[index].ledgeTravel = RolledSnowball.LedgeTravel(originY: foot.y, excluding: id)
        balls[index].velocity = CGVector(dx: horizontal, dy: 0)
        balls[index].spin = min(14, max(-14, horizontal / ball.radius))
    }

    private func throwVelocity(at time: Double) -> CGVector {
        guard let last = samples.last, samples.count >= 2 else { return .zero }
        let delay = max(0, time - last.time)
        guard delay < 0.115 else { return .zero }

        var velocity = CGVector.zero
        var total: CGFloat = 0
        for (first, second) in zip(samples, samples.dropFirst()) {
            let interval = max(0.006, second.time - first.time)
            let age = last.time - second.time
            let weight = exp(-age / 0.033) * min(interval, 0.037)
            velocity.dx += (second.point.x - first.point.x) / interval * weight
            velocity.dy += (second.point.y - first.point.y) / interval * weight
            total += weight
        }
        let speed = hypot(velocity.dx, velocity.dy) / total
        guard speed > 26 else { return .zero }
        let factor = min(0.95, 2_100 / speed) * max(0, 1 - max(0, delay - 0.025) / 0.09) / total
        return CGVector(dx: velocity.dx * factor, dy: velocity.dy * factor)
    }

    @discardableResult
    mutating func release(at time: Double, stacking: Bool = true, freely: Bool = false, within size: CGSize? = nil) -> UUID? {
        guard let index = balls.firstIndex(where: { $0.id == held }) else { return nil }
        var velocity = throwVelocity(at: time)
        endGrip()
        let ball = balls[index]
        let carried = Set(subtree(from: ball.id))
        if stacking, let seat = findSeat(for: ball, carried: carried, freely: freely, within: size) {
            balls[index].rest = .ball(seat.id, offset: seat.offset)
            balls[index].velocity = .zero
            balls[index].spin = 0
            if seat.free { setFree(true, for: ball.id) }
            _ = followSupports()
            return ball.id
        }

        if case .surface = ball.rest, abs(velocity.dy) < 125 {
            velocity.dy = 0
        } else {
            balls[index].rest = nil
        }
        balls[index].velocity = velocity
        balls[index].spin = min(15, max(-15, velocity.dx / ball.radius * 0.61))
        balls[index].pitchedDown = velocity.dy > 310
        if hypot(velocity.dx, velocity.dy) > 225 {
            for child in balls.indices where balls[child].id != ball.id && carried.contains(balls[child].id) {
                let offset = balls[child].center - ball.center
                balls[child].rest = nil
                balls[child].velocity = CGVector(dx: velocity.dx * 0.84 + offset.dx * 2.3,
                                                 dy: velocity.dy * 0.69 - min(68, abs(offset.dy) * 0.6))
                balls[child].spin = balls[index].spin * 0.9
                balls[child].pitchedDown = balls[index].pitchedDown
            }
        }
        return nil
    }

    private struct Seat {
        let id: UUID
        let offset: CGFloat
        let free: Bool
        let miss: CGFloat
    }

    private func findSeat(for ball: RolledSnowball, carried: Set<UUID>, freely: Bool, within size: CGSize?) -> Seat? {
        let moving = balls.filter { carried.contains($0.id) }
        let occupied = Set(balls.compactMap { $0.rest?.parent })
        return balls.compactMap { candidate -> Seat? in
            guard candidate.rest != nil, !carried.contains(candidate.id),
                  let base = self.ball(root(of: candidate.id)), case .surface = base.rest,
                  abs(base.velocity.dx) < 75 else { return nil }
            let free = freely || ball.freeStack || candidate.freeStack || moving.count > 1
            guard free || !occupied.contains(candidate.id),
                  candidate.radius >= ball.radius * (free ? 0.76 : 0.85) else { return nil }
            let dx = ball.center.x - candidate.center.x
            let maxOffset = min(candidate.radius * 0.66, (candidate.radius + ball.radius) * 0.51)
            let offset = free ? min(maxOffset, max(-maxOffset, dx)) : 0
            let center = stackedCenter(on: candidate, radius: ball.radius, offset: offset)
            let dy = abs(ball.center.y - center.y)
            guard ball.center.y < candidate.center.y - candidate.radius * 0.30,
                  abs(dx - offset) <= max(9, free ? ball.radius * 0.58 : candidate.radius * 0.84 + ball.radius * 0.20),
                  dy <= max(13, (candidate.radius + ball.radius) * 0.47) else { return nil }
            let shift = center - ball.center
            for part in moving {
                let next = p(part.center.x + shift.dx, part.center.y + shift.dy)
                if let size, next.y < part.radius || next.x < part.radius || next.x > size.width - part.radius { return nil }
                if balls.contains(where: { other in
                    !carried.contains(other.id) && other.id != candidate.id && other.rest != nil
                        && hypot(next.x - other.center.x, next.y - other.center.y) < (part.radius + other.radius) * 0.91
                }) { return nil }
            }
            return Seat(id: candidate.id, offset: offset, free: free, miss: hypot(dx - offset, dy))
        }.min { $0.miss < $1.miss }
    }

    @discardableResult
    mutating func advance(_ delta: CGFloat, size: CGSize, snow: inout DisplayScene, reduced: Bool) -> Bool {
        guard !balls.isEmpty else { return false }
        var moved = false
        var remaining = delta
        while remaining > 0 {
            let step = min(remaining, 1.0 / 90)
            for index in balls.indices.reversed() where balls[index].id != held && balls[index].rest?.parent == nil {
                moved = advanceBall(index, step, size: size, snow: &snow, reduced: reduced) || moved
            }
            remaining -= step
        }
        return followSupports() || moved
    }

    private mutating func advanceBall(_ index: Int, _ delta: CGFloat, size: CGSize,
                                      snow: inout DisplayScene, reduced: Bool) -> Bool {
        let ball = balls[index]
        balls[index].compression *= exp(-14 * delta)
        if case let .surface(id, fraction) = ball.rest {
            if let surface = snow.surfaces.first(where: { $0.id == id }) {
                let oldX = surface.rect.minX + fraction * surface.rect.width
                let x = oldX + ball.velocity.dx * delta
                if surface.visible.contains(where: { $0.contains(oldX) }) {
                    let wall = sideImpact(from: oldX, to: x, radius: ball.radius, width: size.width)
                    if let edge = crossedEdge(of: surface, from: oldX, to: x) {
                        let travel = (edge - oldX) / (x - oldX)
                        if travel < (wall?.time ?? .infinity) {
                            let speed = ball.velocity.dx * exp(-3.4 * delta * travel)
                            leaveLedge(index, at: p(edge, snow.supportHeight(surface, at: edge)), from: id,
                                       speed: speed, reduced: reduced)
                            advanceAirborne(index, delta * (1 - travel), size: size, snow: &snow, reduced: reduced)
                            return true
                        }
                    }
                    if let wall {
                        let y = snow.supportHeight(surface, at: wall.x)
                        if ball.ledgeTravel == nil, abs(ball.velocity.dx) > 38 {
                            shatter(index, center: p(wall.x, y - ball.radius), normal: wall.normal, snow: &snow, reduced: reduced)
                        } else {
                            placeOnSurface(index, at: wall.x, y: y, on: surface)
                            balls[index].velocity = .zero
                        }
                        return true
                    }
                    placeOnSurface(index, at: x, y: snow.supportHeight(surface, at: x), on: surface)
                    if !reduced { balls[index].rotation += (x - oldX) / ball.radius }
                    let slow = ball.velocity.dx * exp(-3.4 * delta)
                    balls[index].velocity.dx = abs(slow) < 1.5 ? 0 : slow
                    return balls[index].center != ball.center || ball.compression > 0.002
                }
            }
            leaveLedge(index, at: p(ball.center.x, ball.center.y + ball.radius), from: id,
                       speed: ball.velocity.dx, reduced: reduced)
        }
        advanceAirborne(index, delta, size: size, snow: &snow, reduced: reduced)
        return true
    }

    private mutating func advanceAirborne(_ index: Int, _ delta: CGFloat, size: CGSize,
                                          snow: inout DisplayScene, reduced: Bool) {
        guard delta > 0 else { return }
        let ball = balls[index]
        let gravity: CGFloat = 960
        let end = p(ball.center.x + ball.velocity.dx * delta,
                    ball.center.y + (ball.velocity.dy + gravity * delta / 2) * delta)
        balls[index].velocity.dx *= exp(-0.52 * delta)
        balls[index].velocity.dy += gravity * delta
        if !reduced { balls[index].rotation += ball.spin * delta }
        balls[index].spin *= exp(-0.32 * delta)

        let side = sideImpact(from: ball.center.x, to: end.x, radius: ball.radius, width: size.width)
        let upward = end.y < ball.center.y && end.y < ball.radius
        let topTime = upward ? max(0, (ball.radius - ball.center.y) / (end.y - ball.center.y)) : 2
        let sideTime = side?.time ?? 2
        let hit = snow.sweptLanding(from: p(ball.center.x, ball.center.y + ball.radius), to: p(end.x, end.y + ball.radius),
                                    radius: ball.radius, excluding: ball.ledgeTravel?.excluding)
        let hitTime = hit?.time ?? 2
        if topTime <= 1 && topTime <= sideTime && topTime < hitTime {
            let x = ball.center.x + (end.x - ball.center.x) * topTime
            if ball.ledgeTravel == nil {
                shatter(index, center: p(x, ball.radius), normal: CGVector(dx: 0, dy: 1), snow: &snow, reduced: reduced)
            } else {
                balls[index].center = p(x, ball.radius)
                balls[index].velocity.dy = 0
            }
        } else if let side, sideTime < hitTime {
            let y = ball.center.y + (end.y - ball.center.y) * sideTime
            if ball.ledgeTravel == nil, abs(ball.velocity.dx) > 38 {
                shatter(index, center: p(side.x, y), normal: side.normal, snow: &snow, reduced: reduced)
            } else {
                balls[index].center = p(side.x, y)
                balls[index].velocity.dx = 0
                balls[index].velocity.dy = ball.velocity.dy + gravity * delta * sideTime
            }
        } else if let hit {
            balls[index].velocity.dy = ball.velocity.dy + gravity * delta * hitTime
            land(index, at: hit.point, on: hit.surface, screenHeight: size.height, snow: &snow,
                 reduced: reduced, onCorner: hit.onCorner)
        } else if end.y + ball.radius >= size.height, let floor = snow.surfaces.first(where: \.floor) {
            let x = horizontalPosition(end.x, radius: ball.radius, size: size)
            land(index, at: p(x, snow.supportHeight(floor, at: x)), on: floor, screenHeight: size.height,
                 snow: &snow, reduced: reduced)
        } else {
            balls[index].center = end
        }
    }

    private func sideImpact(from old: CGFloat, to new: CGFloat, radius: CGFloat, width: CGFloat)
        -> (x: CGFloat, time: CGFloat, normal: CGVector)? {
        let margin = min(radius, width * 0.5)
        if new < old && new < margin { return (margin, max(0, (margin - old) / (new - old)), CGVector(dx: 1, dy: 0)) }
        if new > old && new > width - margin {
            return (width - margin, max(0, (width - margin - old) / (new - old)), CGVector(dx: -1, dy: 0))
        }
        return nil
    }

    private mutating func placeOnSurface(_ index: Int, at x: CGFloat, y: CGFloat, on surface: SnowSurface) {
        balls[index].center = p(x, y - balls[index].radius)
        balls[index].rest = .surface(surface.id, fraction: (x - surface.rect.minX) / surface.rect.width)
    }

    private mutating func land(_ index: Int, at point: CGPoint, on surface: SnowSurface, screenHeight: CGFloat,
                               snow: inout DisplayScene, reduced: Bool, onCorner: Bool = false) {
        let ball = balls[index]
        let impact = max(0, ball.velocity.dy)
        let center = p(point.x, point.y - ball.radius)
        let overHalfScreen = ball.ledgeTravel.map { point.y - $0.originY > screenHeight * 0.5 }
        if surface.floor, overHalfScreen ?? (ball.pitchedDown && impact > 450) {
            shatter(index, center: center, normal: CGVector(dx: 0, dy: -1), snow: &snow, reduced: reduced)
            return
        }
        balls[index].center = center
        balls[index].compression = reduced ? 0 : min(1, impact / 420)
        if ball.ledgeTravel != nil {
            // A window absorbs the vertical drop. The ball can carry its horizontal momentum to the next edge.
            balls[index].ledgeTravel = RolledSnowball.LedgeTravel(originY: point.y, excluding: nil)
            balls[index].velocity.dx *= surface.floor ? 0.72 : 0.90
        } else {
            balls[index].velocity.dx *= impact > 95 ? 0.74 : 0.89
        }
        if onCorner { balls[index].velocity.dx *= 0.62 }
        if impact > 138 && !reduced {
            balls[index].velocity.dy = ball.ledgeTravel != nil ? -min(66, impact * 0.12) : -min(112, impact * 0.19)
        } else {
            balls[index].velocity.dy = 0
            balls[index].rest = .surface(surface.id, fraction: (point.x - surface.rect.minX) / surface.rect.width)
        }
        balls[index].pitchedDown = false
    }

    private mutating func shatter(_ index: Int, center: CGPoint, normal: CGVector,
                                  snow: inout DisplayScene, reduced: Bool) {
        let ball = balls.remove(at: index)
        let contact = p(center.x - normal.dx * ball.radius, center.y - normal.dy * ball.radius)
        snow.shatterSnowball(at: contact, inward: normal, mass: ball.mass, radius: ball.radius,
                             velocity: ball.velocity, reduced: reduced)
    }

    private func stackedCenter(on parent: RolledSnowball, radius: CGFloat, offset: CGFloat) -> CGPoint {
        let spacing = (parent.radius + radius) * 0.92
        return p(parent.center.x + offset, parent.center.y - sqrt(max(0, spacing * spacing - offset * offset)))
    }

    private mutating func followSupports() -> Bool {
        guard balls.contains(where: { $0.rest?.parent != nil }) else { return false }
        let indices = Dictionary(uniqueKeysWithValues: balls.indices.map { (balls[$0].id, $0) })
        for index in balls.indices {
            if let id = balls[index].rest?.parent, indices[id] == nil { balls[index].rest = nil }
        }
        var settled = Set(balls.filter { $0.rest?.parent == nil }.map(\.id))
        let linked = balls.indices.filter { balls[$0].rest?.parent != nil }
        var moved = false
        while settled.count < balls.count {
            let before = settled.count
            for index in linked where !settled.contains(balls[index].id) {
                guard case let .ball(id, offset) = balls[index].rest, settled.contains(id), let support = indices[id] else { continue }
                let center = stackedCenter(on: balls[support], radius: balls[index].radius, offset: offset)
                moved = moved || center != balls[index].center
                balls[index].center = center
                settled.insert(balls[index].id)
            }
            if settled.count == before { break }
        }
        return moved
    }

    private func root(of id: UUID) -> UUID {
        var root = id
        while let next = ball(root)?.rest?.parent { root = next }
        return root
    }

    private func subtree(from id: UUID) -> [UUID] {
        var result = [id]
        var index = 0
        while index < result.count {
            let parent = result[index]
            result += balls.filter { $0.rest?.parent == parent }.map(\.id)
            index += 1
        }
        return result
    }

    func canToggleFree(for id: UUID) -> Bool {
        let members = Set(subtree(from: root(of: id)))
        return !balls.contains { members.contains($0.id) && !$0.props.isEmpty }
    }

    mutating func setFree(_ free: Bool, for id: UUID) {
        guard free || canToggleFree(for: id) else { return }
        let members = Set(subtree(from: root(of: id)))
        for index in balls.indices where members.contains(balls[index].id) { balls[index].freeStack = free }
    }

    mutating func addProp(_ choice: SnowballPropChoice, to id: UUID, at point: CGPoint) {
        guard let index = balls.firstIndex(where: { $0.id == id }) else { return }
        let ball = balls[index]
        var next = choice.mount(on: ball, near: point)
        for prop in next where prop.kind.exclusive {
            balls[index].props.removeAll { $0.kind.slot == prop.kind.slot }
        }
        next = Array(next.prefix(max(0, 32 - balls[index].props.count)))
        balls[index].props.append(contentsOf: next)
        if !next.isEmpty { setFree(true, for: id) }
    }

    mutating func moveProp(_ prop: UUID, on ball: UUID, to point: CGPoint) {
        guard let index = balls.firstIndex(where: { $0.id == ball }),
              let piece = balls[index].props.firstIndex(where: { $0.id == prop }) else { return }
        let current = balls[index]
        balls[index].props[piece].move(to: point, on: current)
    }

    mutating func removeProp(_ prop: UUID?, from id: UUID) {
        guard let index = balls.firstIndex(where: { $0.id == id }) else { return }
        balls[index].props.removeAll { prop == nil || prop == $0.id }
    }

    var hasStack: Bool { stack(containing: nil, minimum: 2, automatic: false) != nil }

    func canFinishStack(containing ball: UUID) -> Bool {
        stack(containing: ball, minimum: 2, automatic: false) != nil
    }

    private func stack(containing member: UUID?, minimum: Int, automatic: Bool)
        -> (base: RolledSnowball, surface: SurfaceID, ids: [UUID])? {
        for ball in balls {
            guard case let .surface(surface, _) = ball.rest else { continue }
            let group = subtree(from: ball.id)
            guard group.count >= minimum, group.count <= 3, member.map(group.contains) ?? true else { continue }
            let parts = balls.filter { group.contains($0.id) }
            let parents = Set(parts.compactMap { $0.rest?.parent })
            guard parents.count == parts.count - 1, parts.allSatisfy({ $0.props.isEmpty && (!automatic || !$0.freeStack) }) else { continue }
            return (ball, surface, group)
        }
        return nil
    }

    mutating func takeStack(containing member: UUID? = nil, minimum: Int = 2, automatic: Bool = false)
        -> (base: RolledSnowball, surface: SurfaceID, count: Int)? {
        guard let group = stack(containing: member, minimum: minimum, automatic: automatic) else { return nil }
        balls.removeAll { group.ids.contains($0.id) }
        return (group.base, group.surface, group.ids.count)
    }

    mutating func contactPlow(_ contact: SnowplowContact) -> Bool {
        var swept = Set<UUID>()
        for ball in balls where ball.rest?.parent == nil && ball.id != held {
            guard contact.hits(ball.center, radius: ball.radius) else { continue }
            let group = subtree(from: ball.id)
            swept.formUnion(group)
            var leading: CGFloat = 0
            for id in group {
                guard let part = self.ball(id) else { continue }
                plowed.append(PlowedSnowball(ball: part, contact: contact, lead: leading))
                leading += part.radius * 1.55
            }
        }
        balls.removeAll { swept.contains($0.id) }
        return !swept.isEmpty
    }

    mutating func advancePlowed(_ delta: CGFloat, contact: SnowplowContact?, floor: CGRect, reduced: Bool) {
        for index in plowed.indices.reversed() {
            if !plowed[index].advance(delta, contact: contact, floor: floor, reduced: reduced) {
                plowed.remove(at: index)
            }
        }
    }
}

struct PlowedSnowball {
    private(set) var ball: RolledSnowball
    private let direction: CGFloat
    private let speed: CGFloat
    private let lead: CGFloat
    private var blade: CGFloat
    private var falling: CGFloat
    private var age: CGFloat = 0

    init(ball: RolledSnowball, contact: SnowplowContact, lead: CGFloat) {
        self.ball = ball
        self.ball.rest = nil
        direction = contact.direction
        speed = contact.speed
        blade = contact.blade
        self.lead = lead
        falling = -min(140, 42 + lead)
    }

    mutating func advance(_ delta: CGFloat, contact: SnowplowContact?, floor: CGRect, reduced: Bool) -> Bool {
        age += delta
        if let contact, contact.direction == direction { blade = contact.blade }
        else { blade += direction * speed * delta }
        let radius = ball.radius
        let edge = blade + direction * (radius + min(1, age / 0.40) * lead)
        let oldX = ball.center.x
        ball.center.x = direction * max(direction * edge, direction * oldX + speed * 0.69 * delta)
        if !reduced { ball.rotation += (ball.center.x - oldX) / radius }
        falling += delta * 860
        ball.center.y += falling * delta
        if ball.center.y + radius >= floor.minY {
            ball.center.y = floor.minY - radius
            falling = falling > 72 ? -falling * 0.19 : 0
        }
        let tail = radius * (ball.props.isEmpty ? 1.12 : 2.2)
        return direction > 0 ? ball.center.x - tail < floor.maxX : ball.center.x + tail > floor.minX
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }
}
