import AppKit

enum DecorationArt {
    static func draw(_ ornament: Ornament, in rect: CGRect, with ink: Ink, time: Double, now: Date) {
        let size = ornament.kind.size
        ink.ctx.saveGState()
        ink.ctx.translateBy(x: rect.midX, y: rect.midY)
        ink.ctx.rotate(by: ornament.rotation * .pi / 180)
        ink.ctx.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
        ink.ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        let accent = ornament.colors[0]
        switch ornament.kind {
        case .snowman: SnowmanArt.draw(ornament, ink: ink)
        case .tree: tree(ink, ornament)
        case .lantern: lantern(ink, accent: accent, time: time)
        case .gift: gift(ink, accent: accent)
        case .wreath: wreath(ink, colors: ornament.colors)
        case .calendar: calendar(ink, ornament, now: now)
        case .lights:
            let points = (0...24).map { i -> CGPoint in
                let fraction = CGFloat(i) / 24
                return p(10 + fraction * 240, 12 + sin(fraction * .pi) * 18)
            }
            lights(ink, points: points, ornament: ornament, time: time)
        }
        ink.ctx.restoreGState()
    }

    static func windowLights(_ ornament: Ornament, rect: CGRect, ink: Ink, time: Double) {
        let box = rect.insetBy(dx: 4, dy: 3)
        let spacing = max(12, 19 * ornament.scale)
        let steps = min(180, max(2, Int(box.width / spacing)))
        let y = box.minY + 3
        var points: [CGPoint] = []
        if ornament.placement == .windowTop {
            for i in 0...steps {
                let fraction = CGFloat(i) / CGFloat(steps)
                points.append(p(box.minX + box.width * fraction, y + sin(fraction * .pi) * min(box.width / 25, 14)))
            }
        } else {
            let vertical = min(100, max(2, Int(box.height / spacing)))
            for i in 0..<steps { points.append(p(box.minX + box.width * CGFloat(i) / CGFloat(steps), y)) }
            for i in 0..<vertical {
                points.append(p(box.maxX, y + (box.maxY - y) * CGFloat(i) / CGFloat(vertical)))
            }
            for i in 0..<steps { points.append(p(box.maxX - box.width * CGFloat(i) / CGFloat(steps), box.maxY)) }
            for i in 0...vertical {
                points.append(p(box.minX, box.maxY - (box.maxY - y) * CGFloat(i) / CGFloat(vertical)))
            }
        }
        lights(ink, points: points, ornament: ornament, time: time, scale: ornament.scale)
    }

    private static func lights(_ ink: Ink, points: [CGPoint], ornament: Ornament, time: Double, scale: CGFloat = 1) {
        let colors = ornament.colors
        ink.line(points, 0x203637, width: 1.45 * scale, alpha: 0.96)
        for (index, point) in points.enumerated() {
            let phase = time * 3.3 + Double(index) * 1.83
            let strength: CGFloat
            switch ornament.lightMotion {
            case .steady: strength = 0.94
            case .twinkle: strength = 0.63 + sin(phase) * 0.33
            case .chase: strength = (index + Int(time * 7)).isMultiple(of: 5) ? 0.98 : 0.39
            }
            let color = colors[index % colors.count]
            let x = point.x
            let y = point.y + 4 * scale
            let radius: CGFloat = ornament.bulb == .mini ? 2.5 : ornament.bulb == .retro ? 5.0 : 3.5
            ink.circle(x, y, (radius + 3.5) * scale, color, alpha: 0.11 * strength)
            ink.circle(x, y, (radius + 1.5) * scale, color, alpha: 0.19 * strength)
            switch ornament.bulb {
            case .globe, .mini:
                ink.circle(x, y, radius * scale, color, alpha: strength)
            case .fairy:
                if strength > 0.5 {
                    ink.star(x, y, 5.3 * scale, color, points: 4)
                } else {
                    ink.circle(x, y, 2.2 * scale, color, alpha: strength)
                }
            case .retro:
                ink.oval(CGRect(x: x - 3.3 * scale, y: y - 3.3 * scale, width: 6.6 * scale, height: 10 * scale),
                         color, alpha: strength)
            case .icicle:
                let length = CGFloat(7 + index % 4 * 3) * scale
                ink.line([point, p(x, y + length)], color, width: 1.5 * scale, alpha: strength)
                ink.circle(x, y + length, 1.65 * scale, color, alpha: strength)
            }
            if ornament.bulb != .icicle {
                ink.circle(x - scale, y - 0.8 * scale, 0.8 * scale, 0xfff9e9, alpha: strength)
            }
        }
    }

    private static func tree(_ ink: Ink, _ ornament: Ornament) {
        let colors = ornament.colors
        ink.oval(CGRect(x: 13, y: 166, width: 128, height: 16), 0x193947, alpha: 0.63)
        ink.rounded(CGRect(x: 69, y: 142, width: 17, height: 32), 4, 0x976858)
        for index in (0..<5).reversed() {
            let width = 27 + CGFloat(index) * 10
            let y = 42 + CGFloat(index) * 23
            ink.poly([p(77, y - 22), p(77 - width, y + 26), p(73 - width * 0.33, y + 20),
                      p(77, y + 32), p(79 + width * 0.37, y + 20), p(77 + width, y + 24)],
                     index.isMultiple(of: 2) ? 0x316758 : 0x3d7964)
            ink.line([p(77 - width * 0.79, y + 23), p(72 - width * 0.38, y + 17), p(75, y + 22),
                      p(80 + width * 0.27, y + 18), p(78 + width * 0.72, y + 22)], 0xa4deca, width: 1.3, alpha: 0.42)
            guard ornament.extras else { continue }
            for bulb in 0..<(index + 2) {
                let x = 77 + (CGFloat(bulb) / CGFloat(index + 1) - 0.5) * width * 1.44
                let bulbY = y + 15 + sin(CGFloat(bulb) * 0.8) * 5
                let color = colors[(bulb + index) % colors.count]
                ink.circle(x, bulbY, 5.5, color, alpha: 0.18)
                ink.circle(x, bulbY, 2.7, color)
                ink.circle(x - 0.9, bulbY - 0.8, 0.8, 0xffffff, alpha: 0.86)
            }
        }
        ink.glow(77, 20, 22, 0xffcd7e, alpha: 0.49)
        ink.star(77, 21, 12, 0xffd58d)
    }

    private static func lantern(_ ink: Ink, accent: UInt32, time: Double) {
        ink.glow(40, 58, 38, accent, alpha: 0.27)
        ink.rounded(CGRect(x: 20, y: 25, width: 40, height: 61), 6, 0x24364a)
        ink.rounded(CGRect(x: 24, y: 31, width: 32, height: 49), 4, 0x664b48)
        ink.glow(40, 60, 17, 0xffbd70, alpha: 0.72)
        ink.rounded(CGRect(x: 36, y: 63, width: 8, height: 13), 2, 0xffddb0)
        let flame = sin(time * 5.9) * 1.2
        ink.oval(CGRect(x: 37, y: 51 + flame, width: 6, height: 10 - flame), 0xffc46e)
        ink.rounded(CGRect(x: 16, y: 84, width: 48, height: 7), 3, 0x304357)
        ink.poly([p(17, 31), p(26, 20), p(54, 20), p(63, 31)], 0x304357)
        ink.line([p(31, 21), p(34, 12), p(46, 12), p(49, 21)], 0xa18470, width: 2)
        ink.line([p(40, 32), p(40, 79)], 0x27384a, width: 1.1, alpha: 0.62)
    }

    private static func gift(_ ink: Ink, accent: UInt32) {
        ink.oval(CGRect(x: 7, y: 70, width: 69, height: 8), 0x192f42, alpha: 0.53)
        ink.rounded(CGRect(x: 12, y: 31, width: 60, height: 40), 4, 0x9b5668)
        ink.rounded(CGRect(x: 8, y: 25, width: 68, height: 13), 4, 0xc77582)
        ink.rounded(CGRect(x: 37, y: 25, width: 10, height: 46), 2, accent)
        ink.line([p(42, 25), p(26, 20), p(22, 14), p(28, 10), p(35, 15), p(42, 25),
                  p(50, 15), p(58, 12), p(61, 17), p(55, 22), p(42, 25)], accent, width: 3)
    }

    private static func wreath(_ ink: Ink, colors: [UInt32]) {
        for index in 0..<65 {
            let angle = CGFloat(index) * .pi * 2 / 65
            let x = 51 + cos(angle) * 34
            let y = 52 + sin(angle) * 34
            ink.circle(x, y, 8.4, index.isMultiple(of: 2) ? 0x447e66 : 0x2a6658)
            if index.isMultiple(of: 5) {
                ink.circle(x + 2.5, y - 1.8, 2.7, colors[index % colors.count])
                ink.circle(x + 1.8, y - 2.5, 0.7, 0xffffff, alpha: 0.67)
            }
        }
        let accent = colors[0]
        ink.poly([p(49, 32), p(40, 48), p(34, 44), p(45, 29)], accent)
        ink.poly([p(50, 30), p(64, 45), p(59, 47), p(49, 34)], accent)
        ink.oval(CGRect(x: 32, y: 22, width: 21, height: 12), accent)
        ink.oval(CGRect(x: 49, y: 22, width: 20, height: 12), accent)
        ink.circle(50, 29, 5, 0xffe2a1)
    }

    static func calendarDoorRect(_ day: Int) -> CGRect {
        let i = day - 1
        return CGRect(x: 17 + (i % 5) * 48, y: 51 + (i / 5) * 31, width: 45, height: 28)
    }

    static func calendarDay(at point: CGPoint) -> Int? {
        (1...25).first { calendarDoorRect($0).contains(point) }
    }

    private static func calendar(_ ink: Ink, _ ornament: Ornament, now: Date) {
        let frame = CGRect(x: 5, y: 5, width: 262, height: 213)
        ink.rounded(frame, 18, 0x142d3e)
        ink.rounded(frame.insetBy(dx: 2, dy: 2), 16, 0x1b3b4b)
        ink.line([p(18, 43), p(253, 43)], 0x567682, alpha: 0.49)
        ink.text("DECEMBER", at: p(136, 28), size: 12, color: 0xffdb9e, weight: .semibold)
        ink.star(30, 28, 5, 0xffd993, points: 4)
        ink.star(242, 28, 5, 0xffd993, points: 4)
        let available = ornament.availableDoors(on: now)
        let surprises = ["star.fill", "gift.fill", "snowflake", "flame.fill", "moon.stars.fill", "bell.fill", "tree.fill", "sparkles"]
        for day in 1...25 {
            let rect = calendarDoorRect(day)
            let opened = ornament.opened.contains(day)
            ink.rounded(rect, 5, opened ? 0x584b45 : day <= available ? 0x375663 : 0x274553)
            if opened {
                let symbol = surprises[(day - 1) % surprises.count]
                if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                   let configured = image.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)
                    .applying(.init(paletteColors: [NSColor(rgb: 0xffdb9e)]))) {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ink.ctx, flipped: true)
                    configured.draw(in: CGRect(x: rect.midX - configured.size.width / 2,
                                               y: rect.midY - configured.size.height / 2,
                                               width: configured.size.width, height: configured.size.height),
                                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    ink.star(rect.midX, rect.midY, 6, 0xffdb9e, points: 4)
                }
            } else {
                ink.text(String(day), at: p(rect.midX, rect.midY), size: 10,
                         color: day <= available ? 0xffe4b7 : 0x9ab2bc)
            }
        }
    }
}
