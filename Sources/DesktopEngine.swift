import AppKit
import QuartzCore

private let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
private let windowCornerRadius: CGFloat = {
    if #available(macOS 26, *) { return 18 }
    return 11
}()

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect, level: NSWindow.Level, interactive: Bool) {
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
        var rects: UnsafePointer<NSRect>?
        var count = 0
        getRectsBeingDrawn(&rects, count: &count)
        ctx.saveGState()
        if let rects, count > 1 {
            ctx.addRects(Array(UnsafeBufferPointer(start: rects, count: count)))
            ctx.clip()
        }
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
    var selectionHint: String?
    var editTitle = "在工作台编辑"
    var removalTitle = "移除装饰"

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ink = Ink(ctx: ctx)
        ink.fill(bounds, 0x000000, alpha: selectionHint != nil ? 0.19 : 0.008)
        if let selectionHint {
            let plate = CGRect(x: bounds.midX - 201, y: 52, width: 402, height: 44)
            ink.rounded(plate, 12, 0x173145, alpha: 0.96)
            ink.text(selectionHint, at: p(plate.midX, plate.midY), size: 14, color: 0xe0f6ff)
        }
    }

    override func mouseDown(with event: NSEvent) { down?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { drag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { up?(NSEvent.mouseLocation) }

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

    func place(_ ornament: Ornament) -> CGRect {
        let size = ornament.kind.size
        let width = size.width * ornament.scale
        let height = size.height * ornament.scale
        let x = min(usable.maxX - width / 2, max(usable.minX + width / 2, usable.minX + usable.width * ornament.x))
        let y = min(usable.maxY - height / 2, max(usable.minY + height / 2, usable.minY + usable.height * ornament.y))
        return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
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
    var studioFrame: (() -> CGRect?)?
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
    private var handles: [UUID: (OverlayPanel, HandleView)] = [:]
    private var ballHandles: [Int: (OverlayPanel, HandleView)] = [:]
    private var workshop: SnowmanWorkshop?
    private var workshopDisplay: UInt32?
    private var workshopSource: UUID?
    private var picking: [OverlayPanel] = []
    private var dragSession: (id: UUID, start: CGPoint, center: CGPoint)?
    private var workingPlacement = false
    private var wasRunning = false
    private var reducedMotion = false
    private var lastSettings: SnowSettings?
    private var lastEditing = false
    private var lastSelection: UUID?
    private var lastIdleScene = false
    private var lastCanvasReducedMotion = false
    private var calendarDay: Date?
    private var lastStudioFrame: CGRect?
    private let pid = ProcessInfo.processInfo.processIdentifier

    init(model: SnowModel) {
        self.model = model
        updateScreens()
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated),
                                                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for overlay in screens.values { overlay.setVisibility(back: false, front: false) }
        for (panel, _) in handles.values { panel.orderOut(nil) }
        finishPicking(nil, reopen: false)
        cancelSnowman()
    }

    func updateScreens() {
        let external = NSScreen.screens
        dockDisplays = external
        primaryTop = external.first?.frame.maxY ?? 0
        let ids = Set(external.map(\.snowScreenID))
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
        if model.buildingSnowman { cancelSnowman() }
    }

    func clear() {
        if !windowExits.isEmpty { layoutDirty = true }
        windowExits.removeAll(keepingCapacity: true)
        windowSnow.clear()
        for screen in screens.values {
            screen.sim.clearAccumulation()
            screen.fallingSnowmen.removeAll()
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
        cancelSnowman()
        model.hideStudio?()
        model.preview = true
        previewStarted = CACurrentMediaTime()
        capturedPreviewInput = nil
    }

    func beginPicking() {
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

    private func showPicker(hint: String, onClick: @escaping (CGPoint) -> Void, onCancel: @escaping () -> Void) {
        for screen in screens.values {
            let panel = OverlayPanel(frame: screen.frame, level: .init(rawValue: overlayLevel.rawValue + 2), interactive: true)
            let view = HandleView()
            view.selectionHint = hint
            view.down = onClick
            view.remove = onCancel
            panel.contentView = view
            picking.append(panel)
            panel.orderFrontRegardless()
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

    @objc private func spaceChanged() {
        spaceChangedAt = CACurrentMediaTime()
        snowmanPerches.removeAll()
        windows.removeAll()
        shakes.removeAll()
        for (id, exit) in windowExits where exit.airborne { resolveWindowExit(id, didDisappear: false) }
        windowExits.removeAll(keepingCapacity: true)
        windowSnow.clear()
        layoutDirty = true
        lastScan = 0
        cancelSnowman()
    }

    private func getWindows() -> [DesktopWindow] {
        DesktopWindow.onscreen(primaryTop: primaryTop, ignoring: pid, stageDisplays: stageDisplays)
    }

    private var stageDisplays: [CGRect] { stageEnabled ? screens.values.map(\.frame) : [] }

    @objc private func applicationActivated() {
        guard stageEnabled else { return }
        lastScan = 0
        fastTrackingUntil = CACurrentMediaTime() + 0.34
    }

    func startSnowman() {
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
        handles.removeValue(forKey: ornament.id)?.0.orderOut(nil)
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
        for display in screens.values { updateLayout(on: display, studio: studioFrame?(), hasOrnaments: hasOrnaments) }
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
        guard let platform = shelf ?? platforms.first(where: { $0.id == .ground(screen.id) }) else {
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
            let ground = CGRect(x: screen.usable.minX + 10, y: screen.usable.minY + 12,
                                width: max(1, screen.usable.width - 20), height: 1)
            platforms.append(SnowballPlatform(id: .ground(screen.id), frame: ground,
                                               span: ground.minX...ground.maxX, anchor: nil))
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
                let tone = id == workshop.balls.count - 1 ? 2 : id
                view.setAccessibilityLabel(["大雪球", "中雪球", "小雪球"][tone])
                if workshopSource != nil {
                    view.up = { [weak self] _ in
                        guard let self else { return }
                        let platforms = self.workshopPlatforms()
                        self.workshop?.rebuild(at: id, on: platforms)
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
            }
            return
        }
        var finished = Ornament(kind: .snowman, display: screen.id, x: x, y: y)
        finished.anchor = platform.anchor
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
        if let source = workshopSource, !settings.ornamentsVisible || !settings.ornaments.contains(where: { $0.id == source }) {
            cancelSnowman()
        }
        let running = model.running
        let hasOrnaments = settings.ornamentsVisible && !settings.ornaments.isEmpty
        let active = running || hasOrnaments || model.buildingSnowman
            || screens.values.contains { !$0.fallingSnowmen.isEmpty || !$0.sim.released.isEmpty || $0.sim.fallingSnowAnimating }
        let studio = studioFrame?()
        let changed = settings != lastSettings || model.editMode != lastEditing || studio != lastStudioFrame || wasRunning != running
        lastSettings = settings
        lastEditing = model.editMode
        lastStudioFrame = studio

        if !running && wasRunning { clear() }
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
        let tracksSnow = running && settings.accumulate
        let dockChanged = active && updateDock(at: now)
        if !tracksSnow && !windowExits.isEmpty { windowExits.removeAll(keepingCapacity: true) }
        let fastTracking = (tracksSnow || tracksWindows || model.buildingSnowman) && now < fastTrackingUntil
        let needsScan = active && (fastTracking || now - lastScan >= (running || tracksWindows ? 0.082 : 0.21))
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

        let fullLayout = layoutDirty || changed
        let needsLayout = fullLayout || geometryChanged || dockChanged
        var layoutRegions: [UInt32: [CGRect]] = [:]
        if needsLayout {
            for screen in screens.values {
                let oldSurfaces = fullLayout ? [] : screen.sim.surfaces
                let oldAnchored = fullLayout ? [] : screen.placements.filter { $0.2 != nil }
                updateLayout(on: screen, studio: studio, hasOrnaments: hasOrnaments)
                if !fullLayout {
                    let newSurfaces = screen.sim.surfaces
                    let before = Dictionary(uniqueKeysWithValues: oldSurfaces.map { ($0.id, $0) })
                    let after = Dictionary(uniqueKeysWithValues: newSurfaces.map { ($0.id, $0) })
                    var regions = oldSurfaces.filter { after[$0.id] != $0 }.map(\.paintBounds)
                    regions += newSurfaces.filter { before[$0.id] != $0 }.map(\.paintBounds)
                    if geometryChanged {
                        for (ornament, rect, _) in oldAnchored + screen.placements.filter({ $0.2 != nil }) {
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

        let idleScene = model.preview || (model.idleActive && settings.idleSeconds > 0)
        let canvasChanged = lastIdleScene != idleScene || lastCanvasReducedMotion != reducedMotion
            || lastSelection != model.selectedOrnament || (dayChanged && hasOrnaments)
        lastIdleScene = idleScene
        lastCanvasReducedMotion = reducedMotion
        lastSelection = model.selectedOrnament
        let canSweep = tracksSnow && !idleScene && !mouseDown && !model.editMode && !model.pickingWindow && !model.buildingSnowman
            && studio?.contains(pointer) != true
        let behind = running && settings.layer == .behindWindows && !idleScene
        let sceneTick = now - lastWeatherTick >= (1.0 / 30 - 0.002)
        let weatherDelta = lastWeatherTick > 0 ? min(0.065, now - lastWeatherTick) : 1.0 / 30
        if sceneTick { lastWeatherTick = now }
        let newFrontWindow = windows.first(where: { !$0.widget })?.rect ?? .null
        let changedFlakeMask = geometryChanged && running && !idleScene && settings.layer == .behindFrontWindow
            ? oldFrontWindow.areasOutside(newFrontWindow) + newFrontWindow.areasOutside(oldFrontWindow) : []
        for screen in screens.values {
            let revealBack = behind && !screen.visibleBack
            let revealFront = active && !screen.visibleFront
            screen.setVisibility(back: behind, front: active)
            let size = screen.frame.size
            let hasFallingSnowmen = !screen.fallingSnowmen.isEmpty
            let hasDebris = !screen.sim.released.isEmpty
            let hadFallingSnow = screen.sim.fallingSnowAnimating
            let swept = canSweep && screen.frame.contains(pointer) && screen.sim.sweepSnow(
                from: screen.local(CGRect(origin: previousPointer, size: .zero)).origin,
                to: screen.local(CGRect(origin: pointer, size: .zero)).origin, delta: delta, reduced: reducedMotion)
            if running && sceneTick {
                screen.sim.step(size: size, delta: weatherDelta, time: now,
                                settings: settings, reduced: reducedMotion)
            } else if !running && hasDebris {
                screen.sim.stepDebris(size: size, delta: delta, accumulate: false)
            }
            if hadFallingSnow && tracksSnow { screen.sim.stepFallingSnow(delta: delta, reduced: reducedMotion) }
            for index in screen.fallingSnowmen.indices.reversed() {
                if !screen.fallingSnowmen[index].advance(delta, scene: &screen.sim, limit: size.height,
                                                         accumulate: running && settings.accumulate, reduced: reducedMotion) {
                    screen.fallingSnowmen.remove(at: index)
                }
            }
            if behind && (sceneTick || changed || revealBack) {
                screen.backView.invalidate(moving: screen.sim.flakes.map(\.paintBounds), full: changed || revealBack || canvasChanged)
            }
            let fullFront = fullLayout || revealFront || canvasChanged
            if active && (needsLayout || fullFront || sceneTick || hasDebris || hadFallingSnow || hasFallingSnowmen || workshop != nil || swept) {
                let moving = movingFront(on: screen, weatherInFront: running && !behind, idleScene: idleScene)
                var changedRegions = screen.changedSnow(showing: running)
                changedRegions += layoutRegions[screen.id] ?? []
                changedRegions += changedFlakeMask.map(screen.local)
                screen.frontView.invalidate(moving: moving, changed: changedRegions, full: fullFront)
                if dockChanged || (geometryChanged && (fastTracking || tracksSnow)) { screen.frontView.displayIfNeeded() }
            }
        }
        if needsLayout || dragSession != nil {
            updateHandles(studio, showing: hasOrnaments && !model.preview && !model.pickingWindow)
        }
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
            where ornament.kind == .lantern || (ornament.kind == .lights && ornament.lightMotion != .steady) {
                rects.append(ornament.paintBounds(in: rect))
            }
        }
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
        if let workshop {
            for ball in workshop.balls where workshop.revealed(ball.id) {
                rects.append(screen.local(CGRect(around: ball.center, radius: ball.radius + 3)))
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
        let mainScreen = NSScreen.screens.first?.snowScreenID
        if hasOrnaments {
            for ornament in model.settings.ornaments where ornament.id != workshopSource {
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
                    placements.append((ornament, screen.local(screen.place(ornament)), nil))
                }
            }
        }
        screen.placements = placements
        var surfaces: [SnowSurface] = []
        var covers = studio.map { [screen.local($0)] } ?? []
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
        for (ornament, rect, target) in placements where target == nil || ornament.kind != .lights {
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
            ink.ctx.addPath(path)
            ink.ctx.clip(using: .evenOdd)
        }
    }

    private func paint(_ ink: Ink, screen: ScreenOverlay, isBack: Bool, dirty: CGRect) {
        let settings = model.settings
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let idleScene = model.preview || (model.idleActive && settings.idleSeconds > 0)
        let now = CACurrentMediaTime()
        let motionTime = reducedMotion ? 0 : now
        ink.ctx.saveGState()
        if !isBack, let frame = studioFrame?() { outside([screen.local(frame)], bounds: bounds, ink: ink) }
        if !isBack && model.running && idleScene && settings.idleDim { ink.fill(bounds, 0x071526, alpha: 0.30) }
        if model.running {
            ink.ctx.saveGState()
            if isBack, let id = settings.wallpaper, Wallpaper.all.first(where: { $0.id == id })?.showsWindowView == true {
                let path = CGMutablePath()
                let scale = max(bounds.width / 1200, bounds.height / 750)
                let dx = (bounds.width - scale * 1200) / 2
                let dy = (bounds.height - scale * 750) / 2
                for x in [CGFloat(86), 608] {
                    for (y, height) in [(CGFloat(59), CGFloat(281)), (352, 302)] {
                        path.addRect(CGRect(x: dx + x * scale, y: dy + y * scale,
                                            width: 506 * scale, height: height * scale))
                    }
                }
                ink.ctx.addPath(path)
                ink.ctx.clip()
            }
            if isBack {
                paintFlakes(screen.sim.flakes, ink: ink, dirty: dirty)
            } else if settings.layer != .behindWindows || idleScene {
                if settings.layer == .behindFrontWindow && !idleScene,
                   let front = windows.first(where: { !$0.widget }) {
                    outside([screen.local(front.rect)], bounds: bounds, ink: ink)
                }
                paintFlakes(screen.sim.flakes, ink: ink, dirty: dirty)
            }
            ink.ctx.restoreGState()
        }

        if !isBack {
            for (ornament, rect, target) in screen.placements {
                guard dirty.intersects(ornament.paintBounds(in: rect)) else { continue }
                ink.ctx.saveGState()
                if let target {
                    let nearer = windows.prefix { $0.id != target.id }
                    outside(nearer.map { screen.local($0.rect) }, bounds: bounds, ink: ink)
                }
                if target != nil && ornament.kind == .lights {
                    DecorationArt.windowLights(ornament, rect: rect, ink: ink, time: motionTime)
                } else {
                    DecorationArt.draw(ornament, in: rect, with: ink, time: motionTime, now: Date())
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
            if model.running {
                for surface in screen.sim.surfaces where dirty.intersects(surface.paintBounds) {
                    guard let drift = screen.sim.drift(on: surface.id) else { continue }
                    ink.ctx.saveGState()
                    outside(surface.occluders, bounds: bounds, ink: ink)
                    SnowArt.drift(drift, on: surface, icicles: settings.icicles, ink: ink)
                    ink.ctx.restoreGState()
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
            paintFlakes(screen.sim.released, ink: ink, dirty: dirty)
            if let workshop {
                for ball in workshop.balls where workshop.revealed(ball.id) {
                    let center = screen.local(CGRect(origin: ball.center, size: .zero)).origin
                    ink.ctx.saveGState()
                    ink.ctx.translateBy(x: center.x, y: center.y)
                    if !reducedMotion { ink.ctx.rotate(by: ball.spin) }
                    let tone = ball.id == workshop.balls.count - 1 ? 2 : ball.id
                    SnowmanArt.ball(.zero, radius: ball.radius, ink: ink, tone: tone)
                    ink.ctx.restoreGState()
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
    }

    private func workshopHint(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.midX - 158, y: 46, width: 316, height: 30)
    }

    private func paintFlakes(_ flakes: [Flake], ink: Ink, dirty: CGRect) {
        guard !flakes.isEmpty else { return }
        let buckets = (0..<8).map { _ in CGMutablePath() }
        let halos = CGMutablePath()
        for flake in flakes where dirty.intersects(flake.paintBounds) {
            let opacity = (0.26 + flake.depth * 0.61) * flake.opacity
            let radius = flake.radius
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
        var present = Set<UUID>()
        if showing {
            for screen in screens.values {
                for (ornament, rect, target) in screen.placements {
                    let snowman = ornament.kind == .snowman
                    let editing = model.editMode && target == nil
                    guard editing || snowman || ornament.kind == .calendar else { continue }
                    let frame = screen.global(rect)
                    let hitFrame = snowman && !editing
                        ? frame.insetBy(dx: frame.width * 0.15, dy: frame.height * 0.047)
                        : frame
                    guard studio?.intersects(hitFrame) != true else { continue }
                    if let target, windows.prefix(while: { $0.id != target.id }).contains(where: { $0.rect.intersects(hitFrame) }) {
                        continue
                    }
                    present.insert(ornament.id)
                    let (panel, view) = handles[ornament.id] ?? makeHandle(for: ornament.id, frame: hitFrame)
                    if panel.frame != hitFrame { panel.setFrame(hitFrame, display: false) }
                    if !panel.isVisible { panel.orderFrontRegardless() }
                    let id = ornament.id
                    if snowman {
                        view.editTitle = "给雪人换装"
                        view.settings = { [weak self] in self?.model.showWardrobe?(id, frame) }
                        view.knock = model.editMode ? nil : { [weak self, weak screen] in
                            if let screen { self?.knockSnowman(ornament, from: frame, on: screen) }
                        }
                    }
                    view.drag = editing ? { [weak self] point in self?.drag(id, to: point) } : nil
                    view.down = editing ? { [weak self] point in self?.handleDown(id, point: point, frame: frame) } : nil
                    view.up = { [weak self] point in self?.handleUp(id, point: point, frame: frame) }
                }
            }
        }
        for id in Array(handles.keys) where !present.contains(id) {
            handles.removeValue(forKey: id)?.0.orderOut(nil)
        }
    }

    private func makeHandle(for id: UUID, frame: CGRect) -> (OverlayPanel, HandleView) {
        let panel = OverlayPanel(frame: frame, level: .init(rawValue: overlayLevel.rawValue + 1), interactive: true)
        let view = HandleView()
        panel.contentView = view
        view.remove = { [weak self] in self?.model.remove(id) }
        view.settings = { [weak self] in
            self?.model.selectedOrnament = id
            self?.model.showStudio?()
        }
        handles[id] = (panel, view)
        return (panel, view)
    }

    private func handleDown(_ id: UUID, point: CGPoint, frame: CGRect) {
        guard model.editMode else { return }
        model.selectedOrnament = id
        dragSession = (id, point, p(frame.midX, frame.midY))
        workingPlacement = false
    }

    private func drag(_ id: UUID, to point: CGPoint) {
        guard let session = dragSession, session.id == id else { return }
        let dx = point.x - session.start.x
        let dy = point.y - session.start.y
        guard workingPlacement || hypot(dx, dy) > 3 else { return }
        guard let screen = screens.values.first(where: { $0.frame.contains(point) }) else { return }
        workingPlacement = true
        let x = (session.center.x + dx - screen.usable.minX) / screen.usable.width
        let y = (session.center.y + dy - screen.usable.minY) / screen.usable.height
        model.change(id) {
            $0.display = screen.id
            $0.x = min(0.98, max(0.02, x))
            $0.y = min(0.98, max(0.02, y))
        }
    }

    private func handleUp(_ id: UUID, point: CGPoint, frame: CGRect) {
        let wasDragging = workingPlacement
        dragSession = nil
        workingPlacement = false
        guard !wasDragging, let ornament = model.settings.ornaments.first(where: { $0.id == id }) else { return }
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
