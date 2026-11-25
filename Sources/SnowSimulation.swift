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

    static func onscreen(primaryTop: CGFloat, ignoring pid: Int32, stageDisplays: [CGRect] = []) -> [Self] {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, ownerPID != pid,
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
}

struct DisplayScene {
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

    init(id: UInt32, windowSnow: WindowSnowpack = WindowSnowpack()) {
        rng = SnowRandom(state: UInt64(id) + 841_651)
        nextDirection = id.isMultiple(of: 2) ? 1 : -1
        self.windowSnow = windowSnow
    }

    var plowAnimating: Bool { plow != nil || !powder.isEmpty }
    var fallingSnowAnimating: Bool { !fallingSnow.isEmpty || !impactPowder.isEmpty || !looseSnow.isEmpty }

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

    mutating func step(size: CGSize, delta: CGFloat, time: CGFloat, settings: SnowSettings, reduced: Bool) {
        let scale = min(2.1, max(0.5, (size.width * size.height) / 1_250_000))
        let target = Int((65 + settings.intensity * 675) * scale * (reduced ? 0.24 : 1))
        if flakes.count > target { flakes.removeLast(flakes.count - target) }
        if flakes.count < target {
            let number = flakes.isEmpty ? target : min(target - flakes.count, 32)
            for _ in 0..<number { flakes.append(makeFlake(in: size, scattered: true)) }
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

        let movement = delta * (0.33 + settings.speed * 1.77) * (reduced ? 0.48 : 1)
        for index in flakes.indices {
            let old = flakes[index]
            var flake = old
            let breeze = CGFloat(settings.wind) * 92 + sin(time * 0.57 + flake.phase) * 20
            flake.x += movement * breeze * (0.35 + flake.depth * 0.65)
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
            flakes[index] = flake.y > size.height + 15 ? makeFlake(in: size, scattered: false) : flake
        }

        stepDebris(size: size, delta: delta, accumulate: settings.accumulate)
        if settings.accumulate {
            windowSnow.settle(at: time)
            settling += delta
            if settling >= 0.18 {
                settling -= 0.18
                for key in Array(drifts.keys) where key != .floor || plow == nil {
                    drifts[key]?.settle()
                }
            }
            if let floor { updatePlow(on: floor, delta: delta, automatic: settings.automaticPlowing, reduced: reduced) }
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

    func landing(at x: CGFloat, from oldY: CGFloat, to newY: CGFloat) -> (surface: SnowSurface, y: CGFloat)? {
        guard oldY <= newY else { return nil }
        for surface in surfaces where surface.visible.contains(where: { $0.contains(x) }) {
            let depth = surface.snowDepth(drift(on: surface.id), at: x)
            let y = surface.settlingY(at: x, depth: depth)
            if oldY <= y && y <= newY { return (surface, y) }
        }
        return nil
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
        for index in looseSnow.indices.reversed() {
            looseSnow[index].advance(delta, between: (floor.rect.minX + 0.5)...(floor.rect.maxX - 0.5))
            let grain = looseSnow[index]
            let x = grain.position.x - floor.rect.minX
            let crest = floor.rect.minY - (drifts[.floor]?.height(at: x) ?? 0)
            guard grain.velocity.dy > 0, grain.position.y + grain.radius >= crest else { continue }
            depositOnFloor(floor, at: x, mass: grain.mass, width: grain.radius * 3)
            looseSnow.remove(at: index)
        }
        for index in fallingSnow.indices.reversed() {
            let previousClump = fallingSnow[index]
            fallingSnow[index].advance(delta, within: floor.rect.width)
            let clump = fallingSnow[index]
            let contact = clump.contact
            let y = floor.rect.minY - (drifts[.floor]?.height(at: contact.x) ?? 0)
            guard contact.y >= y else { continue }
            if clump.pendingWindow != nil {
                // Only a confirmed disappearance can add snow to the floor.
                fallingSnow[index] = previousClump
                continue
            }
            let previous = previousClump.contact
            let travel = max(0.001, contact.y - previous.y)
            let fraction = min(1, max(0, (y - previous.y) / travel))
            let x = min(floor.rect.width, max(0, previous.x + (contact.x - previous.x) * fraction))
            depositOnFloor(floor, at: x, mass: clump.mass, width: clump.width)
            fallingSnow.remove(at: index)
            guard !reduced else { continue }
            for _ in 0..<min(7, Int(ceil(clump.mass * 0.42))) {
                impactPowder.append(SnowPowder(x: x + rng.inRange(-clump.width * 0.32, clump.width * 0.32),
                                               y: y - rng.inRange(1, 4), vx: rng.inRange(-76, 76),
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
        return Flake(x: rng.inRange(-12, size.width + 12),
                     y: scattered ? rng.inRange(0, size.height) : rng.inRange(-38, -3),
                     radius: 0.64 + pow(depth, 1.7) * rng.inRange(1.0, 3.15),
                     speed: 24 + depth * rng.inRange(40, 100),
                     phase: rng.inRange(0, .pi * 2), depth: depth)
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
