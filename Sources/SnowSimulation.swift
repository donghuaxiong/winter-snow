import AppKit
import QuartzCore

struct DesktopWindow: Equatable {
    var id: UInt32
    var pid: Int32
    var owner: String
    var rect: CGRect
    var widget = false

    var anchor: WindowAnchor {
        WindowAnchor(id: id, owner: owner, pid: pid, x: rect.midX, y: rect.midY)
    }

    static func presentedFrame(of windowNumber: Int, primaryTop: CGFloat) -> CGRect? {
        guard let number = UInt32(exactly: windowNumber), number > 0,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, number)
                as? [[String: Any]])?.first,
              (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value == number,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              (info[kCGWindowAlpha as String] as? Double ?? 0) > 0.15,
              let rawBounds = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary), !bounds.isEmpty else { return nil }
        return CGRect(x: bounds.minX, y: primaryTop - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    static func onscreen(primaryTop: CGFloat, ignoring pid: Int32, includingOwnWindow ownWindow: UInt32? = nil,
                         stageDisplays: [CGRect] = []) -> [Self] {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID != pid || id == ownWindow,
                  let owner = entry[kCGWindowOwnerName as String] as? String,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let alpha = entry[kCGWindowAlpha as String] as? Double, alpha > 0.15,
                  let rawBounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return nil }
            let widget = owner == "NotificationCenter" && layer < 0 && (80...480).contains(bounds.width)
                && (65...490).contains(bounds.height)
            guard widget || (layer == 0 && bounds.width >= 90 && bounds.height >= 50
                             && !["Dock", "Window Server", "NotificationCenter", "Control Center"].contains(owner)) else {
                return nil
            }
            let rect = CGRect(x: bounds.minX, y: primaryTop - bounds.maxY, width: bounds.width, height: bounds.height)
            if !widget && StageWindow.isThumbnail(rect, on: stageDisplays) { return nil }
            return Self(id: id, pid: ownerPID, owner: owner, rect: rect, widget: widget)
        }
    }
}

enum SurfaceID: Hashable {
    case window(UInt32), decoration(UUID), dock, floor
}

struct SnowSurface: Equatable {
    let id: SurfaceID
    let rect: CGRect
    let visible: [ClosedRange<CGFloat>]
    let floor: Bool
    var occluders: [CGRect] = []
    var cornerRadius: CGFloat = 0

    var maximumDepth: CGFloat { floor ? 26 : id == .dock ? 7 : 13 }

    func driftX(localX: CGFloat, recordedWidth: CGFloat) -> CGFloat {
        guard id == .dock, rect.width > 0 else { return localX }
        return localX * recordedWidth / rect.width
    }

    func snowDepth(_ drift: SnowDrift?, at x: CGFloat) -> CGFloat {
        guard let drift else { return 0 }
        return drift.height(at: driftX(localX: x - rect.minX, recordedWidth: drift.width))
    }

    func settlingY(at x: CGFloat, depth: CGFloat) -> CGFloat {
        guard id == .dock, cornerRadius > 0 else { return rect.minY - depth }
        let profile = DockSnowProfile(rect, radius: cornerRadius)
        return profile.contactY(at: x) - depth * profile.coverage(at: x)
    }

    func overflowCorner(left: Bool, on floor: CGRect) -> CGPoint? {
        guard case .window = id, cornerRadius > 0 else { return nil }
        let edge = left ? rect.minX : rect.maxX
        let inside = edge + (left ? 1 : -1) * max(20, cornerRadius + 4)
        let outside = edge + (left ? -6 : 6)
        guard (floor.minX...floor.maxX).contains(outside), rect.minY + cornerRadius + 7 < floor.minY,
              visible.contains(where: { $0.contains(edge) && $0.contains(inside) }) else { return nil }
        let route = CGRect(x: min(inside, outside), y: rect.minY - 5,
                           width: abs(inside - outside), height: cornerRadius + 12)
        guard !occluders.contains(where: { $0.intersects(route) }) else { return nil }
        return p(edge, rect.minY)
    }
}

struct WindowShake {
    var rect: CGRect
    private var direction = 0
    private var distance: CGFloat = 0
    private var reversedDistance: CGFloat = 0
    private var lastMove = -Double.infinity
    private var lastTurn = -Double.infinity
    private var lastRelease = -Double.infinity
    private(set) var fling: CGFloat = 0

    init(rect: CGRect) { self.rect = rect }

    mutating func update(_ new: CGRect, at time: Double) -> Bool {
        let dx = new.midX - rect.midX
        let movingWindow = abs(rect.width - new.width) < 3 && abs(rect.height - new.height) < 3
        rect = new
        if !movingWindow || time - lastMove > 0.42 {
            direction = 0
            distance = 0
            reversedDistance = 0
        }
        guard movingWindow, abs(dx) >= 0.5 else { return false }
        let next = dx > 0 ? 1 : -1
        if next != direction {
            reversedDistance = distance
            lastTurn = time
            distance = 0
            direction = next
        }
        distance += abs(dx)
        lastMove = time
        guard reversedDistance >= 13, distance >= 7, time - lastTurn <= 0.31,
              time - lastRelease > 0.55 else { return false }
        fling = -CGFloat(direction) * min(170, max(38, reversedDistance * 2.2))
        lastRelease = time
        reversedDistance = 0
        return true
    }
}

struct Flake {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var speed: CGFloat
    var phase: CGFloat
    var depth: CGFloat
    var opacity: CGFloat = 1
    var crystal: CGFloat = 1
}

struct DisplayScene {
    static let rollingTolerance: CGFloat = 17

    var flakes: [Flake] = []
    var released: [Flake] = []
    private var drifts: [SurfaceID: SnowDrift] = [:]
    var surfaces: [SnowSurface] = []
    private(set) var plow: PlowPass?
    private(set) var powder: [SnowPowder] = []
    private(set) var fallingSnow: [WindowSnowClump] = []
    private(set) var impactPowder: [SnowPowder] = []
    private(set) var looseSnow: [LooseSnow] = []
    private(set) var completedPasses = 0
    private let windowSnow: WindowSnowpack
    private var nextDirection: CGFloat
    private var settling: CGFloat = 0
    private var cooldown: CGFloat = 0
    private var rng: SnowRandom
    private let weatherSeed: UInt64
    private var hasEmittedSnow = false

    init(id: UInt32, windowSnow: WindowSnowpack = WindowSnowpack()) {
        rng = SnowRandom(state: UInt64(id) + 841_651)
        weatherSeed = UInt64(id) + 841_651
        nextDirection = id.isMultiple(of: 2) ? 1 : -1
        self.windowSnow = windowSnow
    }

    var plowAnimating: Bool { plow != nil || !powder.isEmpty }
    var fallingSnowAnimating: Bool { !fallingSnow.isEmpty || !impactPowder.isEmpty || !looseSnow.isEmpty }
    var weatherAnimating: Bool { !flakes.isEmpty || !released.isEmpty || plowAnimating }
    var hasAccumulation: Bool { !drifts.isEmpty }

    func drift(on id: SurfaceID) -> SnowDrift? {
        if case let .window(window) = id { return windowSnow[window] }
        return drifts[id]
    }

    @discardableResult
    mutating func startPlow() -> Bool {
        guard plow == nil, surfaces.contains(where: \.floor) else { return false }
        plow = PlowPass(direction: nextDirection)
        nextDirection *= -1
        return true
    }

    mutating func clearAccumulation() {
        windowSnow.clear()
        drifts.removeAll(keepingCapacity: true)
        released.removeAll(keepingCapacity: true)
        fallingSnow.removeAll(keepingCapacity: true)
        impactPowder.removeAll(keepingCapacity: true)
        looseSnow.removeAll(keepingCapacity: true)
        plow = nil
        powder.removeAll(keepingCapacity: true)
        settling = 0
        cooldown = 0
    }

    mutating func step(size: CGSize, delta: CGFloat, time: CGFloat, settings: SnowSettings, reduced: Bool,
                       emitting: Bool = true, lowPower: Bool = false) {
        if emitting {
            let scale = min(2.1, max(0.5, (size.width * size.height) / 1_250_000))
            let target = Int((65 + settings.intensity * 675) * scale * (reduced ? 0.24 : lowPower ? 0.70 : 1))
            if flakes.count > target { flakes.removeLast(flakes.count - target) }
            if flakes.count < target {
                let count = hasEmittedSnow ? min(target - flakes.count, 32) : target - flakes.count
                for _ in 0..<count { flakes.append(makeFlake(in: size, scattered: !hasEmittedSnow)) }
                hasEmittedSnow = true
            }
        }
        if !settings.accumulate {
            windowSnow.clear()
            drifts.removeAll(keepingCapacity: true)
            fallingSnow.removeAll(keepingCapacity: true)
            impactPowder.removeAll(keepingCapacity: true)
            looseSnow.removeAll(keepingCapacity: true)
            plow = nil
            powder.removeAll(keepingCapacity: true)
            cooldown = 0
        }
        let floor = surfaces.first(where: \.floor)
        let gust = SnowGust(time: time, width: size.width, amount: reduced ? 0 : settings.gusts, seed: weatherSeed)

        let movement = delta * (0.33 + settings.speed * 1.77) * (reduced ? 0.48 : 1)
        var remaining = 0
        for index in flakes.indices {
            let old = flakes[index]
            if !emitting && old.y + old.radius < 0 { continue }
            var flake = old
            let breeze = CGFloat(settings.wind) * 92 + sin(time * 0.57 + flake.phase) * 20
            flake.x += movement * (breeze + gust.push(at: flake.x)) * (0.35 + flake.depth * 0.65)
            flake.y += movement * flake.speed
            if flake.x < -18 { flake.x += size.width + 32 }
            if flake.x > size.width + 18 { flake.x -= size.width + 32 }
            if settings.accumulate && flake.depth > 0.22 {
                for surface in surfaces {
                    let baseline = surface.rect.minY
                    let bend = surface.id == .dock ? surface.cornerRadius : 0
                    guard flake.y >= baseline - surface.maximumDepth, old.y < baseline + bend,
                          surface.visible.contains(where: { $0.contains(flake.x) }) else { continue }
                    let x = flake.x - surface.rect.minX
                    let y = surface.settlingY(at: flake.x, depth: surface.snowDepth(drift(on: surface.id), at: flake.x))
                    guard old.y < y, flake.y >= y else { continue }
                    if !surface.floor && rng.next() > (surface.id == .dock ? 0.74 : 0.48) { continue }
                    if !surface.floor || plow == nil {
                        land(on: surface, at: x, mass: (surface.floor ? 6.4 : 4.4) * (0.62 + flake.depth * 0.63))
                    }
                    flake.y = size.height + 20
                    break
                }
            }
            if flake.y > size.height + 15 {
                guard emitting else { continue }
                flake = makeFlake(in: size, scattered: false)
            }
            flakes[remaining] = flake
            remaining += 1
        }
        if remaining < flakes.count { flakes.removeLast(flakes.count - remaining) }

        stepDebris(size: size, delta: delta, accumulate: settings.accumulate)
        if settings.accumulate {
            windowSnow.settle(at: time)
            settling += delta
            if settling >= 0.18 {
                settling -= 0.18
                for key in Array(drifts.keys) where key != .floor || plow == nil {
                    drifts[key]?.settle()
                }
                if emitting, let floor { spillWindowCorners(at: time, within: floor.rect, reduced: reduced) }
            }
            if let floor {
                updatePlow(on: floor, delta: delta, automatic: emitting && settings.automaticPlowing, reduced: reduced)
            }
        }
    }

    mutating func stepDebris(size: CGSize, delta: CGFloat, accumulate: Bool) {
        for index in released.indices {
            let previousY = released[index].y
            released[index].y += delta * released[index].speed
            released[index].speed += delta * 370
            released[index].x += delta * released[index].phase
            released[index].opacity -= delta * 0.8
            let snow = released[index]
            if let hit = landing(at: snow.x, from: previousY, to: snow.y) {
                if accumulate && (!hit.surface.floor || plow == nil) {
                    land(on: hit.surface, at: snow.x - hit.surface.rect.minX, mass: snow.radius * snow.opacity * 2.2)
                }
                released[index].opacity = 0
            }
        }
        released.removeAll { $0.opacity <= 0 || $0.y > size.height + 16 }
    }

    func landing(at x: CGFloat, from oldY: CGFloat, to newY: CGFloat,
                 excluding source: SurfaceID? = nil) -> (surface: SnowSurface, y: CGFloat)? {
        guard oldY <= newY else { return nil }
        for surface in surfaces where surface.id != source && surface.visible.contains(where: { $0.contains(x) }) {
            let y = supportHeight(surface, at: x)
            if oldY <= y && y <= newY { return (surface, y) }
        }
        return nil
    }

    func supportHeight(_ surface: SnowSurface, at x: CGFloat) -> CGFloat {
        surface.settlingY(at: x, depth: surface.snowDepth(drift(on: surface.id), at: x))
    }

    struct BallLanding {
        let surface: SnowSurface
        let point: CGPoint
        let time: CGFloat
        var onCorner = false
    }

    func sweptLanding(from start: CGPoint, to end: CGPoint, radius: CGFloat = 0,
                      excluding source: SurfaceID?) -> BallLanding? {
        let dx = end.x - start.x, dy = end.y - start.y
        guard dy > 0 else { return nil }
        var firstHit: BallLanding?
        for surface in surfaces where surface.id != source
            && end.y >= surface.rect.minY - surface.maximumDepth
            && start.y <= surface.rect.minY + max(surface.id == .dock ? surface.cornerRadius : 0, radius * 0.16) + 1 {
            let snow = drift(on: surface.id)
            func height(atX x: CGFloat) -> CGFloat {
                return surface.settlingY(at: x, depth: surface.snowDepth(snow, at: x))
            }
            func height(at time: CGFloat) -> CGFloat { height(atX: start.x + dx * time) }
            for span in surface.visible {
                if radius > 0, case .window = surface.id {
                    for (edgeX, inward): (CGFloat, CGFloat) in [(span.lowerBound, 1), (span.upperBound, -1)] {
                        let tip = p(edgeX, height(atX: edgeX))
                        guard let time = Self.cornerContact(from: start, dx: dx, dy: dy, radius: radius, tip: tip, inward: inward),
                              time < (firstHit?.time ?? .infinity) else { continue }
                        let seat = edgeX + inward * min(2, (span.upperBound - span.lowerBound) / 4)
                        firstHit = BallLanding(surface: surface, point: p(seat, height(atX: seat)), time: time, onCorner: true)
                    }
                }
                let begin: CGFloat, end: CGFloat
                if dx == 0 {
                    guard span.contains(start.x) else { continue }
                    begin = 0
                    end = min(1, firstHit?.time ?? 1)
                } else {
                    let a = (span.lowerBound - start.x) / dx
                    let b = (span.upperBound - start.x) / dx
                    begin = max(0, min(a, b))
                    end = min(firstHit?.time ?? 1, max(a, b))
                }
                guard begin <= end else { continue }
                var before = begin
                var gap = start.y + dy * begin - height(at: begin)
                // Contact starts from above the visible edge. A small tolerance covers an existing contact at frame start.
                guard gap <= (begin == 0 ? 0.85 : 0) else { continue }
                var collision: CGFloat? = gap >= 0 ? begin : nil
                if collision == nil {
                    let checks = max(1, Int(ceil((end - begin) * abs(dx) / 3)))
                    for step in 1...checks {
                        let time = begin + (end - begin) * CGFloat(step) / CGFloat(checks)
                        let distance = start.y + dy * time - height(at: time)
                        if distance >= 0 {
                            collision = before + (time - before) * (-gap / (distance - gap))
                            break
                        }
                        before = time
                        gap = distance
                    }
                }
                if let time = collision, time < (firstHit?.time ?? .infinity) {
                    firstHit = BallLanding(surface: surface, point: p(start.x + dx * time, height(at: time)), time: time)
                }
            }
        }
        return firstHit
    }

    private static func cornerContact(from foot: CGPoint, dx: CGFloat, dy: CGFloat, radius: CGFloat,
                                      tip: CGPoint, inward: CGFloat) -> CGFloat? {
        let x = foot.x - tip.x, y = foot.y - radius - tip.y
        let along = x * dx + y * dy
        guard along < 0 else { return nil }
        let travel = dx * dx + dy * dy
        let distance = x * x + y * y - radius * radius
        let discriminant = along * along - travel * distance
        guard discriminant >= 0 else { return nil }
        let time = max(0, (-along - sqrt(discriminant)) / travel)
        let side = (x + dx * time) * inward
        // The lower arc can catch a lip. A sideways graze or an approach from below keeps falling.
        guard time <= 1, side <= 0, side >= -radius * 0.51, y + dy * time <= -radius * 0.86 else { return nil }
        return time
    }

    mutating func shatterSnowman(at point: CGPoint, on support: SnowSurface, scale: CGFloat, accumulate: Bool) {
        if accumulate && (!support.floor || plow == nil) {
            land(on: support, at: point.x - support.rect.minX, mass: 28 * scale)
        }
        for index in 0..<34 {
            let heavy = index < 5
            released.append(Flake(x: point.x + rng.inRange(-7, 7), y: point.y - rng.inRange(2, 18),
                                  radius: heavy ? rng.inRange(3.5, 6.4) : rng.inRange(0.65, 2.7),
                                  speed: -rng.inRange(38, heavy ? 117 : 180),
                                  phase: rng.inRange(-136, 132), depth: 1,
                                  opacity: rng.inRange(0.62, 1)))
        }
    }

    private mutating func land(on surface: SnowSurface, at x: CGFloat, mass: CGFloat) {
        if case let .window(window) = surface.id {
            if windowSnow[window] == nil {
                windowSnow[window] = SnowDrift(width: surface.rect.width, floor: false,
                                               seed: rng.state, maximumDepth: surface.maximumDepth)
            }
            windowSnow[window]?.land(at: x, mass: max(0, mass))
            return
        }
        if drifts[surface.id] == nil {
            drifts[surface.id] = SnowDrift(width: surface.rect.width, floor: surface.floor,
                                          seed: rng.state, maximumDepth: surface.maximumDepth)
        }
        if let savedWidth = drifts[surface.id]?.width {
            let storedX = surface.driftX(localX: x, recordedWidth: savedWidth)
            drifts[surface.id]?.land(at: storedX, mass: max(0, mass))
        }
    }

    private mutating func updatePlow(on floor: SnowSurface, delta: CGFloat, automatic: Bool, reduced: Bool) {
        for index in powder.indices { powder[index].step(delta) }
        powder.removeAll { $0.age >= $0.life || $0.y > floor.rect.minY + 1 }
        cooldown = max(0, cooldown - delta)
        if plow == nil, automatic, cooldown == 0, drifts[.floor]?.readyToPlow == true {
            if reduced {
                drifts[.floor]?.leaveDust()
                completedPasses += 1
                cooldown = 3
            } else {
                startPlow()
            }
        }
        guard var pass = plow else { return }
        let width = floor.rect.width
        let oldBlade = pass.bladeX(width: width)
        pass.advance(delta, width: width)
        let blade = pass.bladeX(width: width)
        let removed = drifts[.floor]?.scrape(from: oldBlade, to: blade) ?? 0
        pass.push(removed)

        if removed > 0.2 && !reduced {
            let speed = pass.speed(width: width)
            let count = min(4, max(1, Int(ceil(removed / 6))))
            let mass = removed * 0.17 / CGFloat(count)
            for _ in 0..<count {
                looseSnow.append(LooseSnow(position: p(floor.rect.minX + blade + pass.direction * rng.inRange(7, 14),
                                                        floor.rect.minY - rng.inRange(8, 23)),
                                           velocity: CGVector(dx: pass.direction * speed * rng.inRange(0.58, 1.1),
                                                              dy: -rng.inRange(65, 143)), mass: mass))
            }
            for _ in 0..<min(8, max(1, Int(removed * 0.58))) {
                let x = floor.rect.minX + blade + pass.direction * rng.inRange(3, 14)
                let forward = pass.speed(width: width) * 0.7 + rng.inRange(46, 112)
                powder.append(SnowPowder(x: x, y: floor.rect.minY - rng.inRange(2, 13),
                                         vx: pass.direction * forward, vy: -rng.inRange(24, 91),
                                         life: rng.inRange(0.20, 0.58), radius: rng.inRange(0.75, 2.85)))
            }
        }
        if pass.isComplete(width: width) {
            plow = nil
            completedPasses += 1
            cooldown = 3
        } else {
            plow = pass
        }
    }

    @discardableResult
    mutating func sweepSnow(from start: CGPoint, to end: CGPoint, delta: CGFloat, reduced: Bool) -> Bool {
        guard let sweep = CursorSweep(from: start, to: end, delta: delta) else { return false }
        for surface in surfaces where sweep.reaches(surface) {
            if case .decoration = surface.id { continue }
            guard var drift = drift(on: surface.id) else { continue }
            let scale = surface.id == .dock ? surface.rect.width / drift.width : 1
            guard scale > 0 else { continue }
            let low = max(0, Int(floor((sweep.xRange.lowerBound - surface.rect.minX) / scale / SnowDrift.spacing)))
            let high = min(drift.heights.count - 1, Int(floor((sweep.xRange.upperBound - surface.rect.minX) / scale / SnowDrift.spacing)))
            guard low <= high else { continue }
            var removed: CGFloat = 0
            var weightedX: CGFloat = 0
            var weightedY: CGFloat = 0
            for index in low...high where drift.heights[index] > 0.38 {
                let x = surface.rect.minX + drift.xAt(index) * scale
                guard surface.visible.contains(where: { $0.contains(x) }) else { continue }
                let y = surface.settlingY(at: x, depth: drift.heights[index])
                guard !surface.occluders.contains(where: { $0.contains(p(x, y)) }) else { continue }
                let mass = drift.dislodge(at: index, pressure: sweep.pressure(at: p(x, y)))
                removed += mass
                weightedX += x * mass
                weightedY += y * mass
            }
            guard removed > 0 else { continue }
            let point = p(weightedX / removed, weightedY / removed)
            let destination = end.x + sweep.direction * (22 + sweep.strength * 16)
            let stays = surface.visible.contains { $0.contains(destination) }
            let airborne = stays ? removed * (reduced ? 0.08 : 0.24) : removed
            if stays {
                drift.depositImpact(at: (destination - surface.rect.minX) / scale, mass: removed - airborne, width: 15)
            }
            if case let .window(id) = surface.id { windowSnow[id] = drift }
            else { drifts[surface.id] = drift }
            if airborne > 0 {
                looseSnow.append(LooseSnow(position: p(point.x, point.y - 0.8),
                                           velocity: CGVector(dx: sweep.direction * (22 + sweep.strength * 104),
                                                              dy: -(20 + sweep.strength * 48)), mass: airborne))
            }
            if !reduced && removed > 0.26 {
                for _ in 0..<min(5, Int(ceil(removed))) {
                    impactPowder.append(SnowPowder(x: point.x + rng.inRange(-8, 8), y: point.y - rng.inRange(0, 3),
                                                   vx: sweep.direction * rng.inRange(32, 116) * sweep.strength,
                                                   vy: -rng.inRange(24, 85), life: rng.inRange(0.16, 0.42),
                                                   radius: rng.inRange(0.45, 1.65)))
                }
            }
            return true
        }
        return false
    }

    mutating func dropWindowSnow(_ drift: SnowDrift, from surface: SnowSurface,
                                 horizontalSpeed: CGFloat, reduced: Bool, pendingWindow: UInt32? = nil) {
        fallingSnow.append(contentsOf: WindowSnowClump.detach(drift, from: surface,
                                                              horizontalSpeed: horizontalSpeed,
                                                              reduced: reduced, pendingWindow: pendingWindow, random: &rng))
    }

    private func snowBand(on surface: SnowSurface, drift: SnowDrift, at x: CGFloat) -> ClosedRange<CGFloat>? {
        if case .decoration = surface.id { return nil }
        guard surface.visible.contains(where: { $0.contains(x) }) else { return nil }
        let depth = surface.snowDepth(drift, at: x)
        let top = surface.settlingY(at: x, depth: depth)
        let base = surface.settlingY(at: x, depth: 0)
        guard base - top > 0.45,
              !surface.occluders.contains(where: { $0.minX <= x && $0.maxX >= x && $0.minY < base && $0.maxY > top }) else { return nil }
        return top...base
    }

    func rollHandle(at point: CGPoint) -> CGRect? {
        for surface in surfaces {
            guard let drift = drift(on: surface.id), let band = snowBand(on: surface, drift: drift, at: point.x),
                  band.contains(point.y) else { continue }
            var left = point.x, right = point.x
            var top = band.lowerBound, bottom = band.upperBound
            for direction: CGFloat in [-1, 1] {
                for width in 1...14 {
                    let x = point.x + direction * CGFloat(width)
                    guard let side = snowBand(on: surface, drift: drift, at: x), side.contains(point.y) else { break }
                    if direction < 0 { left = x } else { right = x }
                    top = max(top, side.lowerBound)
                    bottom = min(bottom, side.upperBound)
                }
            }
            return CGRect(x: left, y: top, width: max(1, right - left), height: max(0.45, bottom - top))
        }
        return nil
    }

    func rollingContact(near point: CGPoint) -> CGFloat? {
        for surface in surfaces {
            guard let drift = drift(on: surface.id), let band = snowBand(on: surface, drift: drift, at: point.x),
                  abs(band.lowerBound - point.y) < Self.rollingTolerance else { continue }
            return band.lowerBound
        }
        return nil
    }

    func rollingSupport(near point: CGPoint) -> (surface: SnowSurface, y: CGFloat)? {
        var nearest: (surface: SnowSurface, y: CGFloat)?
        var distance = Self.rollingTolerance
        for surface in surfaces where surface.visible.contains(where: { $0.contains(point.x) }) {
            if case .decoration = surface.id { continue }
            let height = supportHeight(surface, at: point.x)
            let gap = abs(height - point.y)
            if gap < distance {
                nearest = (surface, height)
                distance = gap
            }
        }
        return nearest
    }

    mutating func harvestSnow(from start: CGPoint, to end: CGPoint, radius: CGFloat = 6,
                              limit: CGFloat = .infinity) -> CGFloat {
        guard limit > 0 else { return 0 }
        let dx = end.x - start.x, dy = end.y - start.y
        let distance = hypot(dx, dy)
        let samples = max(1, min(90, Int(ceil(distance / 3.8))))
        let pressure = min(0.60, max(0.12, distance / CGFloat(samples) / 7.1))
        let reach = max(1, min(8, Int(ceil(radius * 0.27 / SnowDrift.spacing))))
        var total: CGFloat = 0
        for index in 1...samples where total < limit {
            let t = CGFloat(index) / CGFloat(samples)
            let point = p(start.x + dx * t, start.y + dy * t)
            for surface in surfaces where surface.visible.contains(where: { $0.contains(point.x) }) {
                guard let drift = drift(on: surface.id), let band = snowBand(on: surface, drift: drift, at: point.x),
                      abs(band.lowerBound - point.y) < Self.rollingTolerance else { continue }
                var pack = drift
                let loc = surface.driftX(localX: point.x - surface.rect.minX, recordedWidth: pack.width)
                let bin = min(pack.heights.count - 1, max(0, Int(loc / SnowDrift.spacing)))
                total += pack.dislodge(at: bin, pressure: pressure, limit: limit - total)
                for offset in 1...reach where total < limit {
                    let weight = pow(1 - CGFloat(offset) / CGFloat(reach + 1), 1.65) * 0.70
                    for side in [bin - offset, bin + offset] where pack.heights.indices.contains(side) {
                        let column = surface.rect.minX + pack.xAt(side) * (surface.id == .dock ? surface.rect.width / pack.width : 1)
                        if snowBand(on: surface, drift: pack, at: column) != nil {
                            total += pack.dislodge(at: side, pressure: pressure * weight, limit: limit - total)
                        }
                    }
                }
                if case let .window(id) = surface.id { windowSnow[id] = pack }
                else { drifts[surface.id] = pack }
                break
            }
        }
        if distance > 2, total > 0.8, impactPowder.count < 120, let y = rollingContact(near: end) {
            let side: CGFloat = dx < 0 ? -1 : 1
            impactPowder.append(SnowPowder(x: end.x, y: y - 1, vx: -side * rng.inRange(12, 29), vy: -rng.inRange(12, 27),
                                           life: rng.inRange(0.20, 0.32), radius: rng.inRange(0.48, 1.25)))
        }
        return total
    }

    mutating func shatterSnowball(at point: CGPoint, inward: CGVector, mass: CGFloat, radius: CGFloat,
                                 velocity: CGVector, reduced: Bool) {
        guard let floor = surfaces.first(where: \.floor) else { return }
        let chunky = min(reduced ? 7 : 17, max(3, Int(radius * 0.26)))
        let count = min(reduced ? chunky + 6 : chunky + 31, max(0, 450 - looseSnow.count))
        let bounds = (floor.rect.minX + 0.5)...(floor.rect.maxX - 0.5)
        if count == 0 {
            let x = min(bounds.upperBound, max(bounds.lowerBound, point.x))
            depositOnFloor(floor, at: x - floor.rect.minX, mass: mass, width: radius)
            return
        }
        let impact = max(40, -(velocity.dx * inward.dx + velocity.dy * inward.dy))
        let tangential = CGVector(dx: velocity.dx + inward.dx * impact, dy: velocity.dy + inward.dy * impact)
        let tangent = CGVector(dx: -inward.dy, dy: inward.dx)
        let weights = (0..<count).map { index in rng.inRange(0.56, 1.45) * (index < chunky ? 5.8 : 0.76) }
        let total = weights.reduce(0, +)
        var remaining = mass
        for index in 0..<count {
            let share = weights[index] / total * mass
            let pieceMass = index == count - 1 ? remaining : share
            remaining -= pieceMass
            let big = index < chunky
            let size = big ? min(12, (0.88 + pow(pieceMass, 0.51) * 1.35) * rng.inRange(0.66, 1.24))
                           : rng.inRange(0.55, 1.9)
            let across = rng.inRange(-radius * 0.56, radius * 0.56)
            let sink = rng.inRange(0.7, max(2, radius * 0.43))
            let x = min(bounds.upperBound, max(bounds.lowerBound, point.x + tangent.dx * across + inward.dx * sink))
            let y = max(size, min(floor.rect.minY - size, point.y + tangent.dy * across + inward.dy * sink - 0.5))
            let rebound = min(410, impact * rng.inRange(0.086, big ? 0.25 : 0.38) + rng.inRange(14, 70))
            let scatter = rng.inRange(-112, 112) * (big ? 0.8 : 1.25)
            let motion = CGVector(dx: inward.dx * rebound + tangent.dx * scatter + tangential.dx * 0.24,
                                  dy: inward.dy * rebound + tangent.dy * scatter + tangential.dy * 0.24 - rng.inRange(4, 42))
            looseSnow.append(LooseSnow(position: p(x, y), velocity: motion, mass: pieceMass, chunkRadius: size,
                                       spin: reduced ? 0 : rng.inRange(-9, 9), angle: rng.inRange(0, .pi * 2)))
        }
        guard !reduced else { return }
        for _ in 0..<min(max(0, 220 - impactPowder.count), 12 + Int(radius * 0.43)) {
            let across = rng.inRange(-radius * 0.72, radius * 0.72)
            let sink = rng.inRange(1, max(2, radius * 0.31))
            let rebound = rng.inRange(49, 148) + min(260, impact * 0.19)
            let sideways = rng.inRange(-92, 92)
            impactPowder.append(SnowPowder(x: point.x + inward.dx * sink + tangent.dx * across,
                                           y: max(0, point.y + inward.dy * sink + tangent.dy * across),
                                           vx: inward.dx * rebound + tangent.dx * sideways + tangential.dx * 0.12,
                                           vy: inward.dy * rebound + tangent.dy * sideways + tangential.dy * 0.12 - 22,
                                           life: rng.inRange(0.23, 0.62), radius: rng.inRange(0.7, 3.0)))
        }
    }

    mutating func shedBranchSnow(at point: CGPoint, load: CGFloat) {
        let count = max(2, Int(ceil(load * 8)))
        for index in 0..<count {
            released.append(Flake(x: point.x + rng.inRange(-7, 7), y: point.y - rng.inRange(1, 6),
                                  radius: index == 0 ? 2.1 + load * 2.7 : rng.inRange(0.7, 1.7),
                                  speed: rng.inRange(-5, 34), phase: rng.inRange(-30, 30), depth: 1))
        }
    }

    private mutating func spillWindowCorners(at time: CGFloat, within floor: CGRect, reduced: Bool) {
        for surface in surfaces {
            guard fallingSnow.count < 48, case let .window(id) = surface.id, var drift = windowSnow[id] else { continue }
            for left in [true, false] {
                guard let edge = surface.overflowCorner(left: left, on: floor) else { continue }
                let mass = drift.spillFromCorner(left: left, at: time)
                guard mass > 0 else { continue }
                windowSnow[id] = drift
                fallingSnow.append(.spill(window: id, edge: edge, radius: surface.cornerRadius, left: left,
                                          mass: mass, reduced: reduced, random: &rng))
                break
            }
        }
    }

    mutating func resolveFallingWindow(_ id: UInt32, didDisappear: Bool) {
        if didDisappear {
            for index in fallingSnow.indices where fallingSnow[index].pendingWindow == id {
                fallingSnow[index].pendingWindow = nil
            }
        } else {
            fallingSnow.removeAll { $0.pendingWindow == id }
        }
    }

    mutating func stepFallingSnow(delta: CGFloat, reduced: Bool) {
        guard let floor = surfaces.first(where: \.floor) else { return }
        for index in impactPowder.indices { impactPowder[index].step(delta) }
        impactPowder.removeAll { $0.age >= $0.life || $0.y >= floor.rect.minY }
        var fracturedSnowLanded = false
        for index in looseSnow.indices.reversed() {
            looseSnow[index].advance(delta, between: (floor.rect.minX + 0.5)...(floor.rect.maxX - 0.5))
            let grain = looseSnow[index]
            let x = grain.position.x - floor.rect.minX
            let crest = floor.rect.minY - (drifts[.floor]?.height(at: x) ?? 0)
            guard grain.velocity.dy > 0, grain.position.y + grain.radius >= crest else { continue }
            depositOnFloor(floor, at: x, mass: grain.mass, width: grain.radius * 3)
            fracturedSnowLanded = fracturedSnowLanded || grain.chunkRadius != nil
            looseSnow.remove(at: index)
        }
        if fracturedSnowLanded { drifts[.floor]?.settle() }
        for index in fallingSnow.indices.reversed() {
            let previousClump = fallingSnow[index]
            let source = previousClump.followsCorner ? surfaces.first { $0.id == previousClump.overflowSource } : nil
            let rolled = fallingSnow[index].advanceAlongCorner(delta, on: source, floor: floor.rect, reduced: reduced)
            if !rolled { fallingSnow[index].advance(delta, within: floor.rect.width) }
            let clump = fallingSnow[index]
            if clump.followsCorner { continue }
            let contact = clump.contact
            let previous = previousClump.contact
            let hit: (surface: SnowSurface, y: CGFloat)
            let floorY = floor.settlingY(at: contact.x, depth: floor.snowDepth(drifts[.floor], at: contact.x))
            if let origin = clump.overflowSource,
               let support = landing(at: contact.x, from: rolled ? min(previous.y, source?.rect.minY ?? previous.y) : previous.y,
                                     to: contact.y, excluding: origin) {
                hit = support
            } else if contact.y >= floorY {
                hit = (floor, floorY)
            } else { continue }
            if clump.pendingWindow != nil {
                // Only a confirmed disappearance can add snow to the floor.
                fallingSnow[index] = previousClump
                continue
            }
            let travel = max(0.001, contact.y - previous.y)
            let fraction = min(1, max(0, (hit.y - previous.y) / travel))
            let x = hit.surface.floor && clump.overflowSource == nil
                ? min(floor.rect.width, max(0, previous.x + (contact.x - previous.x) * fraction)) : contact.x
            depositImpact(on: hit.surface, at: x, mass: clump.mass, width: clump.width)
            fallingSnow.remove(at: index)
            guard !reduced else { continue }
            for _ in 0..<min(7, Int(ceil(clump.mass * 0.42))) {
                impactPowder.append(SnowPowder(x: x + rng.inRange(-clump.width * 0.32, clump.width * 0.32),
                                               y: hit.y - rng.inRange(1, 4), vx: rng.inRange(-76, 76),
                                               vy: -rng.inRange(19, 82), life: rng.inRange(0.16, 0.38),
                                               radius: rng.inRange(0.65, 2.5)))
            }
        }
    }

    private mutating func depositOnFloor(_ floor: SnowSurface, at x: CGFloat, mass: CGFloat, width: CGFloat) {
        if drifts[.floor] == nil {
            drifts[.floor] = SnowDrift(width: floor.rect.width, floor: true, seed: rng.state,
                                       maximumDepth: floor.maximumDepth)
        }
        drifts[.floor]?.depositImpact(at: x, mass: mass, width: width)
    }

    private mutating func depositImpact(on surface: SnowSurface, at x: CGFloat, mass: CGFloat, width: CGFloat) {
        if surface.floor {
            depositOnFloor(surface, at: x - surface.rect.minX, mass: mass, width: width)
            return
        }
        var pack = drift(on: surface.id) ?? SnowDrift(width: surface.rect.width, floor: surface.floor,
                                                      seed: rng.state, maximumDepth: surface.maximumDepth)
        let offset = surface.driftX(localX: x - surface.rect.minX, recordedWidth: pack.width)
        pack.depositImpact(at: offset, mass: mass, width: width)
        if case let .window(id) = surface.id {
            windowSnow[id] = pack
        } else {
            drifts[surface.id] = pack
        }
    }

    mutating func setSurfaces(_ surfaces: [SnowSurface]) {
        if self.surfaces.first(where: \.floor)?.rect != surfaces.first(where: \.floor)?.rect {
            plow = nil
            powder.removeAll(keepingCapacity: true)
        }
        self.surfaces = surfaces.sorted { $0.rect.minY < $1.rect.minY }
        let ids = Set(surfaces.map(\.id))
        for key in Array(drifts.keys) where !ids.contains(key) { drifts.removeValue(forKey: key) }
        for surface in surfaces {
            if case let .window(id) = surface.id {
                windowSnow[id]?.resize(surface.rect.width)
            } else if surface.id != .dock {
                drifts[surface.id]?.resize(surface.rect.width)
            }
        }
    }

    private mutating func makeFlake(in size: CGSize, scattered: Bool) -> Flake {
        let depth = rng.next()
        let crystal = (depth * 103.7).truncatingRemainder(dividingBy: 1)
        return Flake(x: rng.inRange(-12, size.width + 12),
                     y: scattered ? rng.inRange(0, size.height) : rng.inRange(-38, -3),
                     radius: 0.64 + pow(depth, 1.7) * rng.inRange(1.0, 3.15),
                     speed: 24 + depth * rng.inRange(40, 100),
                     phase: rng.inRange(0, .pi * 2), depth: depth, crystal: crystal)
    }
}

func exposedEdge(_ line: CGRect, inside region: CGRect, blockedBy windows: [CGRect]) -> [ClosedRange<CGFloat>] {
    let left = max(line.minX, region.minX)
    let right = min(line.maxX, region.maxX)
    guard left < right, line.minY >= region.minY, line.minY < region.maxY else { return [] }
    var result = [left...right]
    for cover in windows where cover.minY <= line.minY && cover.maxY > line.minY {
        result = result.flatMap { segment in
            guard cover.minX < segment.upperBound, cover.maxX > segment.lowerBound else { return [segment] }
            var parts: [ClosedRange<CGFloat>] = []
            if segment.lowerBound < cover.minX { parts.append(segment.lowerBound...cover.minX) }
            if segment.upperBound > cover.maxX { parts.append(cover.maxX...segment.upperBound) }
            return parts
        }
    }
    return result
}
