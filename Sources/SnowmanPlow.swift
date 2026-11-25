import CoreGraphics

struct SnowplowContact {
    let blade: CGFloat
    let direction: CGFloat
    let speed: CGFloat
    private let hitArea: CGRect

    init(pass: PlowPass, previous: PlowPass?, floor: CGRect) {
        direction = pass.direction
        speed = pass.speed(width: floor.width)
        let offset = direction * SnowplowArt.bladeNoseOffset
        blade = floor.minX + pass.bladeX(width: floor.width) + offset
        let old = previous.flatMap { $0.direction == pass.direction ? $0 : nil }
            .map { floor.minX + $0.bladeX(width: floor.width) + offset } ?? blade
        let left = max(floor.minX, min(old, blade) - 4)
        let right = min(floor.maxX, max(old, blade) + 4)
        hitArea = CGRect(x: left, y: floor.minY - SnowplowArt.bladeReach,
                         width: max(0, right - left), height: SnowplowArt.bladeReach + 1)
    }

    func hits(_ part: SnowmanPart) -> Bool {
        guard !hitArea.isEmpty else { return false }
        let closestX = min(hitArea.maxX, max(hitArea.minX, part.center.x))
        let closestY = min(hitArea.maxY, max(hitArea.minY, part.center.y))
        return hypot(part.center.x - closestX, part.center.y - closestY) <= part.radius
    }

    func hits(_ rect: CGRect) -> Bool { hitArea.intersects(rect) }
}

struct PlowedSnowman {
    private struct Piece {
        var part: SnowmanPart
        var fallingSpeed: CGFloat
        let lead: CGFloat
    }

    let ornament: Ornament
    private let direction: CGFloat
    private let speed: CGFloat
    private var blade: CGFloat
    private var age: CGFloat = 0
    private var pieces: [Piece]

    var parts: [SnowmanPart] { pieces.map(\.part) }

    init(ornament: Ornament, parts: [SnowmanPart], contact: SnowplowContact) {
        self.ornament = ornament
        direction = contact.direction
        speed = contact.speed
        blade = contact.blade
        var lead: CGFloat = 0
        pieces = parts.map { part in
            let piece = Piece(part: part, fallingSpeed: -CGFloat(46 + part.tone * 33), lead: lead)
            lead += part.radius * 1.85
            return piece
        }
    }

    mutating func advance(_ delta: CGFloat, contact: SnowplowContact?, floor: CGRect, reduced: Bool) -> Bool {
        age += delta
        if let contact, contact.direction == direction { blade = contact.blade }
        else { blade += direction * speed * delta }

        for index in pieces.indices {
            let previous = pieces[index].part
            let lead = min(1, age / 0.40) * pieces[index].lead
            let edge = blade + direction * (previous.radius + lead)
            let coasting = previous.center.x + direction * speed * 0.67 * delta
            let newX = direction * max(direction * edge, direction * coasting)
            pieces[index].part.center.x = newX
            if !reduced { pieces[index].part.angle += (newX - previous.center.x) / previous.radius }
            pieces[index].fallingSpeed += 820 * delta
            pieces[index].part.center.y += pieces[index].fallingSpeed * delta
            let rest = floor.minY - previous.radius
            if pieces[index].part.center.y >= rest {
                pieces[index].part.center.y = rest
                let impact = pieces[index].fallingSpeed
                pieces[index].fallingSpeed = impact > 60 ? -impact * 0.25 : 0
            }
        }
        return pieces.contains {
            let bounds = $0.part.bounds(dressed: true)
            return direction > 0 ? bounds.minX < floor.maxX : bounds.maxX > floor.minX
        }
    }
}

struct PlowedDecoration {
    private(set) var ornament: Ornament
    private(set) var frame: CGRect
    private let direction: CGFloat
    private let speed: CGFloat
    private var fallingSpeed: CGFloat = -112
    private var age: CGFloat = 0

    var opacity: CGFloat { min(1, max(0, (0.9 - age) / 0.58)) }

    init(ornament: Ornament, frame: CGRect, contact: SnowplowContact) {
        self.ornament = ornament
        self.frame = frame
        direction = contact.direction
        speed = contact.speed * 0.84
    }

    mutating func advance(_ delta: CGFloat, floor: CGRect, reduced: Bool) -> Bool {
        age += delta
        frame.origin.x += direction * speed * delta
        if !reduced {
            ornament.rotation += direction * 235 * delta
            fallingSpeed += 740 * delta
            frame.origin.y += fallingSpeed * delta
            let overrun = ornament.interactionFrame(in: frame).maxY - floor.minY
            if overrun > 0 {
                frame.origin.y -= overrun
                fallingSpeed = fallingSpeed > 65 ? -fallingSpeed * 0.26 : 0
            }
        }
        let bounds = ornament.paintBounds(in: frame)
        return opacity > 0 && (direction > 0 ? bounds.minX < floor.maxX : bounds.maxX > floor.minX)
    }
}
