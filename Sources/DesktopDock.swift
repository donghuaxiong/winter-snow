import AppKit
import ApplicationServices
import Darwin

/// The Dock may be omitted from WindowServer's public list. Its work-area inset
/// still describes the reserved edge, even when its window number is unavailable.
struct DesktopDock: Sendable {
    enum Edge: String, Sendable { case bottom, left, right }

    private typealias SystemRectReader = @convention(c) (UnsafeMutablePointer<CGRect>) -> Void
    private static let systemRectReader: SystemRectReader? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(library, "CoreDockGetRect") else {
            dlclose(library)
            return nil
        }
        return unsafeBitCast(symbol, to: SystemRectReader.self)
    }()

    private struct Calibration: Codable {
        let displaySize: CGSize
        let estimatedSize: CGSize
        let bounds: CGRect
    }

    let edge: Edge
    private let scale: CGFloat
    private let tiles: Int
    private let separators: Int
    private let dockPID: Int32?
    private let measured: CGRect?

    @MainActor
    init(primaryTop: CGFloat) {
        self.init(primaryTop: primaryTop, displayFrames: NSScreen.screens.map(\.frame))
    }

    init(primaryTop: CGFloat, displayFrames: [CGRect]) {
        let domain = "com.apple.dock" as CFString
        func preference(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
        edge = (preference("orientation") as? String).flatMap(Edge.init(rawValue:)) ?? .bottom
        scale = max(24, (preference("tilesize") as? NSNumber)?.doubleValue ?? 48)
        let pinned = preference("persistent-apps") as? [[String: Any]] ?? []
        let others = preference("persistent-others") as? [[String: Any]] ?? []
        let recent = (preference("show-recents") as? Bool ?? true)
            ? preference("recent-apps") as? [[String: Any]] ?? [] : []

        func bundleIDs(_ entries: [[String: Any]]) -> Set<String> {
            Set(entries.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String })
        }
        let pinnedIDs = bundleIDs(pinned)
        let recentIDs = bundleIDs(recent).subtracting(pinnedIDs)
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { $0.bundleIdentifier }
        let loose = Set(running).subtracting(pinnedIDs.union(recentIDs)).subtracting(["com.apple.finder"])
        tiles = max(3, pinned.count + others.count + recentIDs.count + loose.count + 2)
        separators = recentIDs.isEmpty ? 1 : 2
        dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier

        measured = Self.visibleBounds(primaryTop: primaryTop, edge: edge, displays: displayFrames)
    }

    @MainActor
    func frame(on screen: NSScreen) -> CGRect? {
        let display = screen.frame
        if let measured, display.contains(p(measured.midX, measured.midY)) { return measured }
        guard let estimate = estimatedFrame(on: screen) else { return nil }
        if let data = UserDefaults.standard.data(forKey: calibrationKey(on: screen)),
           let calibration = try? JSONDecoder().decode(Calibration.self, from: data),
           calibration.displaySize == display.size,
           abs(calibration.estimatedSize.width - estimate.width) < 3,
           abs(calibration.estimatedSize.height - estimate.height) < 3 {
            return calibration.bounds.offsetBy(dx: display.minX, dy: display.minY)
        }
        return estimate
    }

    @MainActor
    func liveFrame(primaryTop: CGFloat, displays: [NSScreen], hitBounds: inout DockHitBounds) -> (UInt32, CGRect)? {
        guard let read = Self.systemRectReader else { return nil }
        var raw = CGRect.zero
        read(&raw)
        guard !raw.isEmpty, [raw.minX, raw.minY, raw.width, raw.height].allSatisfy(\.isFinite) else { return nil }
        let reserved = CGRect(x: raw.minX, y: primaryTop - raw.maxY, width: raw.width, height: raw.height)
        let vertical = edge != .bottom
        let length = vertical ? reserved.height : reserved.width
        let depth = vertical ? reserved.width : reserved.height
        guard (22...150).contains(depth), length > depth * 1.5,
              let display = displays.first(where: { $0.frame.contains(p(reserved.midX, reserved.midY)) }) else { return nil }
        let borderGap: CGFloat = switch edge {
        case .bottom: reserved.minY - display.frame.minY
        case .left: reserved.minX - display.frame.minX
        case .right: display.frame.maxX - reserved.maxX
        }
        guard abs(borderGap) <= 24 else { return nil }
        let displayBounds = CGRect(x: display.frame.minX, y: primaryTop - display.frame.maxY,
                                   width: display.frame.width, height: display.frame.height)
        let reservedInWorkArea = workAreaInset(on: display) >= 22
        if let dockPID, let body = hitBounds.measure(near: raw, on: displayBounds, edge: edge,
                                                   dockPID: dockPID, keepWhenCovered: reservedInWorkArea) {
            let observed = CGRect(x: body.minX, y: primaryTop - body.maxY, width: body.width, height: body.height)
            return (display.snowScreenID, glassFrame(in: observed, measured: true))
        }
        guard reservedInWorkArea else { return nil }
        return (display.snowScreenID, glassFrame(in: reserved, measured: false))
    }

    private func glassFrame(in bounds: CGRect, measured: Bool) -> CGRect {
        // The system rectangle includes the screen-edge gap and a slim hit margin around the glass.
        let modern: Bool = if #available(macOS 26, *) { true } else { false }
        let outside: CGFloat = modern ? 5 : 4
        let inside: CGFloat = modern ? (measured ? 1.5 : 2.5) : 4
        let ends: CGFloat = modern && !measured ? 1 : 0.5
        switch edge {
        case .bottom:
            return CGRect(x: bounds.minX + ends, y: bounds.minY + outside,
                          width: bounds.width - ends * 2, height: bounds.height - outside - inside)
        case .left, .right:
            return CGRect(x: bounds.minX + (edge == .left ? outside : inside), y: bounds.minY + ends,
                          width: bounds.width - outside - inside, height: bounds.height - ends * 2)
        }
    }

    @MainActor
    func calibrate(_ bounds: CGRect, on screen: NSScreen) -> Bool {
        let canvas = CGRect(origin: .zero, size: screen.frame.size)
        guard canvas.contains(bounds), let estimate = estimatedFrame(on: screen),
              let data = try? JSONEncoder().encode(Calibration(displaySize: canvas.size,
                                                                estimatedSize: estimate.size, bounds: bounds)) else { return false }
        UserDefaults.standard.set(data, forKey: calibrationKey(on: screen))
        UserDefaults.standard.synchronize()
        return true
    }

    @MainActor
    private func calibrationKey(on screen: NSScreen) -> String {
        let uuid = CGDisplayCreateUUIDFromDisplayID(screen.snowScreenID)?.takeRetainedValue()
        let id = uuid.map { CFUUIDCreateString(nil, $0) as String } ?? String(screen.snowScreenID)
        return "snowglow-dock-bounds-\(id)-\(edge.rawValue)"
    }

    @MainActor
    private func estimatedFrame(on screen: NSScreen) -> CGRect? {
        let display = screen.frame
        let safe = screen.visibleFrame
        let vertical = edge != .bottom
        let reserve = workAreaInset(on: screen)
        guard reserve >= 22 else { return nil }
        let floatingGlass: Bool = if #available(macOS 26, *) { true } else { false }
        let thickness = max(18, reserve - (floatingGlass ? 7 : 8))
        let spacing = min(scale, max(20, thickness - 15)) + (floatingGlass ? 6.25 : 9)
        let available = vertical ? display.height : display.width
        let inset = floatingGlass ? min(available * 0.07, max(14, thickness * 0.60)) : 9
        let extent = min(available - inset * 2, CGFloat(tiles) * spacing + CGFloat(separators) * 11 + 17)
        let gap: CGFloat = floatingGlass ? 5 : 4
        if vertical {
            let x = edge == .left ? display.minX + gap : display.maxX - gap - thickness
            return CGRect(x: x, y: safe.midY - extent / 2, width: thickness, height: extent)
        }
        return CGRect(x: display.midX - extent / 2, y: display.minY + gap, width: extent, height: thickness)
    }

    @MainActor
    private func workAreaInset(on screen: NSScreen) -> CGFloat {
        let display = screen.frame
        let safe = screen.visibleFrame
        return switch edge {
        case .left: safe.minX - display.minX
        case .right: display.maxX - safe.maxX
        case .bottom: safe.minY - display.minY
        }
    }

    private static func visibleBounds(primaryTop: CGFloat, edge: Edge, displays: [CGRect]) -> CGRect? {
        let docks = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        func isDockShape(_ bounds: CGRect) -> Bool {
            let thin = edge == .bottom ? bounds.height : bounds.width
            let long = edge == .bottom ? bounds.width : bounds.height
            guard (22...150).contains(thin), long >= 85, long > thin * 1.75 else { return false }
            return displays.contains { display in
                let gap = switch edge {
                case .bottom: abs(bounds.minY - display.minY)
                case .left: abs(bounds.minX - display.minX)
                case .right: abs(bounds.maxX - display.maxX)
                }
                return gap < 30 && display.contains(p(bounds.midX, bounds.midY))
            }
        }
        let pids = Set(docks.map(\.processIdentifier))
        let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []
        for entry in entries {
            guard let pid = entry[kCGWindowOwnerPID as String] as? NSNumber, pids.contains(pid.int32Value),
                  let values = entry[kCGWindowBounds as String] as? [String: Any],
                  let raw = CGRect(dictionaryRepresentation: values as CFDictionary) else { continue }
            let frame = CGRect(x: raw.minX, y: primaryTop - raw.maxY, width: raw.width, height: raw.height)
            if isDockShape(frame) { return frame }
        }
        guard AXIsProcessTrusted(), let dock = docks.first else { return nil }

        func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        for list in attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard attribute(list, kAXRoleAttribute) as? String == kAXListRole,
                  let point = attribute(list, kAXPositionAttribute),
                  let size = attribute(list, kAXSizeAttribute),
                  CFGetTypeID(point) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            guard AXValueGetValue(point as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(size as! AXValue, .cgSize, &extent) else { continue }
            let frame = CGRect(x: origin.x, y: primaryTop - origin.y - extent.height,
                               width: extent.width, height: extent.height)
            if isDockShape(frame) { return frame }
        }
        return nil
    }
}
