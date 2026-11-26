import AppKit
import IOKit.ps

enum DesktopWeatherPower {
    static var limited: Bool {
        let process = ProcessInfo.processInfo
        if process.isLowPowerModeEnabled || process.thermalState == .serious || process.thermalState == .critical {
            return true
        }
        guard let source = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(source)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    static func fullscreen(_ window: CGRect, on display: CGRect) -> Bool {
        abs(window.minX - display.minX) <= 4 && abs(window.maxX - display.maxX) <= 4
            && abs(window.minY - display.minY) <= 4 && abs(window.maxY - display.maxY) <= 4
    }
}

struct SnowGust {
    let center: CGFloat
    let extent: CGFloat
    let strength: CGFloat

    init(time: CGFloat, width: CGFloat, amount: CGFloat, seed: UInt64) {
        let shifted = max(0, time + CGFloat(seed % 23) * 0.47)
        let cycle = floor(shifted / 11)
        let age = shifted - cycle * 11
        let direction: CGFloat = cycle.truncatingRemainder(dividingBy: 2) < 1 ? 1 : -1
        let progress = min(1, age / 6)
        center = width * (0.5 + direction * (progress - 0.5) * 1.50)
        extent = max(90, width * 0.36)
        strength = age < 6 ? direction * min(1, max(0, amount)) * 126 * pow(sin(progress * .pi), 1.3) : 0
    }

    func push(at x: CGFloat) -> CGFloat {
        let envelope = max(0, 1 - abs(x - center) / extent)
        return strength * envelope * envelope
    }
}

enum IceCrystalArt {
    private static let patterns: [CGPath] = (0..<3).map { style in
        let path = CGMutablePath()
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3
            let ray = p(cos(angle), sin(angle))
            let normal = p(-ray.y, ray.x)
            path.move(to: .zero)
            path.addLine(to: ray)
            let branches: [CGFloat] = style == 1 ? [0.47, 0.72] : [0.58]
            for distance in branches {
                for side in [-1.0, 1.0] {
                    path.move(to: p(ray.x * distance, ray.y * distance))
                    let reach = style == 0 ? 0.21 : 0.17
                    path.addLine(to: p(ray.x * (distance + reach) + normal.x * side * 0.24,
                                       ray.y * (distance + reach) + normal.y * side * 0.24))
                }
            }
            if style == 2 {
                path.move(to: p(ray.x * 0.36, ray.y * 0.36))
                path.addLine(to: p(cos(angle + .pi / 3) * 0.36, sin(angle + .pi / 3) * 0.36))
            }
        }
        return path
    }

    static func draw(_ flake: Flake, at time: Double, opacity: CGFloat, ink: Ink) {
        let ctx = ink.ctx
        let angle = flake.phase + time * (0.35 + flake.depth * 0.7)
        let radius = flake.radius * 1.35
        ctx.saveGState()
        ctx.translateBy(x: flake.x, y: flake.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: radius, y: radius * (time == 0 ? 1 : 0.78 + 0.22 * cos(time + flake.phase)))
        ctx.setStrokeColor(NSColor(rgb: 0xeeFAff, alpha: min(1, opacity + 0.16)).cgColor)
        ctx.setLineWidth(max(0.13, 0.64 / radius))
        ctx.setLineCap(.round)
        ctx.addPath(patterns[Int(flake.crystal * 97) % patterns.count])
        ctx.strokePath()
        ctx.restoreGState()
    }
}
