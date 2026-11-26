import AppKit
import QuartzCore

private let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
private let windowCornerRadius: CGFloat = {
    if #available(macOS 26, *) { return 18 }
    return 11
}()

private final class OverlayPanel: NSPanel {
    private let keyboard: Bool
    override var canBecomeKey: Bool { keyboard }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect, level: NSWindow.Level, interactive: Bool, keyboard: Bool = false) {
        self.keyboard = keyboard
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = false
        hidesOnDeactivate = false
        ignoresMouseEvents = !interactive
        animationBehavior = .none
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}

private final class PaintView: NSView {
    var paint: ((Ink, CGRect) -> Void)?
    private var damage = CanvasDamage()
    override var isFlipped: Bool { true }

    func invalidate(moving: [CGRect], changed: [CGRect] = [], full: Bool) {
        if let regions = damage.regions(in: bounds.size, moving: moving, changed: changed, full: full) {
            for rect in regions { setNeedsDisplay(rect) }
        } else {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: dirtyRect)
        ctx.clear(dirtyRect)
        paint?(Ink(ctx: ctx), dirtyRect)
        ctx.restoreGState()
    }
}

private final class HandleView: NSView {
    var down: ((CGPoint) -> Void)?
    var drag: ((CGPoint) -> Void)?
    var up: ((CGPoint) -> Void)?
    var remove: (() -> Void)?
    var settings: (() -> Void)?
    var knock: (() -> Void)?
    var key: ((UInt16) -> Void)?
    var wheel: ((CGFloat) -> Void)?
    var guides: ((Ink) -> Void)?
    var selectionHint: String?
    var editTitle = "在工作台编辑"
    var removalTitle = "移除装饰"

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { key != nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ink = Ink(ctx: ctx)
        ink.fill(bounds, 0x000000, alpha: selectionHint == nil ? 0.008 : key == nil ? 0.19 : 0.065)
        guides?(ink)
        if let selectionHint {
            let width = min(bounds.width - 20, key == nil ? 402 : 620)
            let plate = CGRect(x: bounds.midX - width / 2, y: 52, width: width, height: 44)
            ink.rounded(plate, 12, 0x173145, alpha: 0.96)
            ink.text(selectionHint, at: p(plate.midX, plate.midY), size: 14, color: 0xe0f6ff)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if key != nil { window?.makeKey(); window?.makeFirstResponder(self) }
        down?(NSEvent.mouseLocation)
    }
    override func mouseDragged(with event: NSEvent) { drag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { up?(NSEvent.mouseLocation) }
    override func keyDown(with event: NSEvent) {
        if let key { key(event.keyCode) } else { super.keyDown(with: event) }
    }
    override func scrollWheel(with event: NSEvent) {
        if let wheel { wheel(event.scrollingDeltaY) } else { super.scrollWheel(with: event) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: selectionHint != nil ? .crosshair : drag == nil ? .pointingHand : .openHand)
    }

    override func rightMouseDown(with event: NSEvent) {
        if selectionHint != nil { remove?(); return }
        guard remove != nil else { return }
        let menu = NSMenu()
        if settings != nil {
            let item = NSMenuItem(title: editTitle, action: #selector(openSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if knock != nil {
            let item = NSMenuItem(title: "推倒重堆", action: #selector(knockDown), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let item = NSMenuItem(title: removalTitle, action: #selector(removeItem), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func removeItem() { remove?() }
    @objc private func openSettings() { settings?() }
    @objc private func knockDown() { knock?() }
}

private final class SnowRollView: NSView {
    private final class MenuAction: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    var press: ((CGPoint, Double) -> Void)?
    var drag: ((CGPoint, Double) -> Void)?
    var release: ((CGPoint, Double) -> Void)?
    var menuAt: ((CGPoint, SnowRollView) -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.008).setFill()
        dirtyRect.fill()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    private func location(of event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            press?(location(of: event), event.timestamp)
        }
    }

    override func mouseDragged(with event: NSEvent) { drag?(location(of: event), event.timestamp) }
    override func mouseUp(with event: NSEvent) { release?(location(of: event), event.timestamp) }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuAt?(location(of: event), self) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    func item(_ title: String, image: NSImage? = nil, run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.image = image
        item.representedObject = MenuAction(run)
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) { (sender.representedObject as? MenuAction)?.run() }
}

private struct OrnamentHandleKey: Hashable {
    let ornament: UUID
    let display: UInt32
    let region: Int
}

private struct OrnamentDragSession {
    let handle: OrnamentHandleKey
    let start: CGPoint
    let center: CGPoint
    var preview: (display: UInt32, frame: CGRect)?
}

@MainActor
private final class ScreenOverlay {
    let id: UInt32
    let back: OverlayPanel
    let front: OverlayPanel
    let backView = PaintView()
    let frontView = PaintView()
    var frame: CGRect
    var usable: CGRect
    var sim: DisplayScene
    var placements: [(Ornament, CGRect, DesktopWindow?)] = []
    var fallingSnowmen: [FallingSnowman] = []
    var plowedSnowmen: [PlowedSnowman] = []
    var rolledSnow = RolledSnow()
    var festivities = FestiveTraffic()
    var treeSnow: [UUID: TreeBranchSnow] = [:]
    var plowedDecorations: [PlowedDecoration] = []
    private var drawnSnow: [SurfaceID: (seed: UInt64, revision: UInt64)] = [:]
    var visibleBack = false
    var visibleFront = false

    init(screen: NSScreen, windowSnow: WindowSnowpack) {
        id = screen.snowScreenID
        frame = screen.frame
        usable = screen.visibleFrame
        sim = DisplayScene(id: id, windowSnow: windowSnow)
        back = OverlayPanel(frame: frame, level: .init(rawValue: NSWindow.Level.normal.rawValue - 1), interactive: false)
        front = OverlayPanel(frame: frame, level: overlayLevel, interactive: false)
        back.contentView = backView
        front.contentView = frontView
    }

    func local(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    func global(_ rect: CGRect) -> CGRect {
        CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    func place(_ ornament: Ornament, dock: CGRect?) -> CGRect {
        let normal = ornament.desktopFrame(in: frame, usable: usable)
        if ornament.kind == .snowman && SnowmanGround.followsSupport(ornament, usableHeight: usable.height) {
            let foot = SnowmanGround.foot(at: normal.midX, screen: frame, dock: dock)
            return CGRect(x: normal.minX, y: foot - (normal.height - SnowmanArt.baseline * ornament.scale),
                          width: normal.width, height: normal.height)
        }
        return normal
    }

    func changedSnow(showing: Bool) -> [CGRect] {
        var next: [SurfaceID: (seed: UInt64, revision: UInt64)] = [:]
        var changed: [CGRect] = []
        for surface in sim.surfaces {
            let old = drawnSnow[surface.id]
            let updated = showing ? sim.drift(on: surface.id) : nil
            if let updated { next[surface.id] = (updated.seed, updated.revision) }
            if old?.seed != updated?.seed || old?.revision != updated?.revision {
                changed.append(surface.paintBounds)
            }
        }
        drawnSnow = next
        return changed
    }

    func setVisibility(back shouldShowBack: Bool, front shouldShowFront: Bool) {
        if visibleBack != shouldShowBack {
            visibleBack = shouldShowBack
            if visibleBack { back.orderFrontRegardless() } else { back.orderOut(nil) }
        }
        if visibleFront != shouldShowFront {
            visibleFront = shouldShowFront
            if visibleFront { front.orderFrontRegardless() } else { front.orderOut(nil) }
        }
    }
}

@MainActor
final class DesktopEngine {
    private struct PropDrag {
        let ball: UUID
        let prop: UUID
        let offset: CGVector
    }

    private struct SnowRollGesture {
        let display: UInt32
        let start: CGPoint
        let time: Double
        let ball: UUID?
        let prop: PropDrag?
        var started = false
    }

    private struct SnowRollHit {
        let screen: ScreenOverlay
        let rect: CGRect
        let ball: RolledSnowball?
        var prop: SnowballProp?
    }
    private struct LightDraft {
        var display: UInt32?
        var ornament: Ornament?
        var hooks: [CGPoint] = []
        var slack: CGFloat = 1
        var movingHook: Int?
    }
    private struct SnowmanPerch {
        let display: UInt32
        let ornament: Ornament
        let bounds: CGRect
        var lostAt: Double?
    }

    private struct WindowExit {
        let origin: CGRect
        let pack: SnowDrift
        let edges: [UInt32: SnowSurface]
        let began: Double
        var lastMotion: Double
        var samples = 0
        var airborne = false

        static func starts(between old: CGRect, and frame: CGRect) -> Bool {
            let dx = abs(frame.midX - old.midX)
            let dy = abs(frame.midY - old.midY)
            let dw = frame.width - old.width
            let dh = frame.height - old.height
            return (dx + dy >= 1 && max(abs(dw), abs(dh)) >= 1) || (dw <= -1 && dh <= -1)
        }

        func suggestsMinimizing(_ frame: CGRect, toward edge: DesktopDock.Edge) -> Bool {
            let dx = frame.midX - origin.midX
            let dy = frame.midY - origin.midY
            let travels = switch edge {
            case .bottom: -dy
            case .left: -dx
            case .right: dx
            }
            guard travels >= 12 else { return false }
            let vertical = edge == .bottom
            let normalSize = vertical ? frame.height - origin.height : frame.width - origin.width
            let sideways = abs(vertical ? dx : dy)
            let stretch = vertical ? frame.width - origin.width : frame.height - origin.height
            // Genie moves the window toward the Dock while stretching it across that path.
            if abs(normalSize) <= 3, sideways <= travels * 0.55 + 2, (2...45).contains(stretch) { return true }
            let widthScale = frame.width / origin.width
            let heightScale = frame.height / origin.height
            return samples >= 2 && sideways <= travels * 4 && max(widthScale, heightScale) <= 0.83
                && abs(widthScale - heightScale) < 0.028
        }
    }

    let model: SnowModel
    var studioWindow: (() -> NSWindow?)?
    private let windowSnow = WindowSnowpack()
    private var screens: [UInt32: ScreenOverlay] = [:]
    private var windows: [DesktopWindow] = []
    private var shakes: [UInt32: WindowShake] = [:]
    private var windowExits: [UInt32: WindowExit] = [:]
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastScan: Double = 0
    private var lastWeatherTick: Double = 0
    private var fastTrackingUntil: Double = 0
    private var lastPointer = CGPoint.zero
    private var mouseWasDown = false
    private var layoutDirty = true
    private var primaryTop: CGFloat = 0
    private var stageEnabled = false
    private var lastIdleCheck: Double = 0
    private var lastDockScan: Double = 0
    private var desktopDock: DesktopDock?
    private var dockHitBounds = DockHitBounds()
    private var dockDisplays: [NSScreen] = []
    private var fallbackDockFrames: [UInt32: CGRect] = [:]
    private var dockFrames: [UInt32: CGRect] = [:]
    private var dockEdge: DesktopDock.Edge = .bottom
    private var spaceChangedAt: Double = -.infinity
    private var snowmanPerches: [UUID: SnowmanPerch] = [:]
    private var capturedPreviewInput: Double?
    private var previewStarted: Double = 0
    private var handles: [OrnamentHandleKey: (OverlayPanel, HandleView)] = [:]
    private var ballHandles: [Int: (OverlayPanel, HandleView)] = [:]
    private var workshop: SnowmanWorkshop?
    private var workshopDisplay: UInt32?
    private var workshopSource: UUID?
    private var ballDragStart: (id: Int, point: CGPoint)?
    private var picking: [OverlayPanel] = []
    private var lightDraft: LightDraft?
    private var snowRollGesture: SnowRollGesture?
    private var snowRollHandle: OverlayPanel?
    private var snowPointerMonitor: Any?
    private var giftHandles: [UUID: (UInt32, OverlayPanel)] = [:]
    private var fullscreenDisplays = Set<UInt32>()
    private var screensAsleep = false
    private var powerLimited = false
    private var lastPowerCheck: Double = -.infinity
    private var loopFPS: Double = 0
    private var dragSession: OrnamentDragSession?
    private var dragLayoutDirty = false
    private var lastHandlesShowing = false
    private var wasRunning = false
    private var reducedMotion = false
    private var lastSettings: SnowSettings?
    private var lastEditing = false
    private var lastSelection: UUID?
    private var lastIdleScene = false
    private var lastCanvasReducedMotion = false
    private var calendarDay: Date?
    private var lastStudioFrame: CGRect?
    private var studioPresentation: (number: Int, logicalFrame: CGRect, visibleFrame: CGRect?, checked: Double)?
    private let pid = ProcessInfo.processInfo.processIdentifier

    init(model: SnowModel) {
        self.model = model
        updateScreens()
        scheduleTimer(fps: 60)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated),
                                                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sleepDisplays), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleepDisplays), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wakeDisplays), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wakeDisplays), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func scheduleTimer(fps: Double) {
        guard fps != loopFPS || timer == nil else { return }
        timer?.invalidate()
        let next = Timer(timeInterval: 1 / fps, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        next.tolerance = 0.002
        RunLoop.main.add(next, forMode: .common)
        timer = next
        loopFPS = fps
    }

    @objc private func sleepDisplays() {
        screensAsleep = true
        timer?.invalidate()
        timer = nil
        monitorSnowPointer(false)
        cancelActivity()
        for screen in screens.values { screen.setVisibility(back: false, front: false) }
        for (panel, _) in handles.values { panel.orderOut(nil) }
        for (panel, _) in ballHandles.values { panel.orderOut(nil) }
        for (_, panel) in giftHandles.values { panel.orderOut(nil) }
    }

    @objc private func wakeDisplays() {
        guard screensAsleep else { return }
        screensAsleep = false
        lastTick = CACurrentMediaTime()
        lastWeatherTick = 0
        lastScan = 0
        layoutDirty = true
        scheduleTimer(fps: !screens.isEmpty && fullscreenDisplays.count == screens.count ? 12 : powerLimited ? 40 : 60)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitorSnowPointer(false)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for overlay in screens.values { overlay.setVisibility(back: false, front: false) }
        for (panel, _) in handles.values { panel.orderOut(nil) }
        for (_, panel) in giftHandles.values { panel.orderOut(nil) }
        cancelActivity()
        finishPicking(nil, reopen: false)
        cancelSnowman()
    }

    func updateScreens() {
        let external = NSScreen.screens
        dockDisplays = external
        primaryTop = external.first?.frame.maxY ?? 0
        studioPresentation = nil
        let ids = Set(external.map(\.snowScreenID))
        let displaysChanged = ids != Set(screens.keys) || external.contains { screens[$0.snowScreenID]?.frame != $0.frame }
        for key in Array(screens.keys) where !ids.contains(key) {
            screens[key]?.setVisibility(back: false, front: false)
            screens.removeValue(forKey: key)
        }
        for screen in external {
            let id = screen.snowScreenID
            if let overlay = screens[id] {
                overlay.frame = screen.frame
                overlay.usable = screen.visibleFrame
                overlay.front.setFrame(screen.frame, display: false)
                overlay.back.setFrame(screen.frame, display: false)
                continue
            }
            let overlay = ScreenOverlay(screen: screen, windowSnow: windowSnow)
            overlay.backView.paint = { [weak self, weak overlay] ink, dirty in
                if let overlay { self?.paint(ink, screen: overlay, isBack: true, dirty: dirty) }
            }
            overlay.frontView.paint = { [weak self, weak overlay] ink, dirty in
                if let overlay { self?.paint(ink, screen: overlay, isBack: false, dirty: dirty) }
            }
            screens[id] = overlay
        }
        lastScan = 0
        lastDockScan = 0
        layoutDirty = true
        if model.pickingWindow { finishPicking(nil) }
        if displaysChanged {
            cancelActivity()
            cancelOrnamentDrag()
            if model.buildingSnowman { cancelSnowman() }
        }
    }

    func clear() {
        cancelSnowRoll()
        if !windowExits.isEmpty { layoutDirty = true }
        windowExits.removeAll(keepingCapacity: true)
        windowSnow.clear()
        for screen in screens.values {
            screen.sim.clearAccumulation()
            screen.fallingSnowmen.removeAll()
            screen.treeSnow.removeAll()
            screen.rolledSnow = RolledSnow()
            screen.frontView.needsDisplay = true
        }
    }

    func runPlow() {
        guard model.running, model.settings.accumulate,
              let screen = screens.values.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? screens[NSScreen.screens.first?.snowScreenID ?? 0] else { return }
        if screen.sim.startPlow() {
            screen.frontView.needsDisplay = true
            model.feedback = "铲雪车已出发。"
        } else if screen.sim.plow != nil {
            model.feedback = "铲雪车正在清理屏幕底部。"
        }
    }

    func preview() {
        cancelActivity()
        cancelSnowman()
        model.hideStudio?()
        model.preview = true
        previewStarted = CACurrentMediaTime()
        capturedPreviewInput = nil
    }

    func beginPicking() {
        cancelActivity()
        if model.buildingSnowman { cancelSnowman() }
        guard picking.isEmpty else { return }
        if screens.isEmpty { finishPicking(nil); return }
        model.hideStudio?()
        showPicker(hint: "点击目标窗口 · 右键取消", onClick: { [weak self] point in
            guard let self else { return }
            let found = self.getWindows().first { !$0.widget && $0.rect.contains(point) }
            if let found {
                self.finishPicking(found.anchor)
            } else {
                self.model.feedback = "该位置没有可摆放装饰的窗口。请选择一个普通应用窗口。"
                self.finishPicking(nil)
            }
        }, onCancel: { [weak self] in self?.finishPicking(nil) })
    }

    private func showPicker(hint: String, onClick: @escaping (CGPoint) -> Void, onCancel: @escaping () -> Void,
                            drag: ((CGPoint) -> Void)? = nil, up: ((CGPoint) -> Void)? = nil,
                            key: ((UInt16) -> Void)? = nil, wheel: ((CGFloat) -> Void)? = nil,
                            guides: ((UInt32, Ink) -> Void)? = nil) {
        let pointer = NSEvent.mouseLocation
        for screen in screens.values where !fullscreenDisplays.contains(screen.id) {
            let panel = OverlayPanel(frame: screen.frame, level: .init(rawValue: overlayLevel.rawValue + 2),
                                     interactive: true, keyboard: key != nil)
            let view = HandleView()
            view.selectionHint = hint
            view.down = onClick
            view.remove = onCancel
            view.drag = drag
            view.up = up
            view.key = key
            view.wheel = wheel
            if let guides { view.guides = { [id = screen.id] ink in guides(id, ink) } }
            panel.contentView = view
            picking.append(panel)
            panel.orderFrontRegardless()
            if key != nil && screen.frame.contains(pointer) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }

    func finishPicking(_ anchor: WindowAnchor?, reopen: Bool = true) {
        let active = model.pickingWindow
        dismissPicker()
        model.finishPickingWindow(anchor)
        if active && reopen { model.showStudio?() }
    }

    private func dismissPicker() {
        for panel in picking { panel.orderOut(nil) }
        picking.removeAll()
    }

    private func cancelActivity(reopen: Bool = false) {
        cancelSnowRoll()
        guard lightDraft != nil else { return }
        lightDraft = nil
        dismissPicker()
        layoutDirty = true
        if reopen { model.showStudio?() }
    }

    private func prepareActivity() -> Bool {
        guard screens.values.contains(where: { !fullscreenDisplays.contains($0.id) }) else {
            model.feedback = "请先回到普通桌面。"
            return false
        }
        if model.pickingWindow { finishPicking(nil, reopen: false) }
        cancelSnowman()
        cancelActivity()
        model.editMode = false
        model.hideStudio?()
        return true
    }

    private var canRollSnow: Bool {
        model.settings.rollSnowballs && model.settings.accumulate && !screensAsleep && !model.preview
            && !model.pickingWindow && !model.editMode && !model.buildingSnowman && lightDraft == nil
    }

    private func monitorSnowPointer(_ enabled: Bool) {
        if enabled && snowPointerMonitor == nil {
            snowPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.refreshSnowRollHandle(at: NSEvent.mouseLocation)
            }
        } else if !enabled, let snowPointerMonitor {
            NSEvent.removeMonitor(snowPointerMonitor)
            self.snowPointerMonitor = nil
        }
    }

    private func snowRollHit(at point: CGPoint) -> SnowRollHit? {
        guard canRollSnow, presentedStudio()?.frame.contains(point) != true,
              let screen = screens.values.first(where: { $0.frame.contains(point) && !fullscreenDisplays.contains($0.id) }),
              !handles.values.contains(where: { $0.0.isVisible && $0.0.frame.contains(point) }),
              !giftHandles.values.contains(where: { $0.1.isVisible && $0.1.frame.contains(point) }) else { return nil }
        let local = screen.local(CGRect(origin: point, size: .zero)).origin
        for ball in screen.rolledSnow.paintedBalls.reversed() {
            if let hit = SnowballPropArt.hit(at: local, on: ball), let prop = ball.props.first(where: { $0.id == hit.id }) {
                return SnowRollHit(screen: screen, rect: hit.frame, ball: ball, prop: prop)
            }
            if let rect = ball.grabFrame(at: local) { return SnowRollHit(screen: screen, rect: rect, ball: ball) }
        }
        return screen.sim.rollHandle(at: local).map { SnowRollHit(screen: screen, rect: $0, ball: nil) }
    }

    private func refreshSnowRollHandle(at point: CGPoint) {
        if !canRollSnow { cancelSnowRoll(); return }
        guard snowRollGesture == nil, NSEvent.pressedMouseButtons == 0 else { return }
        guard let hit = snowRollHit(at: point) else { snowRollHandle?.orderOut(nil); return }
        let frame = hit.screen.global(hit.rect).intersection(hit.screen.frame)
        guard frame.width >= 1, frame.height > 0.45 else { snowRollHandle?.orderOut(nil); return }
        let panel: OverlayPanel
        if let existing = snowRollHandle { panel = existing }
        else {
            panel = OverlayPanel(frame: frame, level: .init(rawValue: overlayLevel.rawValue + 1), interactive: true)
            let view = SnowRollView(frame: .zero)
            view.press = { [weak self] point, time in self?.beginSnowRoll(at: point, time: time) }
            view.drag = { [weak self] point, time in self?.rollSnow(to: point, time: time) }
            view.release = { [weak self] point, time in self?.releaseSnow(at: point, time: time) }
            view.menuAt = { [weak self] point, view in self?.snowRollMenu(at: point, view: view) }
            panel.contentView = view
            snowRollHandle = panel
        }
        panel.contentView?.setAccessibilityLabel(hit.prop?.kind.title ?? (hit.ball == nil ? "搓雪球" : "雪球"))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func snowRollMenu(at point: CGPoint, view: SnowRollView) -> NSMenu? {
        guard let hit = snowRollHit(at: point), let ball = hit.ball else { return nil }
        let screen = hit.screen
        let id = ball.id
        let local = screen.local(CGRect(origin: point, size: .zero)).origin
        let attachment = p((local.x - ball.center.x) / ball.radius, (local.y - ball.center.y) / ball.radius)
        let menu = NSMenu()
        let keptFree = ball.freeStack || !model.settings.automaticallyFinishSnowman
        let free = view.item("自由堆叠") { [weak self, weak screen] in
            guard let self else { return }
            screen?.rolledSnow.setFree(!keptFree, for: id)
            self.layoutDirty = true
        }
        free.state = keptFree ? .on : .off
        free.isEnabled = model.settings.automaticallyFinishSnowman
            && screen.rolledSnow.canToggleFree(for: id)
        menu.autoenablesItems = false
        menu.addItem(free)
        if screen.rolledSnow.canFinishStack(containing: id) {
            menu.addItem(view.item("堆成雪人") { [weak self] in self?.finishRolledSnowman(containing: id) })
        }
        for choices: [SnowballPropChoice] in [[.eyes, .carrot, .coal], [.leftTwig, .rightTwig], [.feltHat, .woolHat, .scarf]] {
            menu.addItem(.separator())
            for choice in choices {
                let icon = SnowballPropArt.thumbnail(for: choice.kind)
                menu.addItem(view.item(choice.kind.title, image: icon) { [weak self, weak screen] in
                    guard let screen, let current = screen.rolledSnow.ball(id) else { return }
                    let anchor = p(current.center.x + attachment.x * current.radius, current.center.y + attachment.y * current.radius)
                    screen.rolledSnow.addProp(choice, to: id, at: anchor)
                    self?.layoutDirty = true
                })
            }
        }
        if !ball.props.isEmpty {
            menu.addItem(.separator())
            if let prop = hit.prop {
                menu.addItem(view.item("取下" + prop.kind.title) { [weak self, weak screen] in
                    screen?.rolledSnow.removeProp(prop.id, from: id)
                    self?.layoutDirty = true
                })
            }
            menu.addItem(view.item("取下这颗雪球的全部道具") { [weak self, weak screen] in
                screen?.rolledSnow.removeProp(nil, from: id)
                self?.layoutDirty = true
            })
        }
        return menu
    }

    private func beginSnowRoll(at point: CGPoint, time: Double) {
        guard let hit = snowRollHit(at: point) else { return }
        let local = hit.screen.local(CGRect(origin: point, size: .zero)).origin
        let prop: PropDrag?
        if let piece = hit.prop, let ball = hit.ball {
            let anchor = piece.worldAnchor(on: ball)
            prop = PropDrag(ball: ball.id, prop: piece.id, offset: CGVector(dx: anchor.x - local.x, dy: anchor.y - local.y))
        } else { prop = nil }
        snowRollGesture = SnowRollGesture(display: hit.screen.id, start: local, time: time, ball: hit.ball?.id, prop: prop)
    }

    private func rollSnow(to point: CGPoint, time: Double) {
        guard canRollSnow, var gesture = snowRollGesture, let screen = screens[gesture.display] else { return }
        let local = screen.local(CGRect(origin: point, size: .zero)).origin
        if let piece = gesture.prop {
            guard hypot(local.x - gesture.start.x, local.y - gesture.start.y) > 1.6 || gesture.started else { return }
            screen.rolledSnow.moveProp(piece.prop, on: piece.ball, to: p(local.x + piece.offset.dx, local.y + piece.offset.dy))
            gesture.started = true
            snowRollGesture = gesture
            return
        }
        if !gesture.started {
            guard hypot(local.x - gesture.start.x, local.y - gesture.start.y) > 2.5 else { return }
            screen.rolledSnow.take(at: gesture.start, time: max(gesture.time, time - 0.021),
                                   snow: &screen.sim, preferred: gesture.ball)
            gesture.started = true
            snowRollGesture = gesture
        }
        screen.rolledSnow.roll(to: local, time: time, snow: &screen.sim, within: screen.frame.size, reduced: reducedMotion)
    }

    private func releaseSnow(at point: CGPoint, time: Double) {
        rollSnow(to: point, time: time)
        let automatic = model.settings.automaticallyFinishSnowman
        if let gesture = snowRollGesture, gesture.started, let screen = screens[gesture.display] {
            if gesture.prop != nil {
                layoutDirty = true
            } else if let stacked = screen.rolledSnow.release(at: time, freely: !automatic, within: screen.frame.size), automatic {
                finishRolledSnowman(containing: stacked, minimum: 3, showWardrobe: false, automatic: true)
            }
        }
        snowRollGesture = nil
        refreshSnowRollHandle(at: point)
    }

    private func cancelSnowRoll() {
        if let gesture = snowRollGesture, gesture.started, gesture.prop == nil {
            screens[gesture.display]?.rolledSnow.release(at: .infinity, stacking: false)
        }
        snowRollGesture = nil
        snowRollHandle?.orderOut(nil)
    }

    var hasRolledSnowman: Bool { screens.values.contains { $0.rolledSnow.hasStack } }

    func finishRolledSnowman(containing member: UUID? = nil, minimum: Int = 2, showWardrobe: Bool = true,
                            automatic: Bool = false) {
        for screen in screens.values {
            guard let stack = screen.rolledSnow.takeStack(containing: member, minimum: minimum, automatic: automatic) else { continue }
            let point = screen.global(CGRect(origin: stack.base.center, size: .zero)).origin
            let x = (point.x - screen.usable.minX) / screen.usable.width
            var ornament = Ornament(kind: .snowman, display: screen.id, x: Double(x), y: 0.1)
            ornament.scale = min(2, max(0.38, stack.base.radius / SnowmanArt.radii[0]))
            ornament.snowballs = stack.count
            ornament.snowmanFollowsGround = true
            if case let .window(id) = stack.surface, let target = windows.first(where: { $0.id == id }) {
                ornament.anchor = target.anchor
                ornament.x = Double((point.x - target.rect.minX) / target.rect.width)
            }
            model.add(ornament)
            layoutDirty = true
            if showWardrobe { model.showWardrobe?(ornament.id, nil) }
            return
        }
    }

    func beginHangingLights(_ id: UUID? = nil) {
        guard prepareActivity() else { return }
        let item = model.settings.ornaments.first { $0.id == id && $0.lightStrand != nil }
        lightDraft = LightDraft(ornament: item)
        if let item, let strand = item.lightStrand, let screen = screens[item.display], !fullscreenDisplays.contains(screen.id) {
            lightDraft = LightDraft(display: screen.id, ornament: item, hooks: strand.anchors(in: screen.frame.size), slack: strand.slack)
        }
        showPicker(hint: "点一下挂钩 · 拖动可调整 · 滚轮调松紧 · 回车或右键保存 · Esc 取消",
                   onClick: { [weak self] point in self?.placeHook(at: point) },
                   onCancel: { [weak self] in self?.finishLights() },
                   drag: { [weak self] point in self?.moveHook(to: point) },
                   up: { [weak self] _ in self?.lightDraft?.movingHook = nil },
                   key: { [weak self] key in
                       if key == 53 { self?.cancelActivity(reopen: true) }
                       if key == 36 || key == 76 { self?.finishLights() }
                       if key == 51 { self?.undoHook() }
                   }, wheel: { [weak self] delta in
                       guard let self, let draft = self.lightDraft else { return }
                       self.lightDraft?.slack = min(2.8, max(0.15, draft.slack + delta * 0.035))
                       self.refreshPickerGuides()
                   }, guides: { [weak self] display, ink in self?.drawLightGuides(on: display, ink: ink) })
        layoutDirty = true
    }

    private func refreshPickerGuides() {
        for panel in picking { panel.contentView?.needsDisplay = true }
    }

    private func undoHook() {
        if lightDraft?.hooks.isEmpty == false { lightDraft?.hooks.removeLast() }
        lightDraft?.movingHook = nil
        refreshPickerGuides()
    }

    private func placeHook(at global: CGPoint) {
        guard var draft = lightDraft, let screen = screens.values.first(where: { $0.frame.contains(global) }),
              draft.display == nil || draft.display == screen.id else { return }
        let point = lightHook(global, on: screen)
        draft.display = screen.id
        if let index = draft.hooks.firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) < 12 }) {
            draft.movingHook = index
        } else if draft.hooks.count < 22 {
            draft.hooks.append(point)
            draft.movingHook = draft.hooks.count - 1
        }
        lightDraft = draft
        refreshPickerGuides()
    }

    private func moveHook(to global: CGPoint) {
        guard var draft = lightDraft, let display = draft.display, let screen = screens[display],
              let hook = draft.movingHook, draft.hooks.indices.contains(hook) else { return }
        draft.hooks[hook] = lightHook(global, on: screen)
        lightDraft = draft
        refreshPickerGuides()
    }

    private func lightHook(_ global: CGPoint, on screen: ScreenOverlay) -> CGPoint {
        let point = screen.local(CGRect(origin: global, size: .zero)).origin
        func snap(_ coordinate: CGFloat, edge: CGFloat) -> CGFloat {
            if coordinate < 20 { return 12 }
            if edge - coordinate < 20 { return edge - 12 }
            return coordinate
        }
        return p(snap(point.x, edge: screen.frame.width), snap(point.y, edge: screen.frame.height))
    }

    private func finishLights() {
        guard let draft = lightDraft, let id = draft.display, let screen = screens[id], draft.hooks.count > 1 else {
            cancelActivity(reopen: true)
            return
        }
        let hooks = draft.hooks.map { p($0.x / screen.frame.width, $0.y / screen.frame.height) }
        let strand = LightStrand(hooks: hooks, slack: draft.slack)
        var item = draft.ornament ?? Ornament(kind: .lights, display: id, x: 0.5, y: 0.5)
        if draft.ornament == nil { item.lightMotion = .twinkle }
        item.display = id
        item.anchor = nil
        item.lightStrand = strand
        if draft.ornament == nil { model.add(item) }
        else { model.change(item.id) { $0 = item } }
        cancelActivity(reopen: true)
    }

    private func drawLightGuides(on id: UInt32, ink: Ink) {
        guard let draft = lightDraft, let screen = screens[id], draft.display == id else { return }
        var anchors = draft.hooks
        let pointer = NSEvent.mouseLocation
        if draft.movingHook == nil, screen.frame.contains(pointer), anchors.count < 22 {
            anchors.append(lightHook(pointer, on: screen))
        }
        if anchors.count > 1 {
            var item = draft.ornament ?? Ornament(kind: .lights, display: id, x: 0.5, y: 0.5)
            item.lightStrand = LightStrand(hooks: anchors.map { p($0.x / screen.frame.width, $0.y / screen.frame.height) }, slack: draft.slack)
            DecorationArt.freeLights(item, screen: screen.frame.size, brush: nil, wind: 0, ink: ink, time: 0)
        }
        for hook in draft.hooks {
            ink.circle(hook.x, hook.y, 7, 0x12304c)
            ink.circle(hook.x, hook.y, 4.2, 0xa7efff)
        }
    }

    func sendSleigh() {
        let pointer = NSEvent.mouseLocation
        let available = screens.values.filter { !fullscreenDisplays.contains($0.id) }
        guard let screen = available.first(where: { $0.frame.contains(pointer) }) ?? available.first else { return }
        screen.festivities.launch()
        model.feedback = "雪橇已经出发。"
    }

    @objc private func spaceChanged() {
        spaceChangedAt = CACurrentMediaTime()
        studioPresentation = nil
        snowmanPerches.removeAll()
        windows.removeAll()
        shakes.removeAll()
        for (id, exit) in windowExits where exit.airborne { resolveWindowExit(id, didDisappear: false) }
        windowExits.removeAll(keepingCapacity: true)
        windowSnow.clear()
        layoutDirty = true
        lastScan = 0
        cancelActivity()
        cancelOrnamentDrag()
        cancelSnowman()
    }

    private func getWindows() -> [DesktopWindow] {
        let settingsWindow = studioInSpace.flatMap { UInt32(exactly: $0.windowNumber) }
        return DesktopWindow.onscreen(primaryTop: primaryTop, ignoring: pid, includingOwnWindow: settingsWindow,
                                      stageDisplays: stageDisplays)
    }

    private var studioInSpace: NSWindow? {
        guard let studio = studioWindow?(), studio.isVisible, !studio.isMiniaturized, studio.isOnActiveSpace,
              studio.alphaValue > 0.15, !NSApp.isHidden else { return nil }
        return studio
    }

    private func presentedStudio(at now: Double = CACurrentMediaTime()) -> (id: UInt32, frame: CGRect)? {
        guard let studio = studioInSpace, studio.occlusionState.contains(.visible),
              let id = UInt32(exactly: studio.windowNumber) else {
            studioPresentation = nil
            return nil
        }
        let number = studio.windowNumber
        let logicalFrame = studio.frame
        if let cached = studioPresentation, cached.number == number, cached.logicalFrame == logicalFrame,
           now - cached.checked < 1.0 / 30 {
            return cached.visibleFrame.map { (id, $0) }
        }
        let frame = DesktopWindow.presentedFrame(of: number, primaryTop: primaryTop)
        studioPresentation = (number, logicalFrame, frame, now)
        return frame.map { (id, $0) }
    }

    private var stageDisplays: [CGRect] { stageEnabled ? screens.values.map(\.frame) : [] }

    @objc private func applicationActivated() {
        guard stageEnabled else { return }
        lastScan = 0
        fastTrackingUntil = CACurrentMediaTime() + 0.34
    }

    func startSnowman() {
        cancelActivity()
        guard !screens.isEmpty else { return }
        if model.pickingWindow { finishPicking(nil, reopen: false) }
        cancelSnowman()
        model.buildingSnowman = true
        model.hideStudio?()
        showPicker(hint: "点击一个窗口或空白桌面来堆雪人 · 右键取消",
                   onClick: { [weak self] point in self?.placeWorkshop(at: point) },
                   onCancel: { [weak self] in self?.cancelSnowman(reopen: true) })
    }

    func cancelSnowman(reopen: Bool = false) {
        guard model.buildingSnowman || workshop != nil else { return }
        dismissPicker()
        workshop = nil
        workshopDisplay = nil
        workshopSource = nil
        ballDragStart = nil
        layoutDirty = true
        model.buildingSnowman = false
        for (panel, _) in ballHandles.values { panel.orderOut(nil) }
        ballHandles.removeAll()
        for screen in screens.values { screen.frontView.needsDisplay = true }
        if reopen { model.showStudio?() }
    }

    func assembleSnowman() {
        guard workshop != nil else { return }
        let platforms = workshopPlatforms()
        workshop?.assemble(on: platforms)
        finishWorkshopIfReady(platforms)
    }

    private func knockSnowman(_ ornament: Ornament, from frame: CGRect, on screen: ScreenOverlay) {
        guard !model.editMode, !model.buildingSnowman, !model.preview, !model.pickingWindow else { return }
        let direction: CGFloat = frame.midX < screen.frame.midX ? 1 : -1
        workshopSource = ornament.id
        workshopDisplay = screen.id
        workshop = SnowmanWorkshop(knocking: ornament, from: frame, direction: direction, reduced: reducedMotion)
        model.buildingSnowman = true
        snowmanPerches.removeValue(forKey: ornament.id)
        removeHandles(for: [ornament.id])
        layoutDirty = true
        updateBallHandles()
    }

    private func placeWorkshop(at point: CGPoint) {
        dismissPicker()
        guard let screen = screens.values.first(where: { $0.frame.contains(point) }) else {
            cancelSnowman(reopen: true)
            return
        }
        windows = getWindows()
        let hasOrnaments = model.settings.ornamentsVisible && !model.settings.ornaments.isEmpty
        let studio = presentedStudio()?.frame
        for display in screens.values { updateLayout(on: display, studio: studio, hasOrnaments: hasOrnaments) }
        let platforms = workshopPlatforms()
        let clicked = windows.first { !$0.widget && $0.rect.contains(point) }
        let shelf = clicked.flatMap { window in
            platforms
                .filter { $0.id == .window(window.id) && $0.span.upperBound - $0.span.lowerBound >= 120
                    && $0.top + 78 < screen.usable.maxY }
                .min {
                    abs(($0.span.lowerBound + $0.span.upperBound) / 2 - point.x)
                        < abs(($1.span.lowerBound + $1.span.upperBound) / 2 - point.x)
                }
        }
        let dock = platforms.first {
            $0.id == .dock(screen.id) && $0.span.contains(point.x) && $0.span.upperBound - $0.span.lowerBound >= 120
        }
        guard let platform = shelf ?? dock ?? platforms.first(where: { $0.id == .ground(screen.id) }) else {
            cancelSnowman(reopen: true)
            return
        }
        workshopDisplay = screen.id
        workshop = SnowmanWorkshop(platform: platform, near: point.x)
        updateBallHandles()
        screen.frontView.needsDisplay = true
    }

    private func workshopPlatforms() -> [SnowballPlatform] {
        var platforms: [SnowballPlatform] = []
        let ordinary = Dictionary(uniqueKeysWithValues: windows.filter { !$0.widget }.map { ($0.id, $0) })
        for screen in screens.values {
            let ground = CGRect(x: screen.frame.minX + 10, y: screen.frame.minY,
                                width: max(1, screen.frame.width - 20), height: 1)
            platforms.append(SnowballPlatform(id: .ground(screen.id), frame: ground,
                                               span: ground.minX...ground.maxX, anchor: nil))
            if dockEdge == .bottom, let dock = dockFrames[screen.id], dock.width > 20 {
                let shelf = dock.insetBy(dx: 8, dy: 0).offsetBy(dx: 0, dy: 1)
                platforms.append(SnowballPlatform(id: .dock(screen.id), frame: shelf,
                                                   span: shelf.minX...shelf.maxX, anchor: nil))
            }
            for surface in screen.sim.surfaces {
                guard case let .window(id) = surface.id, let window = ordinary[id] else { continue }
                for range in surface.visible {
                    platforms.append(SnowballPlatform(id: .window(id), frame: window.rect,
                                                       span: (range.lowerBound + screen.frame.minX)...(range.upperBound + screen.frame.minX),
                                                       anchor: window.anchor))
                }
            }
        }
        return platforms
    }

    private func updateBallHandles() {
        guard let workshop else { return }
        for ball in workshop.balls where workshop.revealed(ball.id) {
            let frame = CGRect(x: ball.center.x - ball.radius, y: ball.center.y - ball.radius,
                               width: ball.radius * 2, height: ball.radius * 2)
            let panel: OverlayPanel
            if let existing = ballHandles[ball.id]?.0 {
                panel = existing
                if panel.frame != frame { panel.setFrame(frame, display: false) }
            } else {
                panel = OverlayPanel(frame: frame, level: .init(rawValue: overlayLevel.rawValue + 1), interactive: true)
                let view = HandleView()
                let id = ball.id
                let tone = workshop.tone(for: ball)
                view.setAccessibilityLabel(["大雪球", "中雪球", "小雪球"][tone])
                if workshopSource != nil {
                    view.down = { [weak self] point in self?.ballDragStart = (id, point) }
                    view.drag = { [weak self] point in self?.dragLooseBall(id, to: point) }
                    view.up = { [weak self] point in
                        guard let self else { return }
                        self.dragLooseBall(id, to: point)
                        self.ballDragStart = nil
                        let platforms = self.workshopPlatforms()
                        if self.workshop?.held == id {
                            self.workshop?.release(on: platforms)
                        } else {
                            self.workshop?.rebuild(at: id, on: platforms)
                        }
                        self.finishWorkshopIfReady(platforms)
                    }
                } else {
                    view.down = { [weak self] point in self?.workshop?.grab(id, at: point) }
                    view.drag = { [weak self] point in
                        guard let self else { return }
                        self.workshop?.drag(to: point, platforms: self.workshopPlatforms())
                    }
                    view.up = { [weak self] point in
                        guard let self else { return }
                        let platforms = self.workshopPlatforms()
                        self.workshop?.drag(to: point, platforms: platforms)
                        self.workshop?.release(on: platforms)
                        self.finishWorkshopIfReady(platforms)
                    }
                }
                view.removalTitle = "结束堆雪人"
                view.remove = { [weak self] in self?.cancelSnowman() }
                panel.contentView = view
                ballHandles[id] = (panel, view)
                panel.orderFrontRegardless()
            }
        }
    }

    private func dragLooseBall(_ id: Int, to point: CGPoint) {
        guard let start = ballDragStart, start.id == id,
              workshop?.held == id || hypot(point.x - start.point.x, point.y - start.point.y) > 3 else { return }
        if workshop?.held == nil { workshop?.grab(id, at: start.point) }
        workshop?.drag(to: point, platforms: workshopPlatforms())
    }

    private func finishWorkshopIfReady(_ platforms: [SnowballPlatform]) {
        guard let workshop, let base = workshop.balls.first,
              let platform = workshop.completedPlatform(in: platforms),
              let screen = screens.values.first(where: { $0.frame.contains(base.center) }) else { return }
        let source = model.settings.ornaments.first { $0.id == workshopSource }
        let scale = source?.scale ?? SnowmanArt.workshopScale
        let w = OrnamentKind.snowman.size.width * scale
        let h = OrnamentKind.snowman.size.height * scale
        let frame = CGRect(x: base.center.x - w / 2, y: platform.top - (h - SnowmanArt.baseline * scale),
                           width: w, height: h)
        let x = platform.anchor == nil
            ? (frame.midX - screen.usable.minX) / screen.usable.width : platform.fraction(at: base.center.x)
        let y = (frame.midY - screen.usable.minY) / screen.usable.height
        if let source {
            cancelSnowman()
            model.change(source.id) {
                $0.display = screen.id
                $0.x = x
                $0.y = y
                $0.anchor = platform.anchor
                $0.rotation = 0
                $0.snowmanFollowsGround = true
            }
            return
        }
        var finished = Ornament(kind: .snowman, display: screen.id, x: x, y: y)
        finished.anchor = platform.anchor
        finished.snowmanFollowsGround = true
        finished.scale = scale
        finished.hat = .none
        finished.costume = SnowmanCostume()
        cancelSnowman()
        model.add(finished)
        model.showWardrobe?(finished.id, frame)
    }

    private func updateSnowmanPerches(now: Double) {
        guard model.settings.ornamentsVisible, now - spaceChangedAt > 0.85, !model.preview else {
            snowmanPerches.removeAll()
            return
        }
        for screen in screens.values {
            for (ornament, rect, target) in screen.placements where ornament.kind == .snowman && target != nil {
                if screen.frontView.bounds.contains(p(rect.midX, rect.maxY - 7)) {
                    snowmanPerches[ornament.id] = SnowmanPerch(display: screen.id, ornament: ornament, bounds: rect)
                }
            }
        }
        let ornaments = Dictionary(uniqueKeysWithValues: model.settings.ornaments.map { ($0.id, $0) })
        for id in Array(snowmanPerches.keys) {
            guard var perch = snowmanPerches[id], let anchor = ornaments[id]?.anchor else {
                snowmanPerches.removeValue(forKey: id)
                continue
            }
            if layoutAnchor(anchor) != nil {
                perch.lostAt = nil
                snowmanPerches[id] = perch
            } else if let lostAt = perch.lostAt, now - lostAt > 0.22 {
                if let screen = screens[perch.display] {
                    let sway: CGFloat = reducedMotion ? 0 : (perch.bounds.midX < screen.frame.width / 2 ? 19 : -19)
                    screen.fallingSnowmen.append(FallingSnowman(ornament: perch.ornament, rect: perch.bounds, sway: sway))
                }
                snowmanPerches.removeValue(forKey: id)
                model.remove(id)
            } else if perch.lostAt == nil {
                perch.lostAt = now
                snowmanPerches[id] = perch
            }
        }
    }

    @objc private func tick() {
        guard !screensAsleep else { return }
        let now = CACurrentMediaTime()
        let delta = min(0.065, max(0.001, now - lastTick))
        var dayChanged = false
        lastTick = now
        if now - lastIdleCheck > 0.22 {
            lastIdleCheck = now
            readIdle(now)
            reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            stageEnabled = CFPreferencesCopyAppValue("GloballyEnabled" as CFString,
                                                     "com.apple.WindowManager" as CFString) as? Bool ?? false
            let day = Calendar.current.startOfDay(for: Date())
            dayChanged = day != calendarDay
            calendarDay = day
        }
        let settings = model.settings
        if now - lastPowerCheck >= 1.2 {
            lastPowerCheck = now
            powerLimited = settings.adaptivePower && DesktopWeatherPower.limited
        } else if !settings.adaptivePower { powerLimited = false }
        scheduleTimer(fps: !screens.isEmpty && fullscreenDisplays.count == screens.count ? 12 : powerLimited ? 40 : 60)
        if let source = workshopSource, !settings.ornamentsVisible || !settings.ornaments.contains(where: { $0.id == source }) {
            cancelSnowman()
        }
        let running = model.running
        if wasRunning && !running && settings.enabled {
            // Leaving the idle-only mode still restores the regular desktop immediately.
            clear()
            for screen in screens.values { screen.sim.flakes.removeAll(keepingCapacity: true) }
        }
        let hasOrnaments = settings.ornamentsVisible && !settings.ornaments.isEmpty
        let showingHandles = hasOrnaments && !model.preview && !model.pickingWindow
        if let dragSession, !showingHandles || !settings.ornaments.contains(where: { $0.id == dragSession.handle.ornament }) {
            cancelOrnamentDrag()
        }
        let tracksSnow = settings.accumulate && (running || !windowSnow.isEmpty || screens.values.contains {
            $0.sim.hasAccumulation || $0.sim.weatherAnimating || $0.sim.fallingSnowAnimating
                || !$0.fallingSnowmen.isEmpty || !$0.rolledSnow.isEmpty
        })
        let active = running || tracksSnow || hasOrnaments || model.buildingSnowman || lightDraft != nil
            || screens.values.contains {
                !$0.fallingSnowmen.isEmpty || !$0.plowedSnowmen.isEmpty || !$0.plowedDecorations.isEmpty
                    || $0.sim.weatherAnimating || $0.sim.fallingSnowAnimating || $0.festivities.active || !$0.rolledSnow.isEmpty
            }
        let studio = presentedStudio(at: now)?.frame
        let studioChanged = studio != lastStudioFrame
        let changed = settings != lastSettings || model.editMode != lastEditing || studioChanged || wasRunning != running
        if lastSettings?.accumulate == true && !settings.accumulate {
            for screen in screens.values { screen.sim.clearAccumulation() }
        }
        lastSettings = settings
        lastEditing = model.editMode
        lastStudioFrame = studio

        wasRunning = running
        let tracksWindows = hasOrnaments && settings.ornaments.contains { $0.anchor != nil }
        let mouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        let pointer = NSEvent.mouseLocation
        let previousPointer = lastPointer
        if mouseDown != mouseWasDown || (mouseDown && pointer != lastPointer) {
            fastTrackingUntil = now + 0.18
        }
        lastPointer = pointer
        mouseWasDown = mouseDown
        let dockChanged = active && updateDock(at: now)
        if !tracksSnow && !windowExits.isEmpty { windowExits.removeAll(keepingCapacity: true) }
        let fastTracking = (tracksSnow || tracksWindows || model.buildingSnowman) && now < fastTrackingUntil
        let allCovered = !screens.isEmpty && fullscreenDisplays.count == screens.count
        let scanInterval = allCovered ? 0.30 : powerLimited ? 0.15 : (running || tracksWindows ? 0.082 : 0.21)
        let needsScan = active && (studioChanged || fastTracking || now - lastScan >= scanInterval)
        let oldFrontWindow = windows.first(where: { !$0.widget })?.rect ?? .null
        var geometryChanged = false
        var shaken: [(id: UInt32, speed: CGFloat)] = []
        if needsScan {
            lastScan = now
            let previous = windows
            windows = getWindows()
            geometryChanged = previous != windows
            if geometryChanged && tracksSnow { fastTrackingUntil = max(fastTrackingUntil, now + 0.10) }
            let ids = Set(windows.map(\.id))
            for lost in previous where !ids.contains(lost.id) {
                let exit = windowExits.removeValue(forKey: lost.id)
                if tracksSnow && !lost.widget && now - spaceChangedAt > 0.35 {
                    if let exit {
                        _ = windowSnow.take(lost.id)
                        if exit.airborne {
                            resolveWindowExit(lost.id, didDisappear: true)
                        } else {
                            dropWindowSnow(exit.pack, from: exit.edges, horizontalSpeed: 0)
                        }
                    } else {
                        dropWindowSnow(lost.id, horizontalSpeed: 0)
                    }
                } else {
                    _ = windowSnow.take(lost.id)
                    if exit?.airborne == true { resolveWindowExit(lost.id, didDisappear: false) }
                }
            }
            if tracksSnow { trackWindowExits(from: previous, holdingMouse: mouseDown, at: now) }
            for key in Array(shakes.keys) where !ids.contains(key) { shakes.removeValue(forKey: key) }
            for window in windows where !window.widget {
                if shakes[window.id] == nil || windowExits[window.id] != nil {
                    shakes[window.id] = WindowShake(rect: window.rect)
                    continue
                }
                if shakes[window.id]?.update(window.rect, at: now) == true, let fling = shakes[window.id]?.fling, tracksSnow {
                    shaken.append((window.id, fling))
                }
            }
        }

        let hidden = settings.avoidFullscreen ? Set(screens.values.filter { screen in
            windows.contains { !$0.widget && DesktopWeatherPower.fullscreen($0.rect, on: screen.frame) }
        }.map(\.id)) : []
        if hidden != fullscreenDisplays {
            fullscreenDisplays = hidden
            cancelActivity()
            if model.pickingWindow { finishPicking(nil, reopen: false) }
            if let display = workshopDisplay, hidden.contains(display) { cancelSnowman() }
            if let dragSession, hidden.contains(dragSession.handle.display) { cancelOrnamentDrag() }
            layoutDirty = true
        }

        let fullLayout = layoutDirty || changed
        let draggedID = dragLayoutDirty ? dragSession?.handle.ornament : nil
        let needsLayout = fullLayout || geometryChanged || dockChanged || dragLayoutDirty
        dragLayoutDirty = false
        var layoutRegions: [UInt32: [CGRect]] = [:]
        if needsLayout {
            let movedDecoration: ((Ornament, CGRect, DesktopWindow?)) -> Bool = { placement in
                let (ornament, _, target) = placement
                return target != nil || ornament.id == draggedID || (dockChanged && ornament.kind == .snowman)
            }
            for screen in screens.values {
                let oldSurfaces = fullLayout ? [] : screen.sim.surfaces
                let oldDecorations = fullLayout ? [] : screen.placements.filter(movedDecoration)
                updateLayout(on: screen, studio: studio, hasOrnaments: hasOrnaments)
                if !fullLayout {
                    let newSurfaces = screen.sim.surfaces
                    let before = Dictionary(uniqueKeysWithValues: oldSurfaces.map { ($0.id, $0) })
                    let after = Dictionary(uniqueKeysWithValues: newSurfaces.map { ($0.id, $0) })
                    var regions = oldSurfaces.filter { after[$0.id] != $0 }.map(\.paintBounds)
                    regions += newSurfaces.filter { before[$0.id] != $0 }.map(\.paintBounds)
                    if geometryChanged || draggedID != nil || dockChanged {
                        let moved = oldDecorations + screen.placements.filter(movedDecoration)
                        for (ornament, rect, _) in moved {
                            regions.append(ornament.paintBounds(in: rect))
                        }
                    }
                    layoutRegions[screen.id] = regions
                }
            }
            layoutDirty = false
        }
        for shake in shaken {
            dropWindowSnow(shake.id, horizontalSpeed: shake.speed)
        }
        if needsScan { updateSnowmanPerches(now: now) }
        if workshop != nil {
            let platforms = workshopPlatforms()
            workshop?.advance(delta, platforms: platforms)
            finishWorkshopIfReady(platforms)
            updateBallHandles()
        }

        let idleScene = model.preview || (running && model.idleActive && settings.idleSeconds > 0)
        let canvasChanged = lastIdleScene != idleScene || lastCanvasReducedMotion != reducedMotion
            || lastSelection != model.selectedOrnament || (dayChanged && hasOrnaments)
        lastIdleScene = idleScene
        lastCanvasReducedMotion = reducedMotion
        lastSelection = model.selectedOrnament
        let canSweep = tracksSnow && !idleScene && !mouseDown && !model.editMode && !model.pickingWindow
            && !model.buildingSnowman && snowRollGesture == nil && lightDraft == nil && studio?.contains(pointer) != true
        let behind = settings.layer == .behindWindows && !idleScene
        let animatedDecorations = hasOrnaments && !reducedMotion && settings.ornaments.contains {
            $0.kind == .tree || $0.kind == .lantern || $0.lightStrand != nil || ($0.kind == .lights && $0.lightMotion != .steady)
        }
        let rate: Double = powerLimited ? 20 : 30
        let sceneTick = now - lastWeatherTick >= (1 / rate - 0.002)
        let weatherDelta = lastWeatherTick > 0 ? min(0.090, now - lastWeatherTick) : 1 / rate
        if sceneTick { lastWeatherTick = now }
        let newFrontWindow = windows.first(where: { !$0.widget })?.rect ?? .null
        let changedFlakeMask = geometryChanged && !idleScene && settings.layer == .behindFrontWindow
            ? oldFrontWindow.areasOutside(newFrontWindow) + newFrontWindow.areasOutside(oldFrontWindow) : []
        for screen in screens.values {
            if hidden.contains(screen.id) {
                screen.setVisibility(back: false, front: false)
                continue
            }
            let showBack = behind && (running || !screen.sim.flakes.isEmpty)
            let revealBack = showBack && !screen.visibleBack
            let revealFront = active && !screen.visibleFront
            screen.setVisibility(back: showBack, front: active)
            let size = screen.frame.size
            let hasFallingSnowmen = !screen.fallingSnowmen.isEmpty
            let plowWasPushing = !screen.plowedSnowmen.isEmpty || !screen.plowedDecorations.isEmpty
            let previousPlow = screen.sim.plow
            let hadFallingSnow = screen.sim.fallingSnowAnimating
            let holidayWasActive = screen.festivities.active
            let rollingWasActive = screen.rolledSnow.animating
            let pointerLocal = screen.local(CGRect(origin: pointer, size: .zero)).origin
            let swept = canSweep && screen.frame.contains(pointer) && screen.sim.sweepSnow(
                from: screen.local(CGRect(origin: previousPointer, size: .zero)).origin,
                to: screen.local(CGRect(origin: pointer, size: .zero)).origin, delta: delta, reduced: reducedMotion)
            let stepWeather = sceneTick && (running || screen.sim.weatherAnimating)
            if stepWeather {
                screen.sim.step(size: size, delta: weatherDelta, time: now,
                                settings: settings, reduced: reducedMotion, emitting: running, lowPower: powerLimited)
            }
            if hadFallingSnow && tracksSnow { screen.sim.stepFallingSnow(delta: delta, reduced: reducedMotion) }
            var rolledChanged = false
            if rollingWasActive || sceneTick || needsLayout {
                rolledChanged = screen.rolledSnow.advance(delta, size: size, snow: &screen.sim, reduced: reducedMotion)
            }
            screen.festivities.step(delta, size: size, snow: screen.sim,
                                     automatic: settings.festiveVisits && running && !powerLimited
                                        && screen.id == dockDisplays.first?.snowScreenID, reduced: reducedMotion)
            if sceneTick {
                updateTreeSnow(on: screen, delta: weatherDelta, pointer: pointerLocal,
                               stirring: hypot(pointer.x - previousPointer.x, pointer.y - previousPointer.y) > 3
                                   && !mouseDown && !model.editMode && studio?.contains(pointer) != true)
            }
            var plowedRegions: [CGRect] = []
            if let floor = screen.sim.surfaces.first(where: \.floor)?.rect {
                let contact = screen.sim.plow.map { SnowplowContact(pass: $0, previous: previousPlow, floor: floor) }
                if stepWeather, settings.plowDestroysDecorations, let contact {
                    plowedRegions = collideDecorations(contact, floor: floor, on: screen)
                    rolledChanged = screen.rolledSnow.contactPlow(contact) || rolledChanged
                }
                screen.rolledSnow.advancePlowed(delta, contact: contact, floor: floor, reduced: reducedMotion)
                for index in screen.plowedSnowmen.indices.reversed() {
                    if !screen.plowedSnowmen[index].advance(delta, contact: contact, floor: floor, reduced: reducedMotion) {
                        screen.plowedSnowmen.remove(at: index)
                    }
                }
                for index in screen.plowedDecorations.indices.reversed() {
                    if !screen.plowedDecorations[index].advance(delta, floor: floor, reduced: reducedMotion) {
                        screen.plowedDecorations.remove(at: index)
                    }
                }
            }
            for index in screen.fallingSnowmen.indices.reversed() {
                if !screen.fallingSnowmen[index].advance(delta, scene: &screen.sim, limit: size.height,
                                                         accumulate: settings.accumulate, reduced: reducedMotion) {
                    screen.fallingSnowmen.remove(at: index)
                }
            }
            if showBack && (stepWeather || changed || revealBack || canvasChanged) {
                screen.backView.invalidate(moving: screen.sim.flakes.map(\.paintBounds), full: changed || revealBack || canvasChanged)
            }
            let fullFront = fullLayout || revealFront || canvasChanged
            let arrangingProp = snowRollGesture?.display == screen.id && snowRollGesture?.prop != nil
            if active && (needsLayout || fullFront || stepWeather || (sceneTick && animatedDecorations) || hadFallingSnow || hasFallingSnowmen
                          || plowWasPushing || workshop != nil || swept || rollingWasActive || rolledChanged || arrangingProp
                          || holidayWasActive || screen.festivities.active) {
                let moving = movingFront(on: screen, weatherInFront: !behind, idleScene: idleScene)
                var changedRegions = screen.changedSnow(showing: settings.accumulate)
                changedRegions += layoutRegions[screen.id] ?? []
                changedRegions += changedFlakeMask.map(screen.local)
                changedRegions += plowedRegions
                screen.frontView.invalidate(moving: moving, changed: changedRegions, full: fullFront)
                if dockChanged || (geometryChanged && (fastTracking || tracksSnow)) { screen.frontView.displayIfNeeded() }
            }
        }
        if needsLayout || showingHandles != lastHandlesShowing {
            updateHandles(studio, showing: showingHandles)
            lastHandlesShowing = showingHandles
        }
        if lightDraft != nil && pointer != previousPointer { refreshPickerGuides() }
        if sceneTick || needsLayout { updateGiftHandles() }
        monitorSnowPointer(active && canRollSnow && fullscreenDisplays.count < screens.count)
        refreshSnowRollHandle(at: pointer)
    }

    private func updateTreeSnow(on screen: ScreenOverlay, delta: CGFloat, pointer: CGPoint, stirring: Bool) {
        let trees = screen.placements.filter { $0.0.kind == .tree }
        let present = Set(trees.map { $0.0.id })
        screen.treeSnow = screen.treeSnow.filter { present.contains($0.key) }
        let settings = model.settings
        for (ornament, rect, target) in trees {
            var snow = screen.treeSnow[ornament.id] ?? TreeBranchSnow()
            snow.step(delta, density: model.running && settings.accumulate ? 0.32 + settings.intensity * 0.68 : 0)
            let touches = rect.insetBy(dx: rect.width * 0.17, dy: rect.height * 0.16).contains(pointer)
            let covered = target.map { window in windows.prefix { $0.id != window.id }.contains { screen.local($0.rect).contains(pointer) } } ?? false
            if stirring && touches && !covered && settings.accumulate {
                for (point, load) in snow.shake(at: pointer, in: rect) { screen.sim.shedBranchSnow(at: point, load: load) }
            }
            screen.treeSnow[ornament.id] = snow
        }
    }

    private func updateGiftHandles() {
        var present = Set<UUID>()
        if snowRollGesture == nil && lightDraft == nil && !model.pickingWindow && !model.preview && !model.editMode {
            let studio = presentedStudio()?.frame
            for screen in screens.values where !fullscreenDisplays.contains(screen.id) {
                for gift in screen.festivities.gifts where gift.openedAt == nil && gift.rest != nil {
                    let frame = screen.global(gift.frame)
                    guard studio?.intersects(frame) != true else { continue }
                    present.insert(gift.id)
                    let panel: OverlayPanel
                    if let existing = giftHandles[gift.id]?.1 { panel = existing }
                    else {
                        panel = OverlayPanel(frame: frame, level: .init(rawValue: overlayLevel.rawValue + 1), interactive: true)
                        let view = HandleView()
                        view.setAccessibilityLabel("打开雪橇礼物")
                        let id = gift.id
                        view.up = { [weak screen] _ in screen?.festivities.open(id) }
                        panel.contentView = view
                        giftHandles[id] = (screen.id, panel)
                    }
                    if panel.frame != frame { panel.setFrame(frame, display: false) }
                    if !panel.isVisible { panel.orderFrontRegardless() }
                }
            }
        }
        for id in Array(giftHandles.keys) where !present.contains(id) { giftHandles.removeValue(forKey: id)?.1.orderOut(nil) }
    }

    private func workshopPart(_ ball: WorkshopBall, in workshop: SnowmanWorkshop, on screen: ScreenOverlay) -> SnowmanPart {
        SnowmanPart(tone: workshop.tone(for: ball), radius: ball.radius,
                    center: screen.local(CGRect(origin: ball.center, size: .zero)).origin,
                    angle: reducedMotion ? 0 : ball.spin)
    }

    private func collideDecorations(_ contact: SnowplowContact, floor: CGRect, on screen: ScreenOverlay) -> [CGRect] {
        var destroyed = Set<UUID>()
        var regions: [CGRect] = []
        for (ornament, rect, target) in screen.placements where dragSession?.handle.ornament != ornament.id {
            if ornament.kind == .snowman {
                let parts = SnowmanArt.parts(for: ornament, in: rect)
                guard let base = parts.first, contact.hits(base) else { continue }
                screen.plowedSnowmen.append(PlowedSnowman(ornament: ornament, parts: parts, contact: contact))
            } else {
                let mountedLights = target != nil && ornament.kind == .lights
                let body = mountedLights ? DecorationArt.windowLightHitRegions(ornament, in: rect)
                                         : [ornament.interactionFrame(in: rect)]
                guard body.contains(where: contact.hits) else { continue }
                let size = ornament.drawnSize
                let wreck = mountedLights ? CGRect(x: contact.blade - size.width / 2, y: floor.minY - size.height,
                                                    width: size.width, height: size.height) : rect
                screen.plowedDecorations.append(PlowedDecoration(ornament: ornament, frame: wreck, contact: contact))
            }
            destroyed.insert(ornament.id)
            regions.append(ornament.paintBounds(in: rect))
        }
        if let workshop, workshop.held == nil,
           let source = model.settings.ornaments.first(where: { $0.id == workshopSource }) {
            let parts = workshop.balls.map { workshopPart($0, in: workshop, on: screen) }
            if parts.contains(where: contact.hits) {
                screen.plowedSnowmen.append(PlowedSnowman(ornament: source, parts: parts, contact: contact))
                destroyed.insert(source.id)
                regions += parts.map { $0.bounds(dressed: true) }
                cancelSnowman()
            }
        }
        guard !destroyed.isEmpty else { return regions }
        model.remove(destroyed)
        removeHandles(for: destroyed)
        for id in destroyed { snowmanPerches.removeValue(forKey: id) }
        for overlay in screens.values { overlay.placements.removeAll { destroyed.contains($0.0.id) } }
        layoutDirty = true
        return regions
    }

    private func movingFront(on screen: ScreenOverlay, weatherInFront: Bool, idleScene: Bool) -> [CGRect] {
        var rects = screen.sim.released.map(\.paintBounds)
        if weatherInFront {
            let covered = model.settings.layer == .behindFrontWindow && !idleScene
                ? windows.first(where: { !$0.widget }).map { screen.local($0.rect) } : nil
            for flake in screen.sim.flakes where covered?.contains(flake.paintBounds) != true {
                rects.append(flake.paintBounds)
            }
        }
        if !reducedMotion {
            for (ornament, rect, _) in screen.placements
            where ornament.kind == .lantern || ornament.lightStrand != nil || (ornament.kind == .lights && ornament.lightMotion != .steady) {
                rects.append(ornament.lightStrand == nil ? ornament.paintBounds(in: rect) : rect)
            }
        }
        for (ornament, rect, _) in screen.placements where ornament.kind == .tree && screen.treeSnow[ornament.id] != nil {
            rects.append(ornament.paintBounds(in: rect))
        }
        if let flight = screen.festivities.flight { rects.append(flight.paintBounds(in: screen.frame.size)) }
        rects += screen.festivities.gifts.map(\.bounds)
        rects += screen.rolledSnow.balls.map(RolledSnowArt.bounds)
        rects += screen.rolledSnow.plowed.map { RolledSnowArt.bounds(of: $0.ball) }
        if let pass = screen.sim.plow, let floor = screen.sim.surfaces.first(where: \.floor) {
            let x = floor.rect.minX + pass.bladeX(width: floor.rect.width)
            rects.append(CGRect(x: x - 108, y: floor.rect.minY - 82, width: 216, height: 87))
        }
        for powder in screen.sim.powder + screen.sim.impactPowder {
            rects.append(CGRect(around: p(powder.x, powder.y), radius: powder.radius * 2.3 + 2))
        }
        for clump in screen.sim.fallingSnow {
            rects.append(CGRect(around: clump.center, radius: hypot(clump.width, clump.thickness) / 2 + 2))
        }
        for grain in screen.sim.looseSnow {
            rects.append(CGRect(around: grain.position, radius: grain.radius + 2))
        }
        for fall in screen.fallingSnowmen { rects.append(fall.ornament.paintBounds(in: fall.rect)) }
        for wreck in screen.plowedSnowmen { rects += wreck.parts.map { $0.bounds(dressed: true) } }
        for wreck in screen.plowedDecorations { rects.append(wreck.ornament.paintBounds(in: wreck.frame)) }
        if let workshop {
            for ball in workshop.balls where workshop.revealed(ball.id) {
                rects.append(workshopPart(ball, in: workshop, on: screen).bounds(dressed: workshopSource != nil))
            }
            if screen.id == workshopDisplay { rects.append(workshopHint(in: screen.frontView.bounds)) }
        }
        return rects
    }

    private func updateDock(at now: Double) -> Bool {
        if now - lastDockScan >= 1.25 {
            lastDockScan = now
            let dock = DesktopDock(primaryTop: primaryTop)
            desktopDock = dock
            dockEdge = dock.edge
            fallbackDockFrames = Dictionary(uniqueKeysWithValues: dockDisplays.compactMap { display in
                dock.frame(on: display).map { (display.snowScreenID, $0) }
            })
        }
        let frames: [UInt32: CGRect]
        if let (display, frame) = desktopDock?.liveFrame(primaryTop: primaryTop, displays: dockDisplays, hitBounds: &dockHitBounds) {
            frames = [display: frame]
        } else {
            frames = fallbackDockFrames
        }
        guard frames != dockFrames else { return false }
        dockFrames = frames
        return true
    }

    private func dropWindowSnow(_ id: UInt32, horizontalSpeed: CGFloat) {
        guard let pack = windowSnow.take(id) else { return }
        dropWindowSnow(pack, from: windowSnowEdges(id), horizontalSpeed: horizontalSpeed)
    }

    private func windowSnowEdges(_ id: UInt32) -> [UInt32: SnowSurface] {
        var edges: [UInt32: SnowSurface] = [:]
        for screen in screens.values {
            edges[screen.id] = screen.sim.surfaces.first(where: { $0.id == .window(id) })
        }
        return edges
    }

    private func dropWindowSnow(_ pack: SnowDrift, from edges: [UInt32: SnowSurface],
                                horizontalSpeed: CGFloat, pendingWindow: UInt32? = nil) {
        for (id, edge) in edges {
            screens[id]?.sim.dropWindowSnow(pack, from: edge, horizontalSpeed: horizontalSpeed,
                                            reduced: reducedMotion, pendingWindow: pendingWindow)
        }
    }

    private func resolveWindowExit(_ id: UInt32, didDisappear: Bool) {
        for screen in screens.values { screen.sim.resolveFallingWindow(id, didDisappear: didDisappear) }
    }

    private func trackWindowExits(from previous: [DesktopWindow], holdingMouse: Bool, at now: Double) {
        let frames = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.rect) })
        let stageDisplays = self.stageDisplays
        for window in windows where !window.widget {
            guard let old = frames[window.id] else { continue }
            let id = window.id
            let moved = window.rect != old
            if let exit = windowExits[id], now - exit.began > 0.95 || now - exit.lastMotion > 0.15
                || (holdingMouse && !stageEnabled && !exit.airborne) {
                if exit.airborne {
                    resolveWindowExit(id, didDisappear: false)
                    windowSnow[id] = exit.pack
                    layoutDirty = true
                }
                windowExits.removeValue(forKey: id)
            }
            guard moved else { continue }
            if windowExits[id] == nil, (!holdingMouse || stageEnabled), WindowExit.starts(between: old, and: window.rect),
               let pack = windowSnow[id] {
                // WindowServer reports the deformed frame during a system animation.
                let edges = windowSnowEdges(id)
                if !edges.isEmpty { windowExits[id] = WindowExit(origin: old, pack: pack, edges: edges, began: now, lastMotion: now) }
            }
            guard var exit = windowExits[id] else { continue }
            exit.lastMotion = now
            exit.samples += 1
            let shrinkingToStage = StageWindow.isMovingToStrip(from: exit.origin, to: window.rect, on: stageDisplays)
            if !exit.airborne && (shrinkingToStage || (!holdingMouse && exit.suggestsMinimizing(window.rect, toward: dockEdge))) {
                dropWindowSnow(exit.pack, from: exit.edges, horizontalSpeed: shrinkingToStage ? -44 : 0, pendingWindow: id)
                exit.airborne = true
            }
            windowExits[id] = exit
        }
    }

    private func readIdle(_ now: Double) {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        if model.preview && now - previewStarted > 0.55 {
            let estimatedInput = now - idle
            if capturedPreviewInput == nil { capturedPreviewInput = estimatedInput }
            if let originalInput = capturedPreviewInput, estimatedInput > originalInput + 0.1 {
                model.preview = false
                capturedPreviewInput = nil
                model.showStudio?()
            }
        }
        let configured = model.settings.idleSeconds
        let threshold = configured > 0 ? configured : 120
        let idleActive = (configured > 0 || model.settings.onlyWhenIdle) && idle >= Double(threshold)
        if model.idleActive != idleActive { model.idleActive = idleActive }
    }

    private func layoutAnchor(_ anchor: WindowAnchor) -> DesktopWindow? {
        if let direct = windows.first(where: { $0.id == anchor.id && $0.owner == anchor.owner && $0.pid == anchor.pid }) {
            return direct
        }
        let candidates = windows.filter { !$0.widget && $0.owner == anchor.owner && $0.pid != anchor.pid }
        return candidates.min {
            hypot($0.rect.midX - anchor.x, $0.rect.midY - anchor.y) < hypot($1.rect.midX - anchor.x, $1.rect.midY - anchor.y)
        }
    }

    private func updateLayout(on screen: ScreenOverlay, studio: CGRect?, hasOrnaments: Bool) {
        let region = screen.local(screen.frame)
        var placements: [(Ornament, CGRect, DesktopWindow?)] = []
        var draggedPlacement: (Ornament, CGRect, DesktopWindow?)?
        let mainScreen = NSScreen.screens.first?.snowScreenID
        if hasOrnaments {
            for ornament in model.settings.ornaments where ornament.id != workshopSource {
                if let strand = ornament.lightStrand {
                    let here = ornament.display == screen.id || (screens[ornament.display] == nil && screen.id == mainScreen)
                    if here, ornament.id != lightDraft?.ornament?.id, strand.hooks.count > 1 {
                        placements.append((ornament, strand.bounds(in: screen.frame.size, bulbScale: ornament.scale), nil))
                    }
                    continue
                }
                if let dragSession, let preview = dragSession.preview, dragSession.handle.ornament == ornament.id {
                    if preview.display == screen.id { draggedPlacement = (ornament, screen.local(preview.frame), nil) }
                    continue
                }
                if let anchor = ornament.anchor {
                    guard let target = layoutAnchor(anchor), target.rect.intersects(screen.frame) else { continue }
                    let rect = screen.local(target.rect)
                    if ornament.kind == .lights {
                        placements.append((ornament, rect, target))
                    } else {
                        let width = ornament.kind.size.width * ornament.scale
                        let height = ornament.kind.size.height * ornament.scale
                        let centerX = rect.minX + rect.width * ornament.x
                        let foot = ornament.kind == .snowman ? SnowmanArt.baseline * ornament.scale : height * 0.82
                        let frame = CGRect(x: centerX - width / 2, y: rect.minY - foot, width: width, height: height)
                        placements.append((ornament, frame, target))
                    }
                } else if ornament.display == screen.id || (screens[ornament.display] == nil && screen.id == mainScreen) {
                    let dock = dockEdge == .bottom ? dockFrames[screen.id] : nil
                    let frame = screen.place(ornament, dock: dock)
                    placements.append((ornament, screen.local(frame), nil))
                }
            }
        }
        if let draggedPlacement { placements.append(draggedPlacement) }
        screen.placements = placements
        var surfaces: [SnowSurface] = []
        var covers: [CGRect] = []
        if let dock = dockFrames[screen.id] {
            let rect = screen.local(dock)
            let glassScale: CGFloat = if #available(macOS 26, *) { 0.38 } else { 0.25 }
            let profile = DockSnowProfile(rect, radius: min(30, min(rect.width, rect.height) * glassScale))
            let left = max(region.minX, profile.supportedRange.lowerBound)
            let right = min(region.maxX, profile.supportedRange.upperBound)
            if right - left > 5 {
                surfaces.append(SnowSurface(id: .dock, rect: rect, visible: [left...right], floor: false, cornerRadius: profile.radius))
                covers.append(rect)
            }
        }
        for window in windows {
            if window.rect.intersects(screen.frame) {
                let rect = screen.local(window.rect)
                let visible = windowExits[window.id]?.airborne == true ? [] : exposedEdge(rect, inside: region, blockedBy: covers)
                if !visible.isEmpty {
                    let radius = window.widget || rect.contains(region.insetBy(dx: 1, dy: 1)) ? 0 : windowCornerRadius
                    let band = radius > 0
                        ? CGRect(x: rect.minX - 14, y: rect.minY - 15, width: rect.width + 28, height: radius + 30)
                        : CGRect(x: rect.minX, y: rect.minY - 14, width: rect.width, height: 26)
                    surfaces.append(SnowSurface(id: .window(window.id), rect: rect, visible: visible, floor: false,
                                                occluders: covers.filter { $0.intersects(band) }, cornerRadius: radius))
                }
                covers.append(rect)
            }
        }
        for (ornament, rect, target) in placements where ornament.lightStrand == nil && (target == nil || ornament.kind != .lights) {
            let inset = rect.width * (ornament.kind == .calendar ? 0.04 : 0.27)
            let edge = CGRect(x: rect.minX + inset, y: rect.minY + rect.height * 0.13,
                              width: rect.width - 2 * inset, height: 4)
            var covering = studio.map { [screen.local($0)] } ?? []
            if let target {
                covering += windows.prefix { $0.id != target.id }.map { screen.local($0.rect) }
            }
            let visible = exposedEdge(edge, inside: region, blockedBy: covering)
            if !visible.isEmpty { surfaces.append(SnowSurface(id: .decoration(ornament.id), rect: edge, visible: visible, floor: false)) }
        }
        let floorY = region.maxY
        let floor = CGRect(x: region.minX, y: floorY, width: region.width, height: 1)
        surfaces.append(SnowSurface(id: .floor, rect: floor, visible: [floor.minX...floor.maxX], floor: true))
        screen.sim.setSurfaces(surfaces)
    }

    private func outside(_ rects: [CGRect], bounds: CGRect, ink: Ink) {
        for rect in rects where rect.intersects(bounds) {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(rect.intersection(bounds))
            ink.ctx.beginPath()
            ink.ctx.addPath(path)
            ink.ctx.clip(using: .evenOdd)
        }
    }

    private func paint(_ ink: Ink, screen: ScreenOverlay, isBack: Bool, dirty: CGRect) {
        let settings = model.settings
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let idleScene = model.preview || (model.running && model.idleActive && settings.idleSeconds > 0)
        let now = CACurrentMediaTime()
        let motionTime = reducedMotion ? 0 : now
        let studio = isBack ? nil : presentedStudio(at: now)
        let studioSurface = studio.map { SurfaceID.window($0.id) }
        func paintDrift(_ surface: SnowSurface) {
            guard dirty.intersects(surface.paintBounds), let drift = screen.sim.drift(on: surface.id) else { return }
            ink.ctx.saveGState()
            outside(surface.occluders, bounds: bounds, ink: ink)
            SnowArt.drift(drift, on: surface, icicles: settings.icicles, ink: ink)
            ink.ctx.restoreGState()
        }
        ink.ctx.saveGState()
        if let studio { outside([screen.local(studio.frame)], bounds: bounds, ink: ink) }
        if !isBack && model.running && idleScene && settings.idleDim { ink.fill(bounds, 0x071526, alpha: 0.30) }
        if !screen.sim.flakes.isEmpty {
            ink.ctx.saveGState()
            if isBack {
                paintFlakes(screen.sim.flakes, ink: ink, dirty: dirty, crystalMix: settings.crystalMix, time: motionTime)
            } else if settings.layer != .behindWindows || idleScene {
                if settings.layer == .behindFrontWindow && !idleScene,
                   let front = windows.first(where: { !$0.widget }) {
                    outside([screen.local(front.rect)], bounds: bounds, ink: ink)
                }
                paintFlakes(screen.sim.flakes, ink: ink, dirty: dirty, crystalMix: settings.crystalMix, time: motionTime)
            }
            ink.ctx.restoreGState()
        }

        if !isBack {
            for (ornament, rect, target) in screen.placements {
                let paintBounds = ornament.lightStrand == nil ? ornament.paintBounds(in: rect) : rect
                guard dirty.intersects(paintBounds) else { continue }
                ink.ctx.saveGState()
                if let target {
                    let nearer = windows.prefix { $0.id != target.id }
                    outside(nearer.map { screen.local($0.rect) }, bounds: bounds, ink: ink)
                }
                if ornament.lightStrand != nil {
                    let pointer = screen.local(CGRect(origin: NSEvent.mouseLocation, size: .zero)).origin
                    DecorationArt.freeLights(ornament, screen: bounds.size, brush: pointer,
                                             wind: settings.wind, ink: ink, time: motionTime)
                } else if target != nil && ornament.kind == .lights {
                    DecorationArt.windowLights(ornament, rect: rect, ink: ink, time: motionTime)
                } else {
                    var pose = ornament
                    let branchSnow = settings.accumulate ? screen.treeSnow[ornament.id] : nil
                    if !reducedMotion { pose.rotation += Double(branchSnow?.rotation ?? 0) }
                    DecorationArt.draw(pose, in: rect, with: ink, time: motionTime, now: Date())
                    if let branchSnow {
                        ink.ctx.saveGState()
                        ink.ctx.translateBy(x: rect.midX, y: rect.midY)
                        ink.ctx.rotate(by: pose.rotation * .pi / 180)
                        ink.ctx.translateBy(x: -rect.midX, y: -rect.midY)
                        branchSnow.paint(in: rect, ink: ink)
                        ink.ctx.restoreGState()
                    }
                    if model.editMode && model.selectedOrnament == ornament.id {
                        ink.ctx.setStrokeColor(NSColor(rgb: 0x9aeeff, alpha: 0.64).cgColor)
                        ink.ctx.setLineWidth(1)
                        ink.ctx.setLineDash(phase: 0, lengths: [5, 5])
                        ink.ctx.stroke(rect.insetBy(dx: 1, dy: 1))
                        ink.ctx.setLineDash(phase: 0, lengths: [])
                    }
                }
                ink.ctx.restoreGState()
            }
            if settings.accumulate {
                for surface in screen.sim.surfaces where surface.id != studioSurface {
                    paintDrift(surface)
                }
                if let pass = screen.sim.plow, let floor = screen.sim.surfaces.first(where: \.floor) {
                    SnowplowArt.draw(pass, on: floor, ink: ink)
                }
                SnowplowArt.spray(screen.sim.powder, ink: ink)
                SnowArt.falling(screen.sim.fallingSnow, ink: ink)
                SnowArt.loose(screen.sim.looseSnow, ink: ink)
                SnowplowArt.spray(screen.sim.impactPowder, ink: ink)
            }
            for fall in screen.fallingSnowmen {
                DecorationArt.draw(fall.ornament, in: fall.rect, with: ink, time: motionTime, now: Date())
            }
            for wreck in screen.plowedSnowmen {
                for part in wreck.parts where dirty.intersects(part.bounds(dressed: true)) {
                    SnowmanArt.drawPart(part, wearing: wreck.ornament, ink: ink)
                }
            }
            for wreck in screen.plowedDecorations where dirty.intersects(wreck.ornament.paintBounds(in: wreck.frame)) {
                ink.ctx.saveGState()
                ink.ctx.setAlpha(wreck.opacity)
                DecorationArt.draw(wreck.ornament, in: wreck.frame, with: ink, time: motionTime, now: Date())
                ink.ctx.restoreGState()
            }
            paintFlakes(screen.sim.released, ink: ink, dirty: dirty)
            for wreck in screen.rolledSnow.plowed where dirty.intersects(RolledSnowArt.bounds(of: wreck.ball)) {
                RolledSnowArt.draw(wreck.ball, reduced: reducedMotion, ink: ink)
            }
            for ball in screen.rolledSnow.paintedBalls where ball.mass > 0 && dirty.intersects(RolledSnowArt.bounds(of: ball)) {
                RolledSnowArt.draw(ball, reduced: reducedMotion, ink: ink)
            }
            if let pass = screen.festivities.flight, dirty.intersects(pass.paintBounds(in: bounds.size)) {
                FestiveTrafficArt.draw(pass, in: bounds.size, reduced: reducedMotion, ink: ink)
            }
            for gift in screen.festivities.gifts where dirty.intersects(gift.bounds) {
                FestiveTrafficArt.draw(gift, reduced: reducedMotion, ink: ink)
            }
            if let workshop {
                let source = settings.ornaments.first { $0.id == workshopSource }
                for ball in workshop.balls where workshop.revealed(ball.id) {
                    let part = workshopPart(ball, in: workshop, on: screen)
                    if dirty.intersects(part.bounds(dressed: source != nil)) {
                        SnowmanArt.drawPart(part, wearing: source, ink: ink)
                    }
                }
                if screen.id == workshopDisplay {
                    let hint = workshopHint(in: bounds)
                    ink.rounded(hint, 9, 0x132e43, alpha: 0.92)
                    let text = workshopSource == nil ? "把雪球从大到小叠起来" : "点击任意雪球重新堆起"
                    ink.text(text, at: p(hint.midX, hint.midY), size: 12.5, color: 0xe0f6ff)
                }
            }
        }
        ink.ctx.restoreGState()
        // Only the settings window's own snow can wrap over its title bar and corners.
        if settings.accumulate, let studioSurface, let edge = screen.sim.surfaces.first(where: { $0.id == studioSurface }) {
            paintDrift(edge)
        }
    }

    private func workshopHint(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.midX - 158, y: 46, width: 316, height: 30)
    }

    private func paintFlakes(_ flakes: [Flake], ink: Ink, dirty: CGRect, crystalMix: CGFloat = 0, time: Double = 0) {
        guard !flakes.isEmpty else { return }
        let buckets = (0..<8).map { _ in CGMutablePath() }
        let halos = CGMutablePath()
        for flake in flakes where dirty.intersects(flake.paintBounds) {
            let opacity = (0.26 + flake.depth * 0.61) * flake.opacity
            let radius = flake.radius
            if flake.crystal < crystalMix, radius >= 1.5 {
                IceCrystalArt.draw(flake, at: time, opacity: opacity, ink: ink)
                continue
            }
            let index = min(7, max(0, Int(opacity * 8)))
            buckets[index].addEllipse(in: CGRect(x: flake.x - radius, y: flake.y - radius,
                                                 width: 2 * radius, height: 2 * radius))
            if radius > 2 && opacity > 0.35 {
                let halo = radius * 1.68
                halos.addEllipse(in: CGRect(x: flake.x - halo, y: flake.y - halo, width: 2 * halo, height: 2 * halo))
            }
        }
        if !halos.isEmpty {
            ink.ctx.setFillColor(NSColor(rgb: 0xd5edff, alpha: 0.12).cgColor)
            ink.ctx.addPath(halos)
            ink.ctx.fillPath()
        }
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            ink.ctx.setFillColor(NSColor(rgb: 0xf1faff, alpha: (CGFloat(index) + 0.5) / 8).cgColor)
            ink.ctx.addPath(path)
            ink.ctx.fillPath()
        }
    }

    private func updateHandles(_ studio: CGRect?, showing: Bool) {
        var present = Set<OrnamentHandleKey>()
        if showing {
            let grabbed = dragSession?.handle
            // AppKit continues sending drag events to the panel that received mouse-down.
            if let grabbed { present.insert(grabbed) }
            for screen in screens.values where !fullscreenDisplays.contains(screen.id) {
                for (ornament, rect, target) in screen.placements where ornament.id != grabbed?.ornament && ornament.lightStrand == nil {
                    let frame = screen.global(rect)
                    let mountedLights = target != nil && ornament.kind == .lights
                    let regions = mountedLights ? DecorationArt.windowLightHitRegions(ornament, in: rect)
                        : [model.editMode ? rect : ornament.interactionFrame(in: rect)]
                    var covers = studio.map { [$0] } ?? []
                    if let target { covers += windows.prefix { $0.id != target.id }.map(\.rect) }
                    for (index, region) in regions.enumerated() {
                        let visible = screen.global(region).intersection(screen.frame)
                        guard !visible.isEmpty else { continue }
                        let clear = covers.reduce([visible]) { frames, cover in frames.flatMap { $0.areasOutside(cover) } }
                        guard let hitFrame = clear.max(by: { $0.width * $0.height < $1.width * $1.height }),
                              hitFrame.width > 2, hitFrame.height > 2 else { continue }
                        let key = OrnamentHandleKey(ornament: ornament.id, display: screen.id, region: index)
                        present.insert(key)
                        let (panel, view) = handles[key] ?? makeHandle(for: key, frame: hitFrame)
                        if panel.frame != hitFrame { panel.setFrame(hitFrame, display: false) }
                        if ornament.kind == .snowman {
                            view.editTitle = "给雪人换装"
                            view.settings = { [weak self] in self?.model.showWardrobe?(ornament.id, frame) }
                            view.knock = model.editMode ? nil : { [weak self, weak screen] in
                                if let screen { self?.knockSnowman(ornament, from: frame, on: screen) }
                            }
                        }
                        view.down = { [weak self] point in
                            self?.handleDown(key, ornament: ornament, point: point, frame: frame, mountedLights: mountedLights)
                        }
                        view.up = { [weak self] point in self?.handleUp(key, point: point, frame: frame) }
                        if !panel.isVisible { panel.orderFrontRegardless() }
                    }
                }
            }
        }
        for key in Array(handles.keys) where !present.contains(key) {
            handles.removeValue(forKey: key)?.0.orderOut(nil)
        }
    }

    private func removeHandles(for ornaments: Set<UUID>) {
        for key in Array(handles.keys) where ornaments.contains(key.ornament) {
            handles.removeValue(forKey: key)?.0.orderOut(nil)
        }
    }

    private func makeHandle(for key: OrnamentHandleKey, frame: CGRect) -> (OverlayPanel, HandleView) {
        let panel = OverlayPanel(frame: frame, level: .init(rawValue: overlayLevel.rawValue + 1), interactive: true)
        let view = HandleView()
        panel.contentView = view
        let id = key.ornament
        view.drag = { [weak self] point in self?.drag(key, to: point) }
        view.remove = { [weak self] in self?.model.remove(id) }
        view.settings = { [weak self] in
            self?.model.selectedOrnament = id
            self?.model.showStudio?()
        }
        handles[key] = (panel, view)
        return (panel, view)
    }

    private func handleDown(_ key: OrnamentHandleKey, ornament: Ornament, point: CGPoint, frame: CGRect, mountedLights: Bool) {
        if model.editMode { model.selectedOrnament = key.ornament }
        var center = p(frame.midX, frame.midY)
        if mountedLights {
            let fraction = min(1, max(0, (point.x - frame.minX) / frame.width))
            let grip = DecorationArt.desktopLightPoint(at: fraction)
            let size = ornament.kind.size
            let angle = ornament.rotation * .pi / 180
            let x = (grip.x - size.width / 2) * ornament.scale
            let y = (grip.y + 4 - size.height / 2) * ornament.scale
            center = p(point.x - x * cos(angle) + y * sin(angle), point.y + x * sin(angle) + y * cos(angle))
        }
        dragSession = OrnamentDragSession(handle: key, start: point, center: center)
    }

    private func drag(_ key: OrnamentHandleKey, to point: CGPoint) {
        guard let session = dragSession, session.handle == key else { return }
        let dx = point.x - session.start.x
        let dy = point.y - session.start.y
        guard session.preview != nil || hypot(dx, dy) > 3,
              let screen = screens.values.first(where: { $0.frame.contains(point) }),
              let ornament = model.settings.ornaments.first(where: { $0.id == key.ornament }) else { return }
        let frame = ornament.desktopFrame(center: p(session.center.x + dx, session.center.y + dy), inside: screen.frame, free: true)
        guard session.preview?.display != screen.id || session.preview?.frame != frame else { return }
        dragSession?.preview = (screen.id, frame)
        dragLayoutDirty = true
        snowmanPerches.removeValue(forKey: key.ornament)
    }

    private func cancelOrnamentDrag() {
        guard dragSession != nil else { return }
        dragSession = nil
        layoutDirty = true
    }

    private func handleUp(_ key: OrnamentHandleKey, point: CGPoint, frame: CGRect) {
        guard dragSession?.handle == key else { return }
        drag(key, to: point)
        let dropped = dragSession?.preview
        cancelOrnamentDrag()
        let id = key.ornament
        if let dropped {
            if let screen = screens[dropped.display] {
                model.change(id) {
                    $0.placeOnDesktop(at: p(dropped.frame.midX, dropped.frame.midY), displayID: screen.id, display: screen.frame)
                }
            }
            return
        }
        guard let ornament = model.settings.ornaments.first(where: { $0.id == id }) else { return }
        if ornament.kind == .snowman { model.showWardrobe?(id, frame); return }
        guard ornament.kind == .calendar else { return }
        let angle = -ornament.rotation * .pi / 180
        let dx = (point.x - frame.midX) / ornament.scale
        let dy = (frame.midY - point.y) / ornament.scale
        let local = p(dx * cos(angle) - dy * sin(angle) + ornament.kind.size.width / 2,
                      dx * sin(angle) + dy * cos(angle) + ornament.kind.size.height / 2)
        if let day = DecorationArt.calendarDay(at: local) { model.openDoor(day, in: id) }
    }
}
