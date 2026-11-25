import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
enum Snowglow {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 3 && arguments[1] == "--write-icon" {
            exit(writeIcon(to: URL(fileURLWithPath: arguments[2])) ? 0 : 1)
        }
        if arguments.contains("--self-test") {
            SelfTest.run()
            return
        }
        if arguments.count == 7, arguments[1] == "--calibrate-dock" {
            let values = arguments.dropFirst(3).compactMap { Double($0) }
            guard values.count == 4, values.allSatisfy(\.isFinite), let display = UInt32(arguments[2]),
                  let screen = NSScreen.screens.first(where: { $0.snowScreenID == display }) else { exit(2) }
            let bounds = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            let dock = DesktopDock(primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
            guard !bounds.isEmpty, dock.calibrate(bounds, on: screen) else { exit(2) }
            print("Dock calibrated: \(dock.frame(on: screen) ?? bounds)")
            return
        }
        if arguments.count == 2,
           ["--enable-lock-snow", "--restore-lock-wallpaper"].contains(arguments[1]) {
            do {
                try LockScreenSnow.setEnabled(arguments[1] == "--enable-lock-snow")
                print(LockScreenSnow.isEnabled ? "Lock screen snow enabled." : "Wallpaper restored.")
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = SnowAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func writeIcon(to url: URL) -> Bool {
        guard let image = WinterArtwork.bitmap(width: 1024, height: 1024, draw: { ink in
            let plate = CGRect(x: 79, y: 79, width: 866, height: 866)
            let outline = CGPath(roundedRect: plate, cornerWidth: 204, cornerHeight: 204, transform: nil)
            ink.ctx.addPath(outline)
            ink.ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: NSColor(white: 0, alpha: 0.42).cgColor)
            ink.ctx.setFillColor(NSColor(rgb: 0x17334b).cgColor)
            ink.ctx.fillPath()
            ink.ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ink.ctx.addPath(outline)
            ink.ctx.clip()
            ink.gradient(plate, [0x254d68, 0x17384f, 0x0d2035])
            ink.glow(499, 464, 471, 0x83e3f8, alpha: 0.37)
            let center = p(514, 520)
            for index in 0..<6 {
                let angle = Double(index) * .pi / 3 - .pi / 2
                let pivot = p(center.x + 154 * cos(angle), center.y + 154 * sin(angle))
                let tip = p(center.x + 248 * cos(angle), center.y + 248 * sin(angle))
                ink.line([center, tip], 0xe1f6ff, width: 30)
                for side in [-1.0, 1.0] {
                    let sideAngle = angle - side * 0.75
                    ink.line([p(pivot.x + 80 * cos(sideAngle), pivot.y + 80 * sin(sideAngle)), pivot],
                             0xe1f6ff, width: 23)
                }
            }
            ink.glow(717, 275, 96, 0xffc65e, alpha: 0.50)
            ink.star(717, 275, 41, 0xffd899, points: 4)
            ink.circle(320, 316, 15, 0x9edfec, alpha: 0.64)
            ink.circle(749, 702, 12, 0xa2ebf1, alpha: 0.61)
        }), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

@MainActor
final class SnowAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = SnowModel()
    private var engine: DesktopEngine?
    private var status: NSStatusItem?
    private var studio: NSWindow?
    private var wardrobe: NSPanel?
    private var openedBeforeLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let wallpaperService = WallpaperService(model: model)
        model.wallpaperService = wallpaperService
        let engine = DesktopEngine(model: model)
        engine.studioFrame = { [weak self] in
            guard let studio = self?.studio, studio.isVisible, !studio.isMiniaturized else { return nil }
            return studio.frame
        }
        self.engine = engine
        model.showStudio = { [weak self] in self?.showStudio() }
        model.hideStudio = { [weak self] in self?.studio?.orderOut(nil) }
        model.clearSnow = { [weak engine] in engine?.clear() }
        model.runPlow = { [weak engine] in engine?.runPlow() }
        model.startPreview = { [weak engine] in engine?.preview() }
        model.lockSnowActive = LockScreenSnow.isEnabled
        model.toggleLockSnow = { [weak self] in self?.toggleLockScreenSnow() }
        model.startPicking = { [weak engine] in engine?.beginPicking() }
        model.startSnowman = { [weak self, weak engine] in
            self?.wardrobe?.orderOut(nil)
            engine?.startSnowman()
        }
        model.cancelSnowman = { [weak engine] in engine?.cancelSnowman(reopen: true) }
        model.assembleSnowman = { [weak engine] in engine?.assembleSnowman() }
        model.showWardrobe = { [weak self] id, frame in self?.showWardrobe(id: id, beside: frame) }
        installMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !model.welcomeSeen || openedBeforeLaunching || CommandLine.arguments.contains("--studio") {
            model.welcomeSeen = true
            model.persist()
            showStudio()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openedBeforeLaunching = true
        showStudio()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
        model.persist()
    }

    @objc private func displaysChanged() { engine?.updateScreens() }

    @objc private func openStudio() { showStudio() }

    private func showStudio() {
        if studio == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 654),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Snowglow"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.minSize = CGSize(width: 865, height: 610)
            window.backgroundColor = NSColor(rgb: 0x0c1726)
            window.appearance = NSAppearance(named: .darkAqua)
            window.delegate = self
            window.contentView = NSHostingView(rootView: StudioView(model: model, page: .snowfall))
            window.center()
            studio = window
        }
        studio?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        studio?.makeKeyAndOrderFront(nil)
        addKeyMenu()
    }

    private func showWardrobe(id: UUID, beside anchor: CGRect?) {
        guard model.settings.ornaments.contains(where: { $0.id == id && $0.kind == .snowman }) else { return }
        let size = CGSize(width: 344, height: 456)
        if wardrobe == nil {
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                                styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.title = "雪人衣帽间"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            wardrobe = panel
        }
        guard let panel = wardrobe else { return }
        let root = SnowmanWardrobe(model: model, id: id, close: { [weak panel] in panel?.orderOut(nil) },
                                  share: { [weak self] in self?.shareSnowman(id) })
        panel.contentView = NSHostingView(rootView: root)
        let mouse = NSEvent.mouseLocation
        let reference = anchor ?? CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        let center = p(reference.midX, reference.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main {
            let usable = screen.visibleFrame.insetBy(dx: 9, dy: 9)
            let right = reference.maxX + 13
            let left = reference.minX - size.width - 13
            let x = right + size.width < usable.maxX ? right : left
            let y = reference.maxY + 68 - size.height
            let origin = p(max(usable.minX, min(usable.maxX - size.width, x)),
                           max(usable.minY, min(usable.maxY - size.height, y)))
            panel.setFrame(CGRect(origin: origin, size: size), display: false)
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        addKeyMenu()
    }

    private func shareSnowman(_ id: UUID) {
        guard let ornament = model.settings.ornaments.first(where: { $0.id == id }),
              let content = wardrobe?.contentView else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Snowglow-" + UUID().uuidString, directoryHint: .isDirectory)
        let file = folder.appending(path: "Snowglow 雪人.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SnowmanPortrait.write(ornament, to: file)
            NSSharingServicePicker(items: [file]).show(relativeTo: content.bounds, of: content, preferredEdge: .minY)
        } catch {
            let alert = NSAlert(error: error)
            if let wardrobe { alert.beginSheetModal(for: wardrobe) }
        }
    }

    private func addKeyMenu() {
        guard NSApp.mainMenu == nil else { return }
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu(title: "Snowglow")
        app.submenu?.addItem(item("显示 Snowglow", #selector(openStudio), key: ","))
        app.submenu?.addItem(item("退出 Snowglow", #selector(terminate), key: "q"))
        menu.addItem(app)

        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "编辑")
        let editActions = [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                           ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")]
        for (title, action, shortcut) in editActions {
            edit.submenu?.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: shortcut))
        }
        menu.addItem(edit)

        let window = NSMenuItem()
        window.submenu = NSMenu(title: "窗口")
        let close = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.submenu?.addItem(close)
        menu.addItem(window)
        NSApp.mainMenu = menu
    }

    private func installMenu() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Snowglow 雪灯桌面")
        symbol?.isTemplate = true
        status.button?.image = symbol
        status.button?.toolTip = "Snowglow 雪灯桌面"
        status.button?.setAccessibilityLabel("Snowglow 雪灯桌面")
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        self.status = status
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("打开 Snowglow", #selector(openStudio), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(model.settings.enabled ? "暂停降雪" : "开始降雪", #selector(toggleSnow)))
        menu.addItem(item("清除积雪", #selector(clear)))
        menu.addItem(item("预览空闲模式", #selector(preview)))
        if LockScreenSnow.supported {
            if !model.lockSnowChanging { model.lockSnowActive = LockScreenSnow.isEnabled }
            let lockSnow = item(model.lockSnowActive ? "恢复原壁纸" : "启用锁屏飘雪", #selector(toggleLockScreenSnow))
            lockSnow.isEnabled = !model.lockSnowChanging
            menu.addItem(lockSnow)
        }
        menu.addItem(.separator())
        menu.addItem(item("应用雪夜木屋", #selector(applyCabin)))
        if model.buildingSnowman {
            menu.addItem(item("自动堆好雪人", #selector(assembleSnowman)))
            menu.addItem(item("结束堆雪人", #selector(cancelSnowman)))
        } else {
            menu.addItem(item("堆雪人…", #selector(startSnowman)))
        }
        if !model.settings.ornaments.isEmpty {
            menu.addItem(.separator())
            menu.addItem(item(model.settings.ornamentsVisible ? "收起装饰" : "恢复装饰", #selector(toggleDecorations)))
            let edit = item(model.editMode ? "结束摆放" : "在桌面摆放", #selector(toggleEditing))
            edit.isEnabled = model.settings.ornamentsVisible
            menu.addItem(edit)
        }
        menu.addItem(.separator())
        menu.addItem(item("退出 Snowglow", #selector(terminate), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    @objc private func toggleSnow() { model.settings.enabled.toggle() }
    @objc private func clear() { engine?.clear() }
    @objc private func preview() { engine?.preview() }
    @objc private func toggleLockScreenSnow() {
        guard !model.lockSnowChanging else { return }
        let enable = !model.lockSnowActive
        model.lockSnowChanging = true
        model.feedback = enable ? "正在启用锁屏飘雪…" : "正在恢复原壁纸…"
        Task {
            defer { model.lockSnowChanging = false }
            do {
                try await Task.detached(priority: .userInitiated) { try LockScreenSnow.setEnabled(enable) }.value
                model.lockSnowActive = LockScreenSnow.isEnabled
                model.feedback = model.lockSnowActive ? "锁屏飘雪已启用。" : "已恢复原壁纸。"
            } catch {
                model.lockSnowActive = LockScreenSnow.isEnabled
                model.feedback = error.localizedDescription
            }
        }
    }
    @objc private func applyCabin() { model.applyCabinScene() }
    @objc private func startSnowman() { model.startSnowman?() }
    @objc private func cancelSnowman() { model.cancelSnowman?() }
    @objc private func assembleSnowman() { model.assembleSnowman?() }
    @objc private func toggleDecorations() { model.settings.ornamentsVisible.toggle() }
    @objc private func toggleEditing() {
        model.editMode.toggle()
        if model.editMode { studio?.orderOut(nil) }
    }
    @objc private func terminate() { NSApp.terminate(nil) }
}

@MainActor
private enum SelfTest {
    static func run() {
        let region = CGRect(x: 0, y: 0, width: 800, height: 600)
        let settings = SnowSettings()
        checkWindowSnow(in: region, settings: settings)
        checkWindowSnowCorners()
        checkStageAndDock(in: region)
        checkSnowSweep(in: region)
        checkCanvasDamage()
        checkPlowCycle(in: region, settings: settings)
        checkSnowmanWorkshop()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let christmas = calendar.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        let ornament = Ornament(kind: .calendar, display: 0, x: 0.5, y: 0.5, calendarStart: first)
        precondition(ornament.availableDoors(on: first, using: calendar) == 1)
        precondition(ornament.availableDoors(on: christmas, using: calendar) == 25)
        for day in 1...25 {
            let frame = DecorationArt.calendarDoorRect(day)
            precondition(DecorationArt.calendarDay(at: p(frame.midX, frame.midY)) == day)
        }
        let model = SnowModel(defaults: nil)
        model.settings.ornaments = [ornament]
        model.openDoor(3, in: ornament.id, now: first)
        precondition(model.settings.ornaments[0].opened.isEmpty)
        model.openDoor(1, in: ornament.id, now: first)
        precondition(model.settings.ornaments[0].opened == [1])
        model.saveScene(named: "Winter")
        model.settings.intensity = 1
        model.restoreScene(model.scenes[0])
        precondition(model.settings.intensity == 0.45)
        let state = try! JSONEncoder().encode(SnowStorage(settings: model.settings, scenes: model.scenes))
        let decoded = try! JSONDecoder().decode(SnowStorage.self, from: state)
        precondition(decoded.settings == model.settings && decoded.scenes.count == 1)
        precondition(decoded.settings.automaticPlowing && decoded.scenes[0].settings.automaticPlowing)
        model.settings.automaticPlowing = false
        let disabled = try! JSONEncoder().encode(model.settings)
        precondition(!(try! JSONDecoder().decode(SnowSettings.self, from: disabled)).automaticPlowing)
        precondition(Wallpaper.all.count == 32 && Set(Wallpaper.all.map(\.id)).count == 32)
        if Bundle.main.bundlePath.hasSuffix(".app") {
            precondition(Bundle.main.url(forResource: "WinterCabin", withExtension: "jpg") != nil)
        }
        for wallpaper in Wallpaper.all {
            precondition(WinterArtwork.render(wallpaper, width: 192, height: 120) != nil)
        }
        let screens = NSScreen.screens
        let visible = DesktopWindow.onscreen(primaryTop: screens.first?.frame.maxY ?? 0,
                                           ignoring: ProcessInfo.processInfo.processIdentifier)
        print("Passed: rounded window snow, drag and display handoff, falling window snow, cursor displacement and conserved floor deposition, Stage Manager geometry, Dock taper and landing, two plow passes with redeposition, snowball assembly and rebuilding, partial repaint, calendar, scene persistence, 32 wallpapers.")
        print("Live WindowServer: \(screens.count) display(s), \(visible.count) eligible window(s).")
    }

    private static func checkWindowSnow(in region: CGRect, settings: SnowSettings) {
        let titlebar = CGRect(x: -40, y: 130, width: 390, height: 450)
        let cover = CGRect(x: 120, y: 40, width: 160, height: 290)
        precondition(exposedEdge(titlebar, inside: region, blockedBy: [cover]) == [0...120, 280...350])
        var shake = WindowShake(rect: titlebar)
        for frame in 1...5 {
            precondition(!shake.update(titlebar.offsetBy(dx: CGFloat(frame * 4), dy: 0), at: Double(frame) / 60))
        }
        precondition(!shake.update(titlebar.offsetBy(dx: 16, dy: 0), at: 6.0 / 60))
        precondition(shake.update(titlebar.offsetBy(dx: 12, dy: 0), at: 7.0 / 60) && shake.fling > 0)
        precondition(!shake.update(titlebar.offsetBy(dx: 40, dy: 0), at: 8.0 / 60))

        let snowpack = WindowSnowpack()
        var previousDisplay = DisplayScene(id: 10, windowSnow: snowpack)
        previousDisplay.setSurfaces([SnowSurface(id: .window(12), rect: titlebar, visible: [0...350], floor: false)])
        let delta = CGFloat(1) / 60
        for frame in 0..<600 {
            previousDisplay.step(size: region.size, delta: delta * 2, time: CGFloat(frame) * delta * 2,
                                 settings: settings, reduced: false)
        }
        let original = previousDisplay.drift(on: .window(12))!.heights
        precondition(original.contains { $0 > 2 })
        previousDisplay.setSurfaces([])

        let moved = titlebar.offsetBy(dx: 280, dy: -60)
        let edge = SnowSurface(id: .window(12), rect: moved, visible: [moved.minX...moved.maxX], floor: false)
        let lower = SnowSurface(id: .window(13), rect: CGRect(x: 130, y: 320, width: 620, height: 180),
                                visible: [130...750], floor: false)
        let dock = SnowSurface(id: .dock, rect: CGRect(x: 130, y: 540, width: 620, height: 55),
                               visible: [130...750], floor: false)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        var destination = DisplayScene(id: 11, windowSnow: snowpack)
        destination.setSurfaces([edge, lower, dock, floor])
        precondition(destination.drift(on: edge.id)?.heights == original, "Moving or covering a window should preserve its snow")

        let detached = snowpack.take(12)!
        destination.dropWindowSnow(detached, from: edge, horizontalSpeed: 0, reduced: false)
        destination.setSurfaces([lower, dock, floor])
        precondition(destination.drift(on: edge.id) == nil && destination.fallingSnow.count > 5)
        precondition(destination.fallingSnow.allSatisfy {
            edge.visible[0].contains($0.center.x) && abs($0.contact.y - moved.minY) < 0.001
        })
        let detachedMass = destination.fallingSnow.map(\.mass).reduce(0, +)
        let visibleMass = original.filter { $0 >= 0.18 }.reduce(0, +)
        precondition(abs(detachedMass - visibleMass) < 0.01)

        let start = destination.fallingSnow[0].center.y
        for _ in 0..<9 { destination.stepFallingSnow(delta: delta, reduced: false) }
        let early = destination.fallingSnow[0].center.y
        for _ in 0..<9 { destination.stepFallingSnow(delta: delta, reduced: false) }
        let later = destination.fallingSnow[0].center.y
        precondition(early > start && later - early > early - start, "Snow should accelerate after detaching")
        var passedDock = false
        var sawPowder = false
        for _ in 0..<90 {
            destination.stepFallingSnow(delta: delta, reduced: false)
            passedDock = passedDock || destination.fallingSnow.contains { $0.center.y > dock.rect.minY }
            sawPowder = sawPowder || !destination.impactPowder.isEmpty
        }
        let bed = destination.drift(on: .floor)!
        precondition(passedDock && sawPowder && !destination.fallingSnowAnimating)
        precondition(destination.drift(on: lower.id) == nil && destination.drift(on: .dock) == nil)
        precondition(abs(bed.heights.reduce(0, +) - detachedMass) < 0.01, "Fallen snow should reach the floor at its original mass")

        let nearFloor = SnowSurface(id: edge.id, rect: moved.offsetBy(dx: 0, dy: floor.rect.minY - moved.minY - 30),
                                    visible: edge.visible, floor: false)
        var pending = DisplayScene(id: 12)
        pending.setSurfaces([floor])
        pending.dropWindowSnow(detached, from: nearFloor, horizontalSpeed: 0, reduced: true, pendingWindow: 12)
        for _ in 0..<40 { pending.stepFallingSnow(delta: delta, reduced: true) }
        precondition(pending.fallingSnowAnimating && pending.drift(on: .floor) == nil)
        pending.resolveFallingWindow(12, didDisappear: false)
        precondition(!pending.fallingSnowAnimating && pending.drift(on: .floor) == nil)

        pending.dropWindowSnow(detached, from: nearFloor, horizontalSpeed: 0, reduced: true, pendingWindow: 12)
        pending.resolveFallingWindow(12, didDisappear: true)
        for _ in 0..<40 { pending.stepFallingSnow(delta: delta, reduced: true) }
        precondition(!pending.fallingSnowAnimating && abs(pending.drift(on: .floor)!.heights.reduce(0, +) - detachedMass) < 0.01)
    }

    private static func checkWindowSnowCorners() {
        let rect = CGRect(x: 26, y: 35, width: 200, height: 100)
        let full = rect.minX...rect.maxX
        let window = SnowSurface(id: .window(1), rect: rect, visible: [full], floor: false, cornerRadius: 18)
        var snow = SnowDrift(width: rect.width, floor: false, seed: 70)
        precondition(WindowSnowCorner(drift: snow, surface: window, span: full, left: true) == nil)
        for _ in 0..<65 {
            for x in stride(from: CGFloat(3), to: rect.width, by: 6) { snow.land(at: x, mass: 4) }
            snow.settle()
        }
        for left in [true, false] {
            let corner = WindowSnowCorner(drift: snow, surface: window, span: full, left: left)!
            let path = CGMutablePath()
            path.move(to: corner.top)
            corner.append(to: path, fromTop: true)
            precondition(path.currentPoint == corner.base)
            let bounds = path.boundingBoxOfPath
            precondition(bounds.maxY > rect.minY + 18 && bounds.maxY < rect.minY + 32)
            precondition(left ? bounds.minX < rect.minX : bounds.maxX > rect.maxX)
            let clipped = (rect.minX + 2)...(rect.maxX - 2)
            precondition(WindowSnowCorner(drift: snow, surface: window, span: clipped, left: left) == nil)
        }
    }

    private static func checkStageAndDock(in region: CGRect) {
        let display = region.offsetBy(dx: -800, dy: 0)
        let normal = CGRect(x: -570, y: 145, width: 460, height: 315)
        let retreat = CGRect(x: -740, y: 211, width: 300, height: 205)
        let thumbnail = CGRect(x: -785, y: 260, width: 110, height: 72)
        precondition(StageWindow.isMovingToStrip(from: normal, to: retreat, on: [display, region]))
        precondition(StageWindow.isThumbnail(thumbnail, on: [display, region]))
        precondition(!StageWindow.isThumbnail(thumbnail, on: []))
        precondition(!StageWindow.isThumbnail(thumbnail.offsetBy(dx: 380, dy: 0), on: [display, region]))
        precondition(!StageWindow.isMovingToStrip(from: normal, to: normal.offsetBy(dx: -160, dy: 0), on: [display]))

        let dock = CGRect(x: 155, y: 535, width: 510, height: 65)
        let profile = DockSnowProfile(dock, radius: 23)
        let edge = profile.supportedRange.lowerBound
        precondition(profile.contactY(at: edge) > dock.minY && profile.coverage(at: edge) < 0.001)
        precondition(profile.coverage(at: edge + 10) > 0 && profile.coverage(at: edge + 10) < 1)
        precondition(profile.coverage(at: dock.midX) == 1 && profile.contactY(at: dock.midX) == dock.minY)
        var scene = DisplayScene(id: 1)
        let surface = SnowSurface(id: .dock, rect: dock, visible: [profile.supportedRange], floor: false, cornerRadius: profile.radius)
        scene.setSurfaces([surface])
        precondition(scene.landing(at: edge, from: dock.minY - 1, to: dock.minY + 20)?.y == profile.contactY(at: edge))
        precondition(scene.landing(at: dock.minX, from: dock.minY - 1, to: dock.maxY) == nil)
        let leftSnow = dock.minX + dock.width * 0.12
        let rightSnow = dock.minX + dock.width * 0.88
        for x in [leftSnow, rightSnow] {
            scene.shatterSnowman(at: p(x, dock.minY), on: surface, scale: 0.8, accumulate: true)
        }
        let original = scene.drift(on: .dock)!
        for width in [CGFloat(680), 390, dock.width] {
            let resized = CGRect(x: dock.midX - width / 2, y: dock.minY, width: width, height: dock.height)
            let ends = DockSnowProfile(resized, radius: profile.radius)
            let support = SnowSurface(id: .dock, rect: resized, visible: [ends.supportedRange], floor: false, cornerRadius: ends.radius)
            scene.setSurfaces([support])
            let drift = scene.drift(on: .dock)!
            precondition(drift.heights == original.heights && drift.width == original.width)
            for fraction in [CGFloat(0.12), 0.88] {
                let x = resized.minX + width * fraction
                let y = scene.landing(at: x, from: dock.minY - 15, to: dock.minY + 20)!.y
                precondition(abs(y - dock.minY + original.height(at: fraction * dock.width)) < 0.001)
            }
        }
    }

    private static func checkSnowSweep(in region: CGRect) {
        let snowpack = WindowSnowpack()
        var scene = DisplayScene(id: 8, windowSnow: snowpack)
        let sill = SnowSurface(id: .window(87), rect: CGRect(x: 116, y: 220, width: 384, height: 200),
                               visible: [116...320, 386...500], floor: false)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        scene.setSurfaces([sill, floor])
        var layer = SnowDrift(width: sill.rect.width, floor: false, seed: 93)
        for x in stride(from: CGFloat(15), to: layer.width - 12, by: 9) { layer.land(at: x, mass: 10) }
        snowpack[87] = layer
        let y = sill.rect.minY - layer.height(at: 142)
        let delta: CGFloat = 1.0 / 60
        precondition(!scene.sweepSnow(from: p(245, y), to: p(245, y), delta: delta, reduced: false))
        precondition(!scene.sweepSnow(from: p(345, y), to: p(362, y), delta: delta, reduced: false))
        precondition(scene.sweepSnow(from: p(240, y), to: p(264, y), delta: delta, reduced: false))
        let remaining = snowpack[87]!.heights.reduce(0, +)
        let displaced = scene.looseSnow.map(\.mass).reduce(0, +)
        precondition(displaced > 0 && !scene.impactPowder.isEmpty)
        precondition(abs(remaining + displaced - layer.heights.reduce(0, +)) < 0.01)
        precondition(snowpack[87]!.height(at: 142) < layer.height(at: 142))
        precondition(snowpack[87]!.height(at: 183) > layer.height(at: 183))
        for _ in 0..<120 { scene.stepFallingSnow(delta: delta, reduced: false) }
        precondition(!scene.fallingSnowAnimating)
        precondition(abs((scene.drift(on: .floor)?.heights.reduce(0, +) ?? 0) - displaced) < 0.01)
    }

    private static func checkCanvasDamage() {
        let size = CGSize(width: 960, height: 720)
        let old = CGRect(x: 24, y: 27, width: 8, height: 8)
        let next = CGRect(x: 263, y: 222, width: 8, height: 8)
        let staticSnow = CGRect(x: 47, y: 335, width: 420, height: 14)
        var grid = CanvasDamage()
        precondition(grid.regions(in: size, moving: [old], changed: [], full: false) == nil)
        let update = grid.regions(in: size, moving: [next], changed: [staticSnow], full: false)!
        precondition(update.contains(where: { $0.contains(old) }) && update.contains(where: { $0.contains(next) }))
        precondition(update.contains(where: { $0.intersects(staticSnow) }))
        precondition(!update.contains(where: { $0.contains(p(700, 500)) }))
        let last = grid.regions(in: size, moving: [], changed: [], full: false)!
        precondition(last.count == 1 && last[0].contains(next))
        precondition(grid.regions(in: size, moving: [], changed: [], full: false)?.isEmpty == true)
        precondition(grid.regions(in: size, moving: [], changed: [CGRect(origin: .zero, size: size)], full: false) == nil)

        let overlap = CGRect(x: 10, y: 20, width: 40, height: 30)
        let shifted = overlap.offsetBy(dx: 8, dy: 4)
        let strips = overlap.areasOutside(shifted)
        precondition(strips.allSatisfy { $0.intersection(overlap.intersection(shifted)).isEmpty })
        precondition(strips.reduce(0) { $0 + $1.width * $1.height } == 368)
    }

    private static func checkSnowmanWorkshop() {
        let anchor = WindowAnchor(id: 16, owner: "Fixture", pid: 7, x: 320, y: 259)
        let high = SnowballPlatform(id: .window(16), frame: CGRect(x: 190, y: 215, width: 265, height: 145),
                                    span: 190...455, anchor: anchor)
        let ground = SnowballPlatform(id: .ground(1), frame: CGRect(x: 0, y: 0, width: 650, height: 1),
                                      span: 0...650, anchor: nil)
        let platforms = [ground, high]
        var assembly = SnowmanWorkshop(platform: high, near: 300)
        assembly.advance(0.4, platforms: platforms)
        for id in [1, 2] {
            let moving = assembly.balls[id]
            let parent = assembly.balls[id - 1]
            assembly.grab(id, at: moving.center)
            assembly.drag(to: p(parent.center.x, parent.center.y + SnowmanArt.gap(parent.radius, moving.radius) + 39),
                          platforms: platforms)
            assembly.release(on: platforms)
            for _ in 0..<20 { assembly.advance(1.0 / 30, platforms: platforms) }
            precondition(assembly.balls[id].rest == .ball(id - 1))
        }
        precondition(assembly.completedPlatform(in: platforms)?.anchor == anchor)
        let before = assembly.balls[2].center
        let shifted = SnowballPlatform(id: .window(16), frame: high.frame.offsetBy(dx: 32, dy: -14),
                                       span: 222...487, anchor: anchor)
        assembly.advance(1.0 / 30, platforms: [ground, shifted])
        precondition(abs(assembly.balls[2].center.x - before.x - 32) < 0.1)
        precondition(abs(assembly.balls[2].center.y - before.y + 14) < 0.1)

        var rolling = SnowmanWorkshop(platform: high, near: 254)
        rolling.advance(0.4, platforms: platforms)
        let roller = rolling.balls[1]
        rolling.grab(1, at: roller.center)
        rolling.drag(to: p(204, roller.center.y), platforms: platforms)
        precondition(rolling.balls[0].rest == nil && rolling.balls[0].horizontalSpeed < 0)
        for _ in 0..<45 { rolling.advance(1.0 / 30, platforms: platforms) }
        guard case .platform(.ground(1), _) = rolling.balls[0].rest else { preconditionFailure("A loose ball should land below the sill") }

        let dock = SnowSurface(id: .dock, rect: CGRect(x: 175, y: 508, width: 300, height: 70), visible: [175...475], floor: false)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: 600, width: 700, height: 1), visible: [0...700], floor: true)
        var scene = DisplayScene(id: 1)
        scene.setSurfaces([floor, dock])
        var ornament = Ornament(kind: .snowman, display: 1, x: 0.5, y: 0.5)
        ornament.hat = .santa
        ornament.costume = SnowmanCostume()
        for count in [2, 3] {
            ornament.snowballs = count
            let bounds = CGRect(x: 261, y: high.top - 22, width: 115, height: 172)
            var knocked = SnowmanWorkshop(knocking: ornament, from: bounds, direction: 1, reduced: false)
            for _ in 0..<60 { knocked.advance(1.0 / 60, platforms: platforms) }
            precondition(knocked.balls.count == count && knocked.completedPlatform(in: platforms) == nil)
            precondition(abs(knocked.balls[0].center.x - knocked.balls[count - 1].center.x) > 35)
            precondition(knocked.balls.contains { abs($0.spin) > 0.2 })
            knocked.rebuild(at: count - 1, on: platforms)
            precondition(knocked.completedPlatform(in: platforms) != nil)
            precondition(knocked.balls.allSatisfy { $0.center.x == knocked.balls[0].center.x })
        }
        var falling = FallingSnowman(ornament: ornament, rect: CGRect(x: 220, y: 205, width: 76, height: 100), sway: 16)
        for _ in 0..<45 {
            if !falling.advance(1.0 / 30, scene: &scene, limit: 600, accumulate: true, reduced: false) { break }
        }
        precondition(!scene.released.isEmpty && scene.drift(on: .dock)?.maximumDepth == 7)
        precondition(scene.drift(on: .floor) == nil)
        let encoded = try! JSONEncoder().encode(ornament)
        precondition((try! JSONDecoder().decode(Ornament.self, from: encoded)) == ornament)
    }

    private static func checkPlowCycle(in region: CGRect, settings: SnowSettings) {
        let floorRect = CGRect(x: 0, y: region.maxY - 1, width: region.width, height: 1)
        let floor = SnowSurface(id: .floor, rect: floorRect, visible: [0...region.width], floor: true)
        var drift = SnowDrift(width: region.width, floor: true, seed: 89)
        for _ in 0..<4 { drift.land(at: 400, mass: 6) }
        let initialMass = drift.heights.reduce(0, +)
        let initialPeak = drift.heights.max()!
        for _ in 0..<18 { drift.settle() }
        precondition(abs(drift.heights.reduce(0, +) - initialMass) < 0.0001 && drift.heights.max()! < initialPeak)
        precondition(!drift.readyToPlow)

        var simulation = DisplayScene(id: 8)
        simulation.setSurfaces([floor])
        var directions: [CGFloat] = []
        var sawPartialClear = false
        var sawPowder = false
        var snowBeforePass: CGFloat = 0
        var sawLooseSnow = false
        let delta = CGFloat(1) / 30
        for frame in 0..<4500 {
            let previous = simulation.plow
            let completed = simulation.completedPasses
            simulation.step(size: region.size, delta: delta, time: CGFloat(frame) * delta,
                            settings: settings, reduced: false)
            sawLooseSnow = sawLooseSnow || !simulation.looseSnow.isEmpty
            simulation.stepFallingSnow(delta: delta, reduced: false)
            if let pass = simulation.plow {
                if previous == nil {
                    directions.append(pass.direction)
                    snowBeforePass = simulation.drift(on: .floor)?.heights.reduce(0, +) ?? 0
                }
                sawPowder = sawPowder || !simulation.powder.isEmpty
                if pass.direction > 0, (300...500).contains(pass.bladeX(width: region.width)),
                   let bed = simulation.drift(on: .floor) {
                    sawPartialClear = sawPartialClear || (bed.height(at: 100) < 3.4 && bed.height(at: 700) > 3.5)
                }
            }
            if simulation.completedPasses > completed {
                let bed = simulation.drift(on: .floor)!
                precondition(simulation.plow == nil && bed.heights.reduce(0, +) < snowBeforePass * 0.4)
                precondition(bed.heights.contains(where: { $0 > 0.3 }), "Some snow should settle back after the blade passes")
            }
            if simulation.completedPasses == 2 { break }
        }
        precondition(simulation.completedPasses == 2 && directions == [1, -1] && sawPartialClear && sawPowder && sawLooseSnow)
        simulation.startPlow()
        simulation.clearAccumulation()
        precondition(!simulation.plowAnimating && simulation.drift(on: .floor) == nil)
    }
}
