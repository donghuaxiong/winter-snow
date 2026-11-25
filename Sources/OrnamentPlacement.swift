import CoreGraphics

extension Ornament {
    var usesFreePlacement: Bool {
        kind == .snowman ? snowmanFollowsGround == false : usesDisplayCoordinates == true
    }

    var drawnSize: CGSize { CGSize(width: kind.size.width * scale, height: kind.size.height * scale) }

    func desktopFrame(in display: CGRect, usable: CGRect) -> CGRect {
        let area = usesFreePlacement ? display : usable
        let center = p(area.minX + area.width * x, area.minY + area.height * y)
        return desktopFrame(center: center, inside: area, free: usesFreePlacement)
    }

    func desktopFrame(center: CGPoint, inside area: CGRect, free: Bool) -> CGRect {
        let size = drawnSize
        if free && kind == .snowman { return SnowmanGround.frame(center: center, size: size, inside: area) }
        let sprite = CGRect(origin: .zero, size: size)
        let footprint = free ? interactionFrame(in: sprite) : sprite
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        func fitted(_ coordinate: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
            minimum <= maximum ? min(maximum, max(minimum, coordinate)) : (minimum + maximum) / 2
        }
        let x = fitted(center.x, minimum: area.minX + halfWidth - footprint.minX,
                       maximum: area.maxX + halfWidth - footprint.maxX)
        let y = fitted(center.y, minimum: area.minY - halfHeight + footprint.maxY,
                       maximum: area.maxY - halfHeight + footprint.minY)
        return CGRect(x: x - halfWidth, y: y - halfHeight, width: size.width, height: size.height)
    }

    mutating func placeOnDesktop(at center: CGPoint, displayID: UInt32, display: CGRect) {
        anchor = nil
        self.display = displayID
        x = (center.x - display.minX) / display.width
        y = (center.y - display.minY) / display.height
        if kind == .snowman { snowmanFollowsGround = false }
        else { usesDisplayCoordinates = true }
    }

    // The sprite includes transparent padding and glow. Use the drawn body for input and blade contact.
    func interactionFrame(in frame: CGRect) -> CGRect {
        let body: CGRect
        switch kind {
        case .snowman: body = CGRect(x: 0.15, y: 0.047, width: 0.70, height: 0.906)
        case .tree: body = CGRect(x: 0.08, y: 0.04, width: 0.84, height: 0.93)
        case .lights: body = CGRect(x: 0.025, y: 0.16, width: 0.95, height: bulb == .icicle ? 0.80 : 0.58)
        case .lantern: body = CGRect(x: 0.18, y: 0.10, width: 0.64, height: 0.83)
        case .gift: body = CGRect(x: 0.08, y: 0.10, width: 0.84, height: 0.82)
        case .calendar: body = CGRect(x: 0.018, y: 0.022, width: 0.964, height: 0.947)
        case .wreath: body = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let bounds = CGRect(x: frame.minX + body.minX * frame.width, y: frame.minY + body.minY * frame.height,
                            width: body.width * frame.width, height: body.height * frame.height)
        guard rotation != 0 else { return bounds }
        return bounds.applying(CGAffineTransform(translationX: frame.midX, y: frame.midY)
            .rotated(by: rotation * .pi / 180)
            .translatedBy(x: -frame.midX, y: -frame.midY))
    }
}
