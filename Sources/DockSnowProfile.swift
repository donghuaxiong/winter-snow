import CoreGraphics

struct DockSnowProfile {
    private static let start: CGFloat = 0.56
    let rect: CGRect
    let radius: CGFloat

    init(_ rect: CGRect, radius: CGFloat) {
        self.rect = rect
        self.radius = min(radius, rect.width * 0.24, rect.height * 0.5)
    }

    var supportedRange: ClosedRange<CGFloat> {
        let inset = radius * Self.start
        return (rect.minX + inset)...(rect.maxX - inset)
    }

    func contactY(at x: CGFloat) -> CGFloat {
        guard radius > 0 else { return rect.minY }
        let distance = min(x - rect.minX, rect.maxX - x)
        let bend = min(1, max(0, 1 - distance / radius))
        return rect.minY + radius * (1 - sqrt(1 - bend * bend))
    }

    func coverage(at x: CGFloat) -> CGFloat {
        guard radius > 0 else { return 1 }
        let distance = min(x - rect.minX, rect.maxX - x)
        let t = min(1, max(0, (distance - radius * Self.start) / (radius * 1.03)))
        return t * t * (3 - 2 * t)
    }
}
