import AppKit

enum SnowArt {
    private static let powderGradient = gradient([0xffffff, 0xf7fbff, 0xe3eff7, 0xb9d2e4],
                                                  stops: [0, 0.28, 0.71, 1])
    private static let iceGradient = gradient([0xe8fbff, 0x9fcee6, 0xe3f6fd],
                                               stops: [0, 0.61, 1])
    private static let dockGradient = gradient([0xf8fcff, 0xe9f3fa, 0xc5d8e7], stops: [0, 0.59, 1])
    private static let cornerLight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                                colors: [NSColor(rgb: 0xf6fbff, alpha: 0.76).cgColor,
                                                         NSColor(rgb: 0xe4f1fc, alpha: 0.30).cgColor,
                                                         NSColor(rgb: 0xe4f1fc, alpha: 0).cgColor] as CFArray,
                                                locations: [0, 0.38, 1])!

    static func falling(_ clumps: [WindowSnowClump], ink: Ink) {
        let ctx = ink.ctx
        for clump in clumps {
            let half = clump.width / 2
            let depth = clump.thickness / 2
            let crest = (clump.shape - 0.5) * half
            let silhouette = CGMutablePath()
            silhouette.move(to: p(-half, depth * 0.16))
            silhouette.addCurve(to: p(crest, -depth),
                                control1: p(-half, -depth * 0.6), control2: p(crest - half * 0.48, -depth))
            silhouette.addCurve(to: p(half, -depth * 0.16),
                                control1: p(crest + half * 0.42, -depth), control2: p(half, -depth * 0.67))
            silhouette.addCurve(to: p(half * 0.48, depth * 0.85),
                                control1: p(half, depth * 0.54), control2: p(half * 0.76, depth * 0.74))
            silhouette.addCurve(to: p(-half, depth * 0.16),
                                control1: p(-half * 0.16, depth * 1.11), control2: p(-half * 0.99, depth * 0.74))
            silhouette.closeSubpath()

            ctx.saveGState()
            ctx.translateBy(x: clump.center.x, y: clump.center.y)
            ctx.rotate(by: clump.angle)
            ctx.addPath(silhouette)
            ctx.clip()
            ctx.drawLinearGradient(powderGradient, start: p(0, -depth), end: p(0, depth),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    static func loose(_ grains: [LooseSnow], ink: Ink) {
        for grain in grains {
            let radius = grain.radius
            let point = grain.position
            if grain.chunkRadius != nil && radius > 2.5 {
                drawFracture(at: point, radius: radius, rotation: grain.angle, ink: ink)
                continue
            }
            ink.oval(CGRect(x: point.x - radius, y: point.y - radius * 0.62, width: radius * 2, height: radius * 1.38),
                    0xc2d5ec, alpha: 0.92)
            ink.oval(CGRect(x: point.x - radius * 0.9, y: point.y - radius * 0.68, width: radius * 1.62, height: radius),
                    0xf9fcff, alpha: 0.94)
        }
    }

    private static let fractureOutline: CGPath = {
        let points = [p(-0.94, -0.18), p(-0.53, -0.72), p(0.06, -0.88), p(0.81, -0.47),
                      p(0.97, 0.09), p(0.49, 0.63), p(-0.09, 0.81), p(-0.77, 0.53)]
        let path = CGMutablePath()
        let last = points[points.count - 1]
        path.move(to: p((last.x + points[0].x) / 2, (last.y + points[0].y) / 2))
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            path.addQuadCurve(to: p((a.x + b.x) / 2, (a.y + b.y) / 2), control: a)
        }
        path.closeSubpath()
        return path
    }()

    private static func drawFracture(at point: CGPoint, radius: CGFloat, rotation: CGFloat, ink: Ink) {
        let ctx = ink.ctx
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.scaleBy(x: radius, y: radius)
        var transform = CGAffineTransform(rotationAngle: rotation)
        ctx.addPath(fractureOutline.copy(using: &transform) ?? fractureOutline)
        ctx.clip()
        ink.gradient(CGRect(x: -1.1, y: -1.1, width: 2.2, height: 2.2), [0xfbfefe, 0xebf5ff, 0xa7bccf])
        ink.circle(-0.32, -0.33, 0.26, 0xffffff, alpha: 0.57)
        ink.circle(0.30, 0.25, 0.18, 0xc2d6e9, alpha: 0.58)
        ctx.restoreGState()
    }

    static func drift(_ drift: SnowDrift, on surface: SnowSurface, icicles: Bool, ink: Ink) {
        if surface.id == .dock {
            dockDrift(drift, on: surface, ink: ink)
            return
        }
        let y = surface.rect.minY
        let left = surface.rect.minX
        let ctx = ink.ctx
        for range in surface.visible where range.upperBound - range.lowerBound > 1 {
            let start = max(0, Int((range.lowerBound - left) / SnowDrift.spacing))
            let end = min(drift.heights.count - 1, Int((range.upperBound - left) / SnowDrift.spacing))
            guard start <= end, (start...end).contains(where: { drift.heights[$0] > 0.48 }) else { continue }

            let leftCorner = WindowSnowCorner(drift: drift, surface: surface, span: range, left: true)
            let rightCorner = WindowSnowCorner(drift: drift, surface: surface, span: range, left: false)
            let leftX = leftCorner?.top.x ?? range.lowerBound
            let rightX = rightCorner?.top.x ?? range.upperBound
            let low = leftX - left
            let high = rightX - left
            var edge = [p(leftX, y - drift.height(at: low))]
            var thickness = y - edge[0].y
            for index in start...end {
                let x = drift.xAt(index)
                guard x > low, x < high else { continue }
                let amount = drift.height(at: x)
                thickness = max(thickness, amount)
                edge.append(p(left + x, y - amount))
            }
            let outer = drift.height(at: high)
            thickness = max(thickness, outer, leftCorner?.lipDepth ?? 0, rightCorner?.lipDepth ?? 0)
            edge.append(p(rightX, y - outer))
            guard thickness > 0.48 else { continue }

            if icicles && !surface.floor {
                drawIcicles(drift, between: leftX...rightX, left: left, y: y, ink: ink)
            }
            let outline = contour(edge)
            guard let section = outline.mutableCopy() else { continue }
            if let rightCorner {
                rightCorner.append(to: section, fromTop: true)
            } else {
                section.addLine(to: p(rightX, y))
            }
            section.addLine(to: leftCorner?.base ?? p(leftX, y))
            leftCorner?.append(to: section, fromTop: false)
            section.closeSubpath()

            let corners = [leftCorner, rightCorner].compactMap { $0 }
            if !corners.isEmpty {
                ctx.saveGState()
                ctx.setLineCap(.round)
                ctx.setLineWidth(1.55)
                ctx.setStrokeColor(NSColor(rgb: 0x1b3145, alpha: 0.27).cgColor)
                for corner in corners {
                    ctx.addPath(corner.contact)
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }

            ctx.saveGState()
            ctx.addPath(section)
            ctx.clip()
            ctx.drawLinearGradient(powderGradient, start: p(left, y - thickness - 0.45),
                                   end: p(left, y + 0.6), options: [.drawsAfterEndLocation])
            for corner in corners {
                ctx.drawLinearGradient(cornerLight,
                                       start: p(corner.edgeX - corner.inward * 5, y),
                                       end: p(corner.edgeX + corner.inward * (corner.radius + 7), y + 5),
                                       options: [.drawsBeforeStartLocation])
            }
            if thickness > 2.6 {
                let grain = CGMutablePath()
                var x = left + CGFloat((drift.seed >> 7) % 17) + floor(low / 14) * 14
                while x < range.upperBound - 2 {
                    if x >= range.lowerBound + 2 {
                        let depth = drift.height(at: x - left)
                        if depth > 2.5 {
                            let level = 0.42 + 0.22 * sin(x * 0.37)
                            let radius = 0.26 + 0.32 * abs(cos(x * 0.87))
                            grain.addEllipse(in: CGRect(x: x, y: y - depth * level,
                                                        width: radius * 2, height: radius * 2))
                        }
                    }
                    x += 14
                }
                ctx.addPath(grain)
                ctx.setFillColor(NSColor(rgb: 0xb5ccde, alpha: 0.26).cgColor)
                ctx.fillPath()

                ctx.setStrokeColor(NSColor(rgb: 0xffffff, alpha: 0.39).cgColor)
                ctx.setLineWidth(1.10)
                ctx.addPath(outline)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    private static func dockDrift(_ drift: SnowDrift, on surface: SnowSurface, ink: Ink) {
        let profile = DockSnowProfile(surface.rect, radius: surface.cornerRadius)
        let ctx = ink.ctx
        for span in surface.visible {
            let left = max(span.lowerBound, profile.supportedRange.lowerBound)
            let right = min(span.upperBound, profile.supportedRange.upperBound)
            guard right - left > 1 else { continue }
            var roof: [CGPoint] = []
            var contact: [CGPoint] = []
            let grains = CGMutablePath()
            let spacing: CGFloat = 3
            var thickness: CGFloat = 0
            let phase = CGFloat(drift.seed % 233)
            let samples = Array(stride(from: left, to: right, by: spacing)) + [right]
            for (index, x) in samples.enumerated() {
                let base = profile.contactY(at: x)
                let localX = surface.driftX(localX: x - surface.rect.minX, recordedWidth: drift.width)
                let powder = 0.90 + 0.11 * sin(localX * 0.16 + phase) + 0.05 * sin(localX * 0.52 + phase * 1.3)
                let depth = drift.height(at: localX) * profile.coverage(at: x) * powder
                thickness = max(thickness, depth)
                roof.append(p(x, base - depth))
                contact.append(p(x, base))
                if depth > 1.65 && index % 3 == 1 {
                    let radius = 0.26 + 0.31 * abs(sin(localX * 1.31 + phase))
                    let position = 0.28 + 0.38 * abs(cos(localX * 0.26 + phase))
                    grains.addEllipse(in: CGRect(x: x, y: base - depth * position, width: radius * 2, height: radius * 2))
                }
            }
            guard thickness > 0.34 else { continue }
            let snow = contour(roof)
            for point in contact.reversed() { snow.addLine(to: point) }
            snow.closeSubpath()
            ctx.saveGState()
            ctx.addPath(snow)
            ctx.clip()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setAlpha(0.94)
            let baseline = surface.rect.minY
            ctx.drawLinearGradient(dockGradient, start: p(left, baseline - thickness), end: p(left, baseline + 0.5),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.addPath(grains)
            ctx.setFillColor(NSColor(rgb: 0xffffff, alpha: 0.46).cgColor)
            ctx.fillPath()
            let feather = min(0.24, max(2, profile.radius * 0.46) / (right - left))
            if let mask = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(),
                                     colorComponents: [1, 0, 1, 1, 1, 1, 1, 0],
                                     locations: [0, feather, 1 - feather, 1], count: 4) {
                ctx.setAlpha(1)
                ctx.setBlendMode(.destinationIn)
                ctx.drawLinearGradient(mask, start: p(left, baseline), end: p(right, baseline), options: [])
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    private static func contour(_ points: [CGPoint]) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: points[0])
        let steps = zip(points, points.dropFirst()).map { ($1.y - $0.y) / max(0.001, $1.x - $0.x) }
        let slopes = points.indices.map { index -> CGFloat in
            if index == 0 { return steps[0] }
            if index == points.count - 1 { return steps[steps.count - 1] }
            let before = steps[index - 1]
            let after = steps[index]
            return before * after > 0 ? 2 * before * after / (before + after) : 0
        }
        for index in steps.indices {
            let first = points[index]
            let second = points[index + 1]
            let span = (second.x - first.x) / 3
            let top = min(first.y, second.y)
            let bottom = max(first.y, second.y)
            path.addCurve(to: second,
                          control1: p(first.x + span, min(bottom, max(top, first.y + span * slopes[index]))),
                          control2: p(second.x - span, min(bottom, max(top, second.y - span * slopes[index + 1]))))
        }
        return path
    }

    private static func drawIcicles(_ drift: SnowDrift, between range: ClosedRange<CGFloat>,
                                     left: CGFloat, y: CGFloat, ink: Ink) {
        var rng = SnowRandom(state: drift.seed ^ 0xfa45_ee01)
        var x = left + rng.inRange(15, 42)
        while x < range.upperBound - 4 {
            let length = rng.inRange(0.48, 1.16)
            let lean = rng.inRange(-1.2, 1.2)
            let width = rng.inRange(0.85, 2.05)
            let next = rng.inRange(34, 77)
            if x > range.lowerBound + 5 {
                let height = drift.height(at: x - left)
                if height > 4.6 {
                    let drop = min(11, height * length)
                    let shape = CGMutablePath()
                    shape.move(to: p(x - width, y - 0.55))
                    shape.addQuadCurve(to: p(x + lean, y + drop), control: p(x - width * 0.28, y + drop * 0.47))
                    shape.addQuadCurve(to: p(x + width, y - 0.5), control: p(x + width * 0.52, y + drop * 0.64))
                    shape.closeSubpath()
                    ink.ctx.saveGState()
                    ink.ctx.clip(to: shape.boundingBoxOfPath)
                    ink.ctx.addPath(shape)
                    ink.ctx.clip()
                    ink.ctx.setAlpha(0.79)
                    ink.ctx.drawLinearGradient(iceGradient, start: p(x - 1, y), end: p(x + 1, y + drop),
                                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    ink.ctx.restoreGState()
                }
            }
            x += next
        }
    }

    private static func gradient(_ colors: [UInt32], stops: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: colors.map { NSColor(rgb: $0).cgColor } as CFArray, locations: stops)!
    }
}

enum SnowplowArt {
    static let bladeNoseOffset: CGFloat = 8
    static let bladeReach: CGFloat = 22

    static func draw(_ pass: PlowPass, on floor: SnowSurface, ink: Ink) {
        let x = floor.rect.minX + pass.bladeX(width: floor.rect.width)
        let y = floor.rect.minY
        let ctx = ink.ctx
        ctx.saveGState()
        ctx.translateBy(x: x - pass.direction * PlowPass.bladeOffset, y: y)
        ctx.scaleBy(x: pass.direction * 0.82, y: 0.83)
        defer { ctx.restoreGState() }

        ink.oval(CGRect(x: -3, y: -3.4, width: 108, height: 5), 0x172c3e, alpha: 0.37)

        let track = CGRect(x: 3, y: -17.1, width: 73, height: 16.2)
        ink.rounded(track, 7.9, 0x263548)
        ink.rounded(track.insetBy(dx: 2, dy: 1.6), 6.4, 0x46536a)
        for tread in 0..<10 {
            let phase = (pass.distance * 1.16).truncatingRemainder(dividingBy: 6.5)
            let position = 9 + (CGFloat(tread) * 6.5 + phase).truncatingRemainder(dividingBy: 62)
            ink.line([p(position, -1.6), p(position + 0.65, -3.15)], 0x64748d, width: 0.88, alpha: 0.68)
        }
        for hub in 0..<4 {
            let xx = 12.1 + CGFloat(hub) * 18.0
            ink.circle(xx, -8.4, 6.7, 0xa6b9d3)
            ink.circle(xx - 0.48, -8.8, 5.0, 0xe3edfa)
            ink.circle(xx, -8.4, 2.55, 0x899dbb)
            let angle = pass.distance / 5.8 + CGFloat(hub)
            ink.circle(xx + cos(angle) * 3.48, -8.4 + sin(angle) * 3.48, 0.82, 0x68809d)
        }

        let body = CGRect(x: 2, y: -28.0, width: 76, height: 14.1)
        let cab = CGRect(x: 15, y: -52.0, width: 44, height: 29.2)
        ink.rounded(cab, 4.8, 0xb77524)
        ink.rounded(cab.insetBy(dx: 1.85, dy: 1.85), 3.75, 0xffda62)
        ink.line([p(20, -49.8), p(54, -49.8)], 0xffef99, width: 1.45)
        ink.rounded(CGRect(x: 21, y: -46.6, width: 32.6, height: 17.6), 3.0, 0xf5f8f4)
        ink.rounded(CGRect(x: 23.0, y: -44.5, width: 28.7, height: 13.6), 2.35, 0x8ec9f1)
        ink.poly([p(24, -43), p(33.9, -43), p(27, -32.3), p(24, -33)], 0xe4f5ff, alpha: 0.82)
        ink.line([p(36.3, -45), p(36.3, -31.3)], 0x548cb7, width: 0.8, alpha: 0.36)
        ink.rounded(body, 4.65, 0xc78d2f)
        ink.rounded(body.insetBy(dx: 1.5, dy: 1.5), 3.7, 0xffd74b)
        ink.line([p(6, -25.5), p(74, -25.5)], 0xfff09d, width: 1, alpha: 0.88)
        ink.rounded(CGRect(x: 6.1, y: -22.7, width: 3.8, height: 4.7), 1.5, 0xcd6353)
        ink.rounded(CGRect(x: 71, y: -22.7, width: 5.2, height: 4.7), 1.5, 0xfff9da)

        let beacon = 0.56 + 0.36 * sin(pass.distance * 0.059)
        ink.glow(34, -55, 13.5, 0xffac43, alpha: beacon * 0.68)
        ink.rounded(CGRect(x: 28.7, y: -58, width: 10.6, height: 6.75), 3.0, 0xa96525)
        ink.rounded(CGRect(x: 30.0, y: -57.2, width: 8.1, height: 4.5), 2.2, 0xffb741, alpha: 0.55 + beacon * 0.40)

        ink.line([p(76, -16.5), p(84, -12.0), p(88, -8.6)], 0x47586d, width: 3.7)
        let blade = CGMutablePath()
        blade.move(to: p(89, -24))
        blade.addQuadCurve(to: p(96, -4), control: p(84, -14))
        blade.addLine(to: p(100, -2.2))
        blade.addLine(to: p(91, -1.0))
        blade.addQuadCurve(to: p(84, -21), control: p(86, -8))
        blade.closeSubpath()
        ctx.addPath(blade)
        ctx.setFillColor(NSColor(rgb: 0x9cb6cf).cgColor)
        ctx.fillPath()
        ink.line([p(89, -22.5), p(89.2, -15), p(92.5, -8.6), p(98, -4.6)], 0xeaf4ff, width: 1.55)
        ink.line([p(92, -1.65), p(98, -2.8)], 0x587690, width: 1.8)

        if pass.load > 0.8 {
            let load = min(18, pass.load * 1.34)
            let mound = CGMutablePath()
            mound.move(to: p(94, 0.1))
            mound.addQuadCurve(to: p(99, -load), control: p(93, -load * 0.73))
            mound.addCurve(to: p(114 + load, 0.15), control1: p(106, -load * 1.01), control2: p(107 + load * 0.63, -1.6))
            mound.closeSubpath()
            ctx.saveGState()
            ctx.addPath(mound)
            ctx.clip()
            ink.gradient(CGRect(x: 92, y: -load - 1, width: 45, height: load + 2), [0xfcfdff, 0xe7f1fc, 0xc6dbf4])
            ctx.restoreGState()
        }
    }

    static func spray(_ powder: [SnowPowder], ink: Ink) {
        for grain in powder where grain.opacity > 0.02 {
            ink.circle(grain.x, grain.y, grain.radius * 1.55, 0xe1f4ff, alpha: grain.opacity * 0.18)
            ink.circle(grain.x, grain.y, grain.radius, 0xf6fcff, alpha: grain.opacity)
        }
    }
}
