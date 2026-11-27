import CoreGraphics
import Foundation

struct LightStrand: Codable, Equatable {
    struct Attachment: Codable, Equatable {
        let ornament: UUID
        let position: CGPoint
    }

    struct Host {
        let ornament: Ornament
        let frame: CGRect

        private func rotated(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
            point.applying(CGAffineTransform(translationX: frame.midX, y: frame.midY)
                .rotated(by: angle)
                .translatedBy(x: -frame.midX, y: -frame.midY))
        }

        func attachment(at point: CGPoint) -> Attachment? {
            guard frame.width > 0, frame.height > 0, ornament.kind != .lights else { return nil }
            let unturned = rotated(point, by: -ornament.rotation * .pi / 180)
            var flat = ornament
            flat.rotation = 0
            guard flat.interactionFrame(in: frame).insetBy(dx: -8, dy: -8).contains(unturned) else { return nil }
            return Attachment(ornament: ornament.id,
                              position: p((unturned.x - frame.minX) / frame.width, (unturned.y - frame.minY) / frame.height))
        }

        func point(for attachment: Attachment) -> CGPoint {
            let position = attachment.position
            let unturned = p(frame.minX + position.x * frame.width, frame.minY + position.y * frame.height)
            return rotated(unturned, by: ornament.rotation * .pi / 180)
        }
    }

    var hooks: [CGPoint]
    var slack: CGFloat = 1
    var attachments: [Int: Attachment]?

    var attached: Bool { attachments?.isEmpty == false }

    func anchors(in size: CGSize) -> [CGPoint] {
        hooks.prefix(22).map { p($0.x * size.width, $0.y * size.height) }
    }

    func bounds(in size: CGSize, bulbScale: CGFloat) -> CGRect {
        Self.bounds(of: anchors(in: size), bulbScale: bulbScale)
    }

    static func bounds(of anchors: [CGPoint], bulbScale: CGFloat) -> CGRect {
        guard let first = anchors.first else { return .null }
        let xs = anchors.map(\.x), ys = anchors.map(\.y)
        let left = xs.min() ?? first.x, right = xs.max() ?? first.x
        let top = ys.min() ?? first.y, bottom = ys.max() ?? first.y
        return CGRect(x: left - 18, y: top - 22, width: right - left + 36,
                      height: bottom - top + 122 + bulbScale * 25)
    }

    static func attachments(for points: [CGPoint], on hosts: [Host]) -> [Int: Attachment] {
        var result: [Int: Attachment] = [:]
        for (index, point) in points.prefix(22).enumerated() {
            if let attachment = hosts.reversed().lazy.compactMap({ $0.attachment(at: point) }).first {
                result[index] = attachment
            }
        }
        return result
    }

    func resolvedAnchors(free points: [CGPoint], hosts: [UUID: Host]) -> [CGPoint]? {
        var resolved = points
        for (index, attachment) in attachments ?? [:] where resolved.indices.contains(index) {
            guard let host = hosts[attachment.ornament] else { return nil }
            resolved[index] = host.point(for: attachment)
        }
        return resolved
    }

    static func points(_ anchors: [CGPoint], slack: CGFloat, at time: Double, wind: CGFloat,
                       spacing: CGFloat, brush: CGPoint? = nil) -> [CGPoint] {
        var points: [CGPoint] = []
        for (a, b) in zip(anchors, anchors.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            let divisions = min(110, max(2, Int(length / spacing)))
            let droop = min(88, max(0, slack) * abs(dx) * 0.13)
            let middle = p((a.x + b.x) / 2, (a.y + b.y) / 2 + droop)
            let response: CGFloat = if let brush, time != 0 {
                max(0, 1 - hypot(brush.x - middle.x, brush.y - middle.y) / max(54, length * 0.55)) * 7
            } else { 0 }
            let sway = time == 0 ? 0 : sin(time * 2.3 + a.x * 0.013) * (2 + 5 * abs(wind) + response)
            for index in 0...divisions where points.isEmpty || index > 0 {
                let t = CGFloat(index) / CGFloat(divisions)
                let sag = 4 * t * (1 - t)
                points.append(p(a.x + dx * t + sway * sag, a.y + dy * t + (droop + sway * 0.35) * sag))
            }
        }
        return points
    }
}
