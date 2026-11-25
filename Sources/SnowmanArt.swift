import AppKit

enum SnowmanArt {
    static let baseline: CGFloat = 150
    static let workshopScale: CGFloat = 0.62
    static let radii: [CGFloat] = [32, 24, 17]
    private static let frost = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [0xffffff, 0xf8fcff, 0xe6f1fc, 0xb7d0ed, 0x9eb8d9].map { NSColor(rgb: UInt32($0)).cgColor } as CFArray,
        locations: [0, 0.27, 0.60, 0.89, 1]
    )!
    private static let grainColors = [NSColor(rgb: 0xadc9ea, alpha: 0.16).cgColor,
                                      NSColor(rgb: 0xffffff, alpha: 0.35).cgColor]
    private static let grains: [[CGPath]] = (0..<3).map { tone in
        var random = SnowRandom(state: 57_421)
        let paths = [CGMutablePath(), CGMutablePath()]
        let shift = CGFloat(tone) * 0.11
        for index in 0..<48 {
            let x = random.inRange(-0.94, 0.94) + shift
            let y = random.inRange(-0.94, 0.94)
            let r = random.inRange(0.017, 0.11)
            paths[index.isMultiple(of: 3) ? 0 : 1].addEllipse(
                in: CGRect(x: x, y: y, width: r * 2, height: r * 1.55)
            )
        }
        return paths
    }

    static func gap(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        (first + second) * 0.825
    }

    static func ball(_ center: CGPoint, radius: CGFloat, ink: Ink, tone: Int = 0) {
        let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ink.ctx.saveGState()
        ink.ctx.addEllipse(in: bounds)
        ink.ctx.clip()
        let highlight = p(center.x - radius * 0.29, center.y - radius * 0.39)
        ink.ctx.drawRadialGradient(frost, startCenter: highlight, startRadius: 0,
                                   endCenter: center, endRadius: radius * 1.12, options: [.drawsAfterEndLocation])
        ink.ctx.translateBy(x: center.x, y: center.y)
        ink.ctx.scaleBy(x: radius, y: radius)
        for (path, color) in zip(grains[tone % 3], grainColors) {
            ink.ctx.addPath(path)
            ink.ctx.setFillColor(color)
            ink.ctx.fillPath()
        }
        ink.ctx.restoreGState()
    }

    static func draw(_ ornament: Ornament, ink: Ink) {
        let costume = ornament.costume
        let x: CGFloat = 62
        let r = radii
        let baseY = baseline - r[0]
        let bodyY = ornament.snowballs == 2 ? baseY : baseY - gap(r[0], r[1])
        let headY = bodyY - gap(ornament.snowballs == 2 ? r[0] : r[1], r[2])

        ink.oval(CGRect(x: x - 27, y: baseline - 2.2, width: 54, height: 5.6), 0x112b4b, alpha: 0.25)
        if costume.arms {
            ink.line([p(x - 19, bodyY + 4), p(x - 35, bodyY - 7), p(x - 42, bodyY - 18)], 0x634539, width: 2.8)
            ink.line([p(x - 36, bodyY - 8), p(x - 45, bodyY - 10)], 0x8a654c, width: 2.0)
            ink.line([p(x + 19, bodyY + 3), p(x + 36, bodyY - 8), p(x + 46, bodyY - 15)], 0x634539, width: 2.8)
            ink.line([p(x + 37, bodyY - 9), p(x + 37, bodyY - 18)], 0x8a654c, width: 1.9)
        }
        ball(p(x, baseY), radius: r[0], ink: ink, tone: 0)
        if ornament.snowballs != 2 { ball(p(x, bodyY), radius: r[1], ink: ink, tone: 1) }
        ball(p(x, headY), radius: r[2], ink: ink, tone: 2)
        if costume.buttons {
            for (index, offset) in [CGFloat(-0.8), 7.8, 16.2].enumerated() {
                ink.circle(x + sin(CGFloat(index) * 1.15) * 1.4, bodyY + offset, 1.9 - CGFloat(index) * 0.12, 0x283949)
            }
        }
        drawScarf(costume.scarf, palette: ornament.colors[0], at: p(x, headY + 14.5), ink: ink)
        drawFace(costume.face, at: p(x, headY), ink: ink)
        drawHat(ornament.hat, at: p(x, headY - 10.5), accent: ornament.colors[0], ink: ink)
    }

    static func drawFace(_ face: SnowmanFace, at position: CGPoint, ink: Ink) {
        guard face != .plain else { return }
        let x = position.x
        let y = position.y
        if face == .smile {
            ink.circle(x - 5.3, y - 3.35, 1.62, 0x233143)
            ink.circle(x + 5.3, y - 3.35, 1.62, 0x233143)
        } else {
            let bow: CGFloat = face == .happy ? -1.4 : 1.45
            for offset: CGFloat in [-5.6, 5.6] {
                let center = x + offset
                ink.line([p(center - 2.2, y - 3), p(center, y - 3 + bow), p(center + 2.2, y - 3)], 0x344052, width: 1.16)
            }
        }
        ink.oval(CGRect(x: x - 11.6, y: y + 0.5, width: 4.8, height: 3.1), 0xf28784, alpha: 0.49)
        ink.oval(CGRect(x: x + 7, y: y + 0.5, width: 4.8, height: 3.1), 0xf28784, alpha: 0.49)
        ink.poly([p(x - 1.8, y - 0.2), p(x + 8.4, y + 2.2), p(x - 1.4, y + 4.1)], 0xee8a40)
        ink.line([p(x - 0.8, y + 0.6), p(x + 5.4, y + 1.8)], 0xffbf79, width: 0.72)
        if face == .sleepy {
            ink.circle(x, y + 7.0, 1.4, 0x526175)
        } else {
            for index in 0..<5 {
                let offset = CGFloat(index - 2)
                ink.circle(x + offset * 2.25, y + 8.8 - offset * offset * 0.51, 0.78, 0x344151)
            }
        }
    }

    static func drawScarf(_ scarf: SnowmanScarf, palette: UInt32, at position: CGPoint, ink: Ink) {
        guard scarf != .none else { return }
        let color: UInt32
        let highlight: UInt32
        switch scarf {
        case .red: (color, highlight) = (0xc92c48, 0xfa6b78)
        case .blue: (color, highlight) = (0x367db5, 0x80c9ed)
        case .green: (color, highlight) = (0x267866, 0x72c7a9)
        case .plaid: (color, highlight) = (0x82526f, 0xf1b888)
        default: (color, highlight) = (palette, 0xf9f3ea)
        }
        let x = position.x
        let y = position.y
        ink.line([p(x + 7, y + 2.7), p(x + 10, y + 9), p(x + 10.5, y + 20)], color, width: 5.7)
        ink.line([p(x + 9.5, y + 9), p(x + 10.2, y + 17.4)], highlight, width: 1.0, alpha: 0.66)
        ink.line([p(x - 13, y - 2), p(x - 6, y + 1.8), p(x + 4.5, y + 2.6), p(x + 13, y - 1.2)],
                 color, width: 6.0)
        ink.line([p(x - 11.7, y - 2.8), p(x - 5.6, y + 0.1), p(x + 4.8, y + 0.7), p(x + 11, y - 1.7)],
                 highlight, width: 1.22, alpha: 0.70)
        if scarf == .plaid {
            for offset in [-9.0, -4, 1, 6] {
                ink.line([p(x + offset, y - 1.2), p(x + offset + 0.8, y + 3.4)], 0xffcf91, width: 0.8)
            }
        }
    }

    static func drawHat(_ hat: Hat, at position: CGPoint, accent: UInt32, ink: Ink) {
        guard hat != .none else { return }
        ink.ctx.saveGState()
        ink.ctx.translateBy(x: position.x, y: position.y)
        defer { ink.ctx.restoreGState() }
        switch hat {
        case .top:
            ink.rounded(CGRect(x: -12.5, y: -23, width: 25, height: 21), 3, 0x222a3c)
            ink.rounded(CGRect(x: -10.5, y: -21, width: 5, height: 17), 2, 0x394960)
            ink.fill(CGRect(x: -12.5, y: -8, width: 25, height: 4), accent)
            ink.rounded(CGRect(x: -19, y: -5.4, width: 38, height: 5.4), 2.55, 0x172031)
        case .knit:
            ink.oval(CGRect(x: -15, y: -22, width: 30, height: 23), 0x398cce)
            ink.circle(-0.5, -23, 4.5, 0xf9fbfa)
            ink.line([p(-11, -14), p(-5, -16), p(3, -16), p(11, -13)], 0x91c9f5, width: 2.2)
            ink.rounded(CGRect(x: -16, y: -8.5, width: 32, height: 7.4), 2.8, 0xd7edfa)
            for x in stride(from: -12.0, to: 13, by: 4) {
                ink.line([p(x, -7), p(x, -2.8)], 0x84add1, width: 0.7)
            }
        case .crown:
            ink.poly([p(-14, -4), p(-17, -20), p(-8, -13), p(0, -23), p(7, -13), p(16, -20), p(13, -4)], 0xf6bd51)
            ink.rounded(CGRect(x: -14, y: -7.5, width: 28, height: 4.7), 1.5, 0xdf8539)
            ink.circle(0, -12.6, 2.2, 0xe76065)
            ink.line([p(-15, -17), p(-8, -11), p(0, -20)], 0xffecae, width: 0.8)
        case .cowboy:
            ink.rounded(CGRect(x: -12, y: -20, width: 24, height: 15), 7, 0xb77243)
            ink.rounded(CGRect(x: -12, y: -9, width: 24, height: 4), 1.1, 0x694436)
            shape(0xd4945b, ink) { path in
                path.move(to: p(-23, -9)); path.addQuadCurve(to: p(23, -9), control: p(0, 5))
                path.addQuadCurve(to: p(-23, -9), control: p(0, 12))
            }
        case .party:
            ink.poly([p(-15, -3), p(-1, -27), p(14, -3)], 0xaa71d4)
            ink.poly([p(-13, -3), p(-1, -27), p(-4, -3)], 0xcf9bed, alpha: 0.86)
            ink.star(3.4, -11, 4, 0xffe49a, points: 4)
            ink.circle(-2, -27, 3.2, 0xfaadc9)
        case .earmuffs, .headphones:
            let band: UInt32 = hat == .earmuffs ? 0x844c6d : 0x263a53
            let pads: UInt32 = hat == .earmuffs ? 0xf393af : 0x3f86ac
            arch(band, ink: ink)
            for direction: CGFloat in [-1, 1] {
                ink.rounded(CGRect(x: direction * 16.2 - 4.3, y: -1, width: 8.6, height: 12.4), 4.05, pads)
                ink.circle(direction * 17, 4.4, 2.5, 0xe1e9f1, alpha: 0.57)
            }
        case .viking:
            for direction: CGFloat in [-1, 1] {
                shape(0xffedcc, ink) { path in
                    path.move(to: p(direction * 11, -8))
                    path.addQuadCurve(to: p(direction * 26, -22), control: p(direction * 25, -9))
                    path.addQuadCurve(to: p(direction * 12, -14), control: p(direction * 18, -15))
                }
            }
            ink.oval(CGRect(x: -15.1, y: -20, width: 30.2, height: 18), 0x9eb3c0)
            ink.rounded(CGRect(x: -15.6, y: -9, width: 31.2, height: 6.2), 2.2, 0xab734b)
            ink.line([p(0, -17), p(0, -8)], 0xe5c794, width: 2.35)
            ink.circle(0, -6, 1.8, 0xffdc8f)
        case .santa:
            shape(0xda3048, ink) { path in
                path.move(to: p(-16, -3))
                path.addCurve(to: p(7, -24), control1: p(-16, -17), control2: p(-8, -26))
                path.addQuadCurve(to: p(22, -10), control: p(19, -23))
                path.addQuadCurve(to: p(11, -12), control: p(16, -11))
                path.addQuadCurve(to: p(14, -3), control: p(14, -8))
            }
            ink.line([p(-11, -10), p(-8, -16), p(-1, -20)], 0xff6877, width: 1.55, alpha: 0.85)
            ink.rounded(CGRect(x: -17, y: -7, width: 33, height: 7.0), 3.5, 0xfdf9f0)
            ink.circle(22, -10, 4.4, 0xf8f9fc)
        case .elf:
            shape(0x2c9a6c, ink) { path in
                path.move(to: p(-15, -3))
                path.addCurve(to: p(7, -23), control1: p(-10, -19), control2: p(-3, -27))
                path.addQuadCurve(to: p(22, -15), control: p(15, -19))
                path.addQuadCurve(to: p(13, -4), control: p(12, -17))
            }
            ink.poly([p(-16, -8), p(-11, -4), p(-6, -8), p(-2, -4), p(3, -8), p(7, -4), p(13, -8),
                      p(15, -1), p(-16, -1)], 0xcf4260)
            ink.circle(22.1, -15.2, 2.9, 0xffcd69)
        case .antlers:
            for direction: CGFloat in [-1, 1] {
                ink.line([p(direction * 7, -3), p(direction * 12, -12), p(direction * 12.3, -21),
                          p(direction * 16, -27)], 0xa46a40, width: 3.05)
                ink.line([p(direction * 12.1, -15), p(direction * 20, -17), p(direction * 23, -23)], 0xc78d59, width: 2.7)
                ink.line([p(direction * 12, -19), p(direction * 8, -24)], 0xba8052, width: 2.45)
            }
            ink.rounded(CGRect(x: -15, y: -4, width: 30, height: 3.2), 1.4, 0xb34b55)
        case .pirate:
            shape(0x222534, ink) { path in
                path.move(to: p(-22, -4))
                path.addQuadCurve(to: p(-12, -16), control: p(-16, -11))
                path.addQuadCurve(to: p(14, -17), control: p(2, -32))
                path.addQuadCurve(to: p(22, -4), control: p(15, -7))
                path.addQuadCurve(to: p(-22, -4), control: p(0, 2))
            }
            ink.line([p(-17, -4), p(-7, -5.5), p(6, -5.5), p(17, -4)], 0xe5bc73, width: 1.4)
            ink.star(0.4, -12.9, 4.0, 0xf0ece5, points: 4)
        case .none:
            break
        }
    }

    private static func arch(_ color: UInt32, ink: Ink) {
        let path = CGMutablePath()
        path.move(to: p(-17.5, 5))
        path.addCurve(to: p(17.5, 5), control1: p(-17.5, -22), control2: p(17.5, -22))
        ink.ctx.addPath(path)
        ink.ctx.setStrokeColor(NSColor(rgb: color).cgColor)
        ink.ctx.setLineWidth(3.3)
        ink.ctx.strokePath()
    }

    private static func shape(_ fill: UInt32, _ ink: Ink, draw: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        draw(path)
        path.closeSubpath()
        ink.ctx.addPath(path)
        ink.ctx.setFillColor(NSColor(rgb: fill).cgColor)
        ink.ctx.fillPath()
    }
}
