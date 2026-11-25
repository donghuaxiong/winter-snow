import CoreGraphics
import Darwin

/// Reads where WindowServer routes pointer events without moving the pointer.
struct DockHitBounds {
    private struct Reader {
        typealias Connection = @convention(c) () -> Int32
        typealias Find = @convention(c) (Int32, Int32, Int32, Int32, UnsafeMutablePointer<CGPoint>,
                                         UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<UInt32>,
                                         UnsafeMutablePointer<Int32>) -> Int32
        typealias OwnerPID = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
        let connection: Connection
        let find: Find
        let ownerPID: OwnerPID

        init?() {
            let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
            guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
            guard let connection = dlsym(library, "SLSMainConnectionID"),
                  let find = dlsym(library, "SLSFindWindowAndOwner"),
                  let ownerPID = dlsym(library, "SLSConnectionGetPID") else {
                dlclose(library)
                return nil
            }
            self.connection = unsafeBitCast(connection, to: Connection.self)
            self.find = unsafeBitCast(find, to: Find.self)
            self.ownerPID = unsafeBitCast(ownerPID, to: OwnerPID.self)
        }

        func hit(_ point: CGPoint, connection id: Int32) -> (window: UInt32, owner: Int32)? {
            var source = point
            var destination = CGPoint.zero
            var window: UInt32 = 0
            var owner: Int32 = 0
            guard find(id, 0, 1, 0, &source, &destination, &window, &owner) == 0, window != 0 else { return nil }
            return (window, owner)
        }
    }

    private static let reader = Reader()
    private var lastFrame: CGRect?
    private var lastReserved: CGRect?
    private var lastDisplay: CGRect?
    private var lastEdge: DesktopDock.Edge?
    private var lastOwner: Int32?

    mutating func measure(near reserved: CGRect, on display: CGRect, edge: DesktopDock.Edge,
                          dockPID: Int32, keepWhenCovered: Bool) -> CGRect? {
        let sameDisplay = lastDisplay == display && lastEdge == edge && lastOwner == dockPID
        let previous = sameDisplay ? lastFrame : nil
        let anchor = CGPoint(x: reserved.midX, y: reserved.midY)
        guard let reader = Self.reader else { return nil }
        let connection = reader.connection()
        guard let hit = reader.hit(anchor, connection: connection) else { return nil }
        var pid: Int32 = 0
        guard reader.ownerPID(hit.owner, &pid) == 0, pid == dockPID else {
            return keepWhenCovered && lastReserved == reserved ? previous : nil
        }

        func matches(_ point: CGPoint) -> Bool { reader.hit(point, connection: connection)?.window == hit.window }
        func x(to outside: CGFloat, previous: CGFloat?) -> CGFloat {
            Self.boundary(from: anchor.x, to: outside, previous: previous) { matches(CGPoint(x: $0, y: anchor.y)) }
        }
        func y(to outside: CGFloat, previous: CGFloat?) -> CGFloat {
            Self.boundary(from: anchor.y, to: outside, previous: previous) { matches(CGPoint(x: anchor.x, y: $0)) }
        }

        let left = edge == .left ? reserved.minX : x(to: display.minX, previous: previous?.minX)
        let right = edge == .right ? reserved.maxX : x(to: display.maxX - 0.5, previous: previous?.maxX)
        let top = y(to: edge == .bottom ? max(display.minY, display.maxY - 160) : display.minY, previous: previous?.minY)
        let bottom = edge == .bottom ? reserved.maxY : y(to: display.maxY - 0.5, previous: previous?.maxY)
        let frame = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        let length = edge == .bottom ? frame.width : frame.height
        let depth = edge == .bottom ? frame.height : frame.width
        guard length >= 85, (20..<150).contains(depth), length > 1.5 * depth else { return nil }
        lastFrame = frame
        lastReserved = reserved
        lastDisplay = display
        lastEdge = edge
        lastOwner = dockPID
        return frame
    }

    private static func boundary(from inside: CGFloat, to outside: CGFloat, previous: CGFloat?,
                                 matches: (CGFloat) -> Bool) -> CGFloat {
        let inward: CGFloat = inside > outside ? 1 : -1
        if let previous, (min(outside, inside)...max(outside, inside)).contains(previous),
           matches(previous + inward * 0.55), !matches(previous - inward * 0.55) { return previous }
        if matches(outside) { return outside }
        var near = inside
        var far = outside
        while abs(near - far) > 0.5 {
            let midpoint = (near + far) / 2
            if matches(midpoint) { near = midpoint } else { far = midpoint }
        }
        return (near + far) / 2
    }
}
