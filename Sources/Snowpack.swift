import CoreGraphics

final class WindowSnowpack {
    private var drifts: [UInt32: SnowDrift] = [:]
    private var lastSettle: CGFloat?

    var isEmpty: Bool { drifts.isEmpty }

    subscript(id: UInt32) -> SnowDrift? {
        get { drifts[id] }
        set { drifts[id] = newValue }
    }

    func take(_ id: UInt32) -> SnowDrift? { drifts.removeValue(forKey: id) }

    func clear() {
        drifts.removeAll(keepingCapacity: true)
        lastSettle = nil
    }

    func settle(at time: CGFloat) {
        if let lastSettle, time - lastSettle < 0.18 { return }
        lastSettle = time
        for key in Array(drifts.keys) { drifts[key]?.settle() }
    }
}

struct SnowDrift {
    static let spacing: CGFloat = 6
    let seed: UInt64
    let isFloor: Bool
    let maximumDepth: CGFloat
    private(set) var width: CGFloat
    private(set) var heights: [CGFloat]
    private(set) var revision: UInt64 = 0
    private var nextLeftSpill: CGFloat = -.infinity
    private var nextRightSpill: CGFloat = -.infinity

    init(width: CGFloat, floor: Bool, seed: UInt64, maximumDepth: CGFloat? = nil) {
        self.width = width
        isFloor = floor
        self.seed = seed
        self.maximumDepth = maximumDepth ?? (floor ? 26 : 13)
        heights = Array(repeating: 0, count: max(1, Int(ceil(width / Self.spacing))))
    }

    var readyToPlow: Bool {
        var total: CGFloat = 0
        var covered = 0
        for height in heights {
            total += height
            if height >= 3.5 { covered += 1 }
        }
        return total >= 8.5 * CGFloat(heights.count) && covered * 5 >= heights.count * 3
    }

    mutating func resize(_ width: CGFloat) {
        guard self.width != width else { return }
        revision &+= 1
        self.width = width
        let count = max(1, Int(ceil(width / Self.spacing)))
        if heights.count > count { heights.removeLast(heights.count - count) }
        if heights.count < count { heights.append(contentsOf: repeatElement(0, count: count - heights.count)) }
    }

    mutating func land(at x: CGFloat, mass: CGFloat) {
        guard mass > 0 else { return }
        let position = min(CGFloat(heights.count - 1), max(0, x / Self.spacing - 0.5))
        let middle = Int(position.rounded())
        var kernels: [(Int, CGFloat)] = []
        var total: CGFloat = 0
        for index in max(0, middle - 2)...min(heights.count - 1, middle + 2) {
            let offset = abs(CGFloat(index) - position) / 2.75
            let weight = max(0, 1 - offset * offset)
            kernels.append((index, weight * weight))
            total += weight * weight
        }
        var changed = false
        for (index, weight) in kernels {
            let column = xAt(index)
            let phase = CGFloat(seed % 997) * 0.012
            let broad = sin(column / 31 + phase)
            let local = sin(column / 13 + phase * 1.7)
            let microterrain = isFloor ? 0.88 + 0.085 * broad + 0.035 * local
                : 0.80 + 0.12 * broad + 0.08 * local
            let rim = isFloor ? 1 : 0.52 + 0.48 * min(1, min(column, width - column) / 17)
            let capacity = maximumDepth * microterrain * rim
            let freeSpace = max(0, 1 - heights[index] / capacity)
            let added = min(capacity * freeSpace, mass * weight / total * (0.33 + 0.67 * freeSpace))
            heights[index] += added
            changed = changed || added > 0
        }
        if changed { revision &+= 1 }
    }

    mutating func settle() {
        guard heights.count > 1 else { return }
        // Loose grains move down a slope while shallow differences settle more slowly.
        // Visit each pair once using its original heights so there is no left-to-right bias.
        var left = heights[0]
        var changed = false
        for index in 1..<heights.count {
            let right = heights[index]
            let slope = left - right
            let loose = max(0, abs(slope) - (isFloor ? 1.3 : 1.6))
            let flow = slope * 0.073 + (slope < 0 ? -1 : 1) * loose * 0.17
            heights[index - 1] -= flow
            heights[index] += flow
            changed = changed || flow != 0
            left = right
        }
        if changed { revision &+= 1 }
    }

    mutating func depositImpact(at x: CGFloat, mass: CGFloat, width: CGFloat) {
        guard mass > 0 else { return }
        revision &+= 1
        let center = min(heights.count - 1, max(0, Int(x / Self.spacing)))
        let radius = max(2, Int(ceil(width / Self.spacing * 0.65)))
        let lower = max(0, center - radius)
        let upper = min(heights.count - 1, center + radius)
        let total = (lower...upper).reduce(CGFloat.zero) { sum, index in
            sum + CGFloat(radius + 1 - abs(index - center))
        }

        var remaining = mass
        for index in lower...upper {
            let weight = CGFloat(radius + 1 - abs(index - center)) / total
            let added = min(max(0, maximumDepth - heights[index]), mass * weight)
            heights[index] += added
            remaining -= added
        }
        // Excess slides out onto the nearest layer that can hold it.
        if remaining > 0.001 {
            for offset in 0..<heights.count {
                let candidates = offset == 0 ? [center] : [center - offset, center + offset]
                for index in candidates where heights.indices.contains(index) {
                    let added = min(max(0, maximumDepth - heights[index]), remaining)
                    heights[index] += added
                    remaining -= added
                    if remaining <= 0.001 { return }
                }
            }
        }
    }

    func xAt(_ index: Int) -> CGFloat { min(width, (CGFloat(index) + 0.5) * Self.spacing) }

    mutating func spillFromCorner(left: Bool, at time: CGFloat) -> CGFloat {
        guard !isFloor, heights.count >= 5, time >= (left ? nextLeftSpill : nextRightSpill) else { return 0 }
        let outer = left ? 0 : heights.count - 1
        let inward = left ? 1 : -1
        let edge = heights[outer]
        let shoulder = heights[outer + inward] * 0.62 + heights[outer + inward * 2] * 0.38
        guard edge >= maximumDepth * 0.33, shoulder >= maximumDepth * 0.56,
              edge * 0.38 + shoulder * 0.62 >= maximumDepth * 0.52 else { return 0 }

        var mass: CGFloat = 0
        for (offset, fraction) in [CGFloat(0.42), 0.28, 0.15].enumerated() {
            let index = outer + inward * offset
            let removed = min(heights[index] * fraction, max(0, heights[index] - maximumDepth * 0.27))
            heights[index] -= removed
            mass += removed
        }
        let cooldown = 3.4 + CGFloat(seed % 11) * 0.16 + (left ? 0 : 0.45)
        if left { nextLeftSpill = time + cooldown }
        else { nextRightSpill = time + cooldown }
        revision &+= 1
        return mass
    }

    mutating func dislodge(at index: Int, pressure: CGFloat, limit: CGFloat = .infinity) -> CGFloat {
        guard pressure > 0 else { return 0 }
        let removed = min(limit, min(heights[index] * 0.62, 2.9) * pressure)
        heights[index] -= removed
        if removed > 0 { revision &+= 1 }
        return removed
    }

    func height(at x: CGFloat) -> CGFloat {
        let position = min(CGFloat(heights.count - 1), max(0, x / Self.spacing - 0.5))
        let left = Int(position)
        let right = min(left + 1, heights.count - 1)
        let height = heights[left] + (heights[right] - heights[left]) * (position - CGFloat(left))
        guard !isFloor else { return height }
        let ratio = min(1, max(0, min(x, width - x) / 13))
        return height * ratio * ratio * (3 - 2 * ratio)
    }

    mutating func scrape(from start: CGFloat, to end: CGFloat) -> CGFloat {
        let low = min(start, end)
        let high = max(start, end)
        guard low < high, high >= 0, low <= width else { return 0 }
        let first = max(0, Int(floor(low / Self.spacing)))
        let last = min(heights.count - 1, Int(floor(high / Self.spacing)))
        guard first <= last else { return 0 }

        var removed: CGFloat = 0
        for index in first...last where (low...high).contains(xAt(index)) {
            let dust = min(heights[index], 0.24)
            removed += heights[index] - dust
            heights[index] = dust
        }
        if removed > 0 { revision &+= 1 }
        return removed
    }

    mutating func leaveDust() {
        guard heights.contains(where: { $0 > 0.24 }) else { return }
        revision &+= 1
        for index in heights.indices {
            heights[index] = min(heights[index], 0.24)
        }
    }
}

struct PlowPass {
    static let approach: CGFloat = 12
    static let exit: CGFloat = 108
    static let bladeOffset: CGFloat = 74

    let direction: CGFloat
    private(set) var distance: CGFloat = 0
    private(set) var load: CGFloat = 0

    func bladeX(width: CGFloat) -> CGFloat {
        direction > 0 ? distance - Self.approach : width - distance + Self.approach
    }

    func isComplete(width: CGFloat) -> Bool {
        distance >= width + Self.approach + Self.exit
    }

    func speed(width: CGFloat) -> CGFloat { min(300, max(185, width / 6.8)) }

    mutating func advance(_ delta: CGFloat, width: CGFloat) {
        distance += speed(width: width) * delta
        load *= exp(-delta * 5.2)
    }

    mutating func push(_ removed: CGFloat) {
        load = min(20, load + removed * 0.46)
    }
}

struct SnowPowder {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var age: CGFloat = 0
    var life: CGFloat
    var radius: CGFloat

    mutating func step(_ delta: CGFloat) {
        x += vx * delta
        y += vy * delta
        vx *= exp(-delta * 1.6)
        vy += 105 * delta
        age += delta
    }

    var opacity: CGFloat {
        let fraction = age / life
        return 0.66 * min(1, fraction * 13) * max(0, 1 - fraction)
    }
}
