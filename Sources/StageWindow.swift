import CoreGraphics

enum StageWindow {
    static func isThumbnail(_ rect: CGRect, on displays: [CGRect]) -> Bool {
        guard rect.width <= 154, rect.height <= 152 else { return false }
        return displays.contains { display in
            let side = min(146, display.width * 0.15)
            return (display.minX - side...display.minX + side).contains(rect.midX)
                && rect.maxY > display.minY && rect.minY < display.maxY
        }
    }

    static func isMovingToStrip(from start: CGRect, to rect: CGRect, on displays: [CGRect]) -> Bool {
        let widthRatio = rect.width / start.width
        let heightRatio = rect.height / start.height
        guard start.midX - rect.midX >= 24, max(widthRatio, heightRatio) <= 0.89,
              abs(widthRatio - heightRatio) < 0.13 else { return false }
        return displays.contains { display in
            display.contains(CGPoint(x: start.midX, y: start.midY))
                && rect.midX < display.minX + display.width * 0.42
                && rect.midX > display.minX - 166
        }
    }
}
