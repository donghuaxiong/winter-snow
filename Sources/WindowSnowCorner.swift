import CoreGraphics

/// Extends the edge of a snowdrift along the rounded top of a real window.
struct WindowSnowCorner {
    private struct Curve {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint

        func add(to path: CGMutablePath, reversed: Bool = false) {
            if reversed {
                path.addCurve(to: start, control1: control2, control2: control1)
            } else {
                path.addCurve(to: end, control1: control1, control2: control2)
            }
        }
    }

    let top: CGPoint
    let base: CGPoint
    let lipDepth: CGFloat
    let edgeX: CGFloat
    let inward: CGFloat
    let radius: CGFloat
    let contact: CGPath
    private let curves: [Curve]

    init?(drift: SnowDrift, surface: SnowSurface, span: ClosedRange<CGFloat>, left: Bool) {
        let radius = min(surface.cornerRadius, surface.rect.width / 4)
        let edgeX = left ? surface.rect.minX : surface.rect.maxX
        let boundary = left ? span.lowerBound : span.upperBound
        let join = radius * 1.62
        guard radius > 0, abs(boundary - edgeX) < 0.01,
              span.upperBound - span.lowerBound > join + 2 else { return nil }

        let inward: CGFloat = left ? 1 : -1
        let y = surface.rect.minY
        func depth(_ distance: CGFloat) -> CGFloat {
            drift.height(at: edgeX + inward * distance - surface.rect.minX)
        }

        let lip = depth(radius)
        let near = depth(radius * 0.28)
        let shoulder = depth(join)
        let buildup = near * 0.45 + lip * 0.40 + shoulder * 0.15
        guard buildup > 0.62, near > 0.42, lip > 0.42 else { return nil }

        let amount = min(1, max(0, (buildup - 0.62) / 5.8))
        let growth = amount * amount * (3 - 2 * amount)
        let variation = CGFloat((drift.seed >> (left ? 11 : 28)) % 101) / 100
        let lipDepth = min(drift.maximumDepth + 1, lip + growth * (1 + variation * 0.75))
        let arcLength = radius * .pi / 2
        // A dusting ends on the bend. A heavier lip reaches the side and slumps down it.
        let length = arcLength * (0.56 + 0.44 * growth)
            + min(radius * 0.68, 8 + 4 * variation) * growth * growth
        let top = p(edgeX + inward * join, y - shoulder)
        let base = p(top.x, y)

        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        for index in 0...10 {
            // Cluster samples by the rounded tip so it stays smooth at desktop scale.
            let progress = sin(CGFloat(index) * .pi / 20)
            let travelled = length * progress
            let angle = min(CGFloat.pi / 2, travelled / radius)
            let outwardX = sin(angle)
            let outwardY = cos(angle)
            let x = radius * (1 - outwardX)
            let guideY = radius * (1 - outwardY) + max(0, travelled - arcLength)
            let tip = pow(progress, 8)
            let roundTip = sqrt(max(0, 1 - progress * progress)) * (1 + 0.52 * tip)
            let taper = 1 - (0.49 + 0.11 * variation) * pow(progress, 1.45)
            let roll = 1 + 0.13 * growth * pow(sin(.pi * progress), 2)
            let thickness = lipDepth * roundTip * taper * roll
            let contactInset = (0.42 + growth * (0.53 + 1.4 * tip)) * roundTip

            outer.append(p(edgeX + inward * (x - outwardX * thickness), y + guideY - outwardY * thickness))
            inner.append(p(edgeX + inward * (x + outwardX * contactInset), y + guideY + outwardY * contactInset))
        }

        let bend = Self.curves(along: outer + inner.dropLast().reversed(), inward: inward)
        let roofRun = (join - radius) / 3
        let slope = (depth(join + 2) - depth(join - 2)) / 4
        let roof = Curve(start: top, control1: p(top.x - inward * roofRun, top.y + roofRun * slope),
                         control2: p(outer[0].x + inward * roofRun, outer[0].y), end: outer[0])
        let underside = Curve(start: inner[0], control1: p(inner[0].x + inward * roofRun, inner[0].y),
                              control2: p(base.x - inward * roofRun, base.y), end: base)
        let contact = CGMutablePath()
        contact.move(to: outer[outer.count - 1])
        for curve in bend.dropFirst(outer.count - 1) { curve.add(to: contact) }
        underside.add(to: contact)

        self.top = top
        self.base = base
        self.lipDepth = lipDepth
        self.edgeX = edgeX
        self.inward = inward
        self.radius = radius
        self.contact = contact
        curves = [roof] + bend + [underside]
    }

    func append(to path: CGMutablePath, fromTop: Bool) {
        if fromTop {
            for curve in curves { curve.add(to: path) }
        } else {
            for curve in curves.reversed() { curve.add(to: path, reversed: true) }
        }
    }

    private static func curves(along points: [CGPoint], inward: CGFloat) -> [Curve] {
        let tangents = points.indices.map { index -> CGPoint in
            if index == 0 { return p(-inward, 0) }
            if index == points.count - 1 { return p(inward, 0) }
            let previous = points[index - 1]
            let next = points[index + 1]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let distance = max(0.001, hypot(dx, dy))
            return p(dx / distance, dy / distance)
        }
        return (0..<(points.count - 1)).map { index in
            let start = points[index]
            let end = points[index + 1]
            let arm = hypot(end.x - start.x, end.y - start.y) / 3
            let first = tangents[index]
            let second = tangents[index + 1]
            return Curve(start: start, control1: p(start.x + arm * first.x, start.y + arm * first.y),
                         control2: p(end.x - arm * second.x, end.y - arm * second.y), end: end)
        }
    }
}
