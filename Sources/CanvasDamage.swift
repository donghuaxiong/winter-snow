import CoreGraphics

struct CanvasDamage {
    static let tileSize: CGFloat = 48
    private var previous: [Bool] = []
    private var size = CGSize.zero

    // A nil result requests a full repaint when the view changes size or damage is dense.
    mutating func regions(in size: CGSize, moving: [CGRect], changed: [CGRect], full: Bool) -> [CGRect]? {
        let tile = Self.tileSize
        let columns = max(1, Int(ceil(size.width / tile)))
        let rows = max(1, Int(ceil(size.height / tile)))
        let count = columns * rows
        let canvas = CGRect(origin: .zero, size: size)
        var current = Array(repeating: false, count: count)

        func mark(_ rects: [CGRect], in mask: inout [Bool]) {
            for rect in rects {
                let clipped = rect.intersection(canvas)
                guard !clipped.isEmpty else { continue }
                let x0 = max(0, Int(floor(clipped.minX / tile)))
                let x1 = min(columns, Int(ceil(clipped.maxX / tile)))
                let y0 = max(0, Int(floor(clipped.minY / tile)))
                let y1 = min(rows, Int(ceil(clipped.maxY / tile)))
                for y in y0..<y1 {
                    for x in x0..<x1 { mask[y * columns + x] = true }
                }
            }
        }

        mark(moving, in: &current)
        let resized = self.size != size || previous.count != count
        var dirty = resized ? current : previous
        previous = current
        self.size = size
        if full || resized { return nil }
        for index in dirty.indices where current[index] { dirty[index] = true }
        mark(changed, in: &dirty)

        var filled = 0
        var result: [CGRect] = []
        for y in 0..<rows {
            var x = 0
            while x < columns {
                let left = x
                while x < columns, dirty[y * columns + x] { x += 1 }
                if x == left {
                    x += 1
                } else {
                    filled += x - left
                    result.append(CGRect(x: CGFloat(left) * tile, y: CGFloat(y) * tile,
                                         width: CGFloat(x - left) * tile, height: tile).intersection(canvas))
                }
            }
        }
        return filled * 3 >= count * 2 ? nil : result
    }
}

extension CGRect {
    init(around point: CGPoint, radius: CGFloat) {
        self.init(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }

    func areasOutside(_ other: CGRect) -> [CGRect] {
        let overlap = intersection(other)
        if overlap.isEmpty { return isEmpty ? [] : [self] }
        return [
            CGRect(x: minX, y: minY, width: overlap.minX - minX, height: height),
            CGRect(x: overlap.maxX, y: minY, width: maxX - overlap.maxX, height: height),
            CGRect(x: overlap.minX, y: minY, width: overlap.width, height: overlap.minY - minY),
            CGRect(x: overlap.minX, y: overlap.maxY, width: overlap.width, height: maxY - overlap.maxY),
        ].filter { !$0.isEmpty }
    }
}

extension Flake {
    var paintBounds: CGRect { CGRect(around: p(x, y), radius: radius * 1.7 + 1) }
}

extension SnowSurface {
    var paintBounds: CGRect {
        CGRect(x: rect.minX - 18, y: rect.minY - maximumDepth - 5,
               width: rect.width + 36, height: maximumDepth + cornerRadius + 23)
    }
}

extension Ornament {
    func paintBounds(in frame: CGRect) -> CGRect {
        if rotation == 0 { return frame.insetBy(dx: -22, dy: -22) }
        return CGRect(around: p(frame.midX, frame.midY), radius: hypot(frame.width, frame.height) / 2 + 22)
    }
}
