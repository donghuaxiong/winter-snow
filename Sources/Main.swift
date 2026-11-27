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
        if arguments.count == 3 && arguments[1] == "--render-3d-preview" {
            exit(write3DPreview(to: URL(fileURLWithPath: arguments[2])) ? 0 : 1)
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

    private static func write3DPreview(to url: URL) -> Bool {
        let width = 1440
        let height = 620
        guard let image = WinterArtwork.bitmap(width: width, height: height, draw: { ink in
            ink.gradient(CGRect(x: 0, y: 0, width: width, height: height), [0x0D1B2E, 0x152B46, 0x0B1524])
            // Subtle simulated dark macOS window top bar & snow ledge across the bottom
            let ledgeY: CGFloat = 500
            ink.rounded(CGRect(x: 60, y: ledgeY, width: CGFloat(width - 120), height: 140), 18, 0x1E222A)
            ink.line([p(78, ledgeY + 1), p(CGFloat(width - 78), ledgeY + 1)], 0x4A5B70, width: 1.5, alpha: 0.45)

            var snowman1 = Ornament(kind: .snowman, display: 0, x: 0.5, y: 0.5)
            snowman1.hat = .top
            snowman1.snowballs = 3
            snowman1.costume = SnowmanCostume(face: .smile, scarf: .red, arms: true, buttons: true)

            var snowman2 = Ornament(kind: .snowman, display: 0, x: 0.5, y: 0.5)
            snowman2.hat = .santa
            snowman2.snowballs = 2
            snowman2.costume = SnowmanCostume(face: .happy, scarf: .green, arms: true, buttons: true)

            var gift = Ornament(kind: .gift, display: 0, x: 0.5, y: 0.5)
            gift.palette = .classic

            var tree = Ornament(kind: .tree, display: 0, x: 0.5, y: 0.5)
            tree.palette = .classic
            tree.extras = true

            let now = Date()
            DecorationArt.draw(snowman1, in: CGRect(x: 110, y: ledgeY - 310, width: 256, height: 330), with: ink, time: 0, now: now)
            DecorationArt.draw(snowman2, in: CGRect(x: 410, y: ledgeY - 280, width: 234, height: 300), with: ink, time: 0, now: now)
            DecorationArt.draw(gift, in: CGRect(x: 690, y: ledgeY - 205, width: 220, height: 215), with: ink, time: 0, now: now)
            DecorationArt.draw(tree, in: CGRect(x: 960, y: ledgeY - 390, width: 340, height: 408), with: ink, time: 0, now: now)
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
        engine.studioWindow = { [weak self] in self?.studio }
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
        model.hangLights = { [weak engine] id in engine?.beginHangingLights(id) }
        model.sendSleigh = { [weak engine] in engine?.sendSleigh() }
        model.cancelSnowman = { [weak engine] in engine?.cancelSnowman(reopen: true) }
        model.assembleSnowman = { [weak engine] in engine?.assembleSnowman() }
        model.placeCollectedSnowman = { [weak engine] in engine?.placeCollectedSnowman($0) }
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

    @objc private func displaysChanged() {
        engine?.updateScreens()
        if let wardrobe, wardrobe.isVisible { fitWardrobe(wardrobe) }
    }

    @objc private func openStudio() { showStudio() }

    private func showStudio() {
        if studio == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 930, height: 700),
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
            window.backgroundColor = .windowBackgroundColor
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
        if wardrobe == nil {
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: SnowmanWardrobe.preferredContentSize),
                                styleMask: [.titled, .closable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "雪人衣帽间"
            panel.titleVisibility = .hidden
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
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        fitWardrobe(panel, beside: anchor ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1)))
        panel.makeKeyAndOrderFront(nil)
        addKeyMenu()
    }

    private func fitWardrobe(_ panel: NSPanel, beside anchor: CGRect? = nil) {
        let reference = anchor ?? panel.frame
        let center = CGPoint(x: reference.midX, y: reference.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main {
            let contentRect = CGRect(origin: .zero, size: SnowmanWardrobe.preferredContentSize)
            let frameSize = panel.frameRect(forContentRect: contentRect).size
            let frame = SnowmanWardrobe.windowFrame(preferredSize: frameSize, beside: anchor,
                                                   currentFrame: panel.frame, in: screen.visibleFrame)
            panel.setFrame(frame, display: panel.isVisible)
        } else {
            panel.center()
        }
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
        let rollSnow = item("鼠标搓雪球", #selector(toggleRollSnow))
        rollSnow.state = model.settings.rollSnowballs ? .on : .off
        menu.addItem(rollSnow)
        let finishSnowman = item("叠满三颗自动成型", #selector(toggleAutomaticSnowman))
        finishSnowman.state = model.settings.automaticallyFinishSnowman ? .on : .off
        menu.addItem(finishSnowman)
        if engine?.hasRolledSnowman == true {
            menu.addItem(item("堆成雪人", #selector(buildRolledSnowman)))
        }
        menu.addItem(item("自由挂彩灯…", #selector(hangLights)))
        menu.addItem(item("让雪橇出发", #selector(sendSleigh)))
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
    @objc private func toggleRollSnow() { model.settings.rollSnowballs.toggle() }
    @objc private func toggleAutomaticSnowman() { model.settings.automaticallyFinishSnowman.toggle() }
    @objc private func buildRolledSnowman() { engine?.finishRolledSnowman() }
    @objc private func hangLights() { model.hangLights?(nil) }
    @objc private func sendSleigh() { model.sendSleigh?() }
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
        checkNaturalWindowOverflow(in: region)
        checkSnowPause(in: region)
        checkPausedSnowPlay(in: region)
        checkDirectSnowRolling(in: region)
        checkRolledSnowman(in: region)
        checkFreeSnowPlay(in: region)
        checkSnowballThrows(in: region)
        checkSnowballLedgeFalls(in: region)
        checkFestiveEffects(in: region)
        checkStageAndDock(in: region)
        checkSnowSweep(in: region)
        checkCanvasDamage()
        checkPlowCycle(in: region, settings: settings)
        checkSnowmanWorkshop()
        checkSnowmanGroundAndPlow()
        checkSnowmanWardrobeFrame()
        checkDecorationPlacement()
        checkWreathRemoval()

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
        precondition(!decoded.settings.plowDestroysDecorations && !decoded.scenes[0].settings.plowDestroysDecorations)
        model.settings.automaticPlowing = false
        model.settings.plowDestroysDecorations = true
        let enabledCollision = try! JSONEncoder().encode(model.settings)
        let settingsWithCollision = try! JSONDecoder().decode(SnowSettings.self, from: enabledCollision)
        precondition(!settingsWithCollision.automaticPlowing && settingsWithCollision.plowDestroysDecorations)
        precondition(Wallpaper.winter.map(\.id) == Array(31...38))
        precondition(Wallpaper.christmas.map(\.id) == Array(39...42))
        precondition(Set(Wallpaper.all.map(\.id)).count == Wallpaper.all.count)
        if Bundle.main.bundlePath.hasSuffix(".app") {
            for wallpaper in Wallpaper.all {
                precondition(WinterArtwork.render(wallpaper, width: 192, height: 108) != nil)
                precondition(WinterArtwork.render(wallpaper, width: 108, height: 192) != nil)
            }
        }
        var retired = SnowSettings()
        retired.wallpaper = 8
        var retained = SnowSettings()
        retained.wallpaper = 31
        var storage = SnowStorage(settings: retired, scenes: [
            SavedScene(name: "Retired", settings: retired),
            SavedScene(name: "Cabin", settings: retained),
            SavedScene(name: "Original", settings: SnowSettings())
        ])
        storage.migrateRetiredWallpapers()
        precondition(storage.settings.wallpaper == nil)
        precondition(storage.scenes.map { $0.settings.wallpaper } == [31, 31, nil])
        let screens = NSScreen.screens
        let visible = DesktopWindow.onscreen(primaryTop: screens.first?.frame.maxY ?? 0,
                                           ignoring: ProcessInfo.processInfo.processIdentifier)
        print("Passed: window snow, natural overflow, pause and resume, Dock and Stage Manager geometry, plow cycle, preset and free-form snowmen, snowman collections, snowball growth, throws, window-to-window falls and floor impacts, free-hanging and attached lights, fullscreen and power policy, gusts, sleigh gifts, tree branch snow, partial repaint, calendar, scene persistence, and \(Wallpaper.all.count) wallpapers.")
        if let visible {
            print("Live WindowServer: \(screens.count) display(s), \(visible.count) eligible window(s).")
        } else {
            print("Live WindowServer: \(screens.count) display(s), window list unavailable.")
        }
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

    private static func checkNaturalWindowOverflow(in region: CGRect) {
        let rect = CGRect(x: 180, y: 110, width: 360, height: 280)
        let upper = SnowSurface(id: .window(21), rect: rect, visible: [180...540], floor: false, cornerRadius: 18)
        let lower = SnowSurface(id: .window(22), rect: CGRect(x: 65, y: 320, width: 390, height: 190),
                                visible: [65...455], floor: false, cornerRadius: 18)
        let dock = SnowSurface(id: .dock, rect: CGRect(x: 65, y: 535, width: 390, height: 60),
                               visible: [65...455], floor: false, cornerRadius: 20)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let id: UInt32 = 21
        var thick = SnowDrift(width: rect.width, floor: false, seed: 70)
        thick.depositImpact(at: 3, mass: 43, width: 9)
        var thin = SnowDrift(width: rect.width, floor: false, seed: 70)
        thin.land(at: 9, mass: 6)
        precondition(thin.spillFromCorner(left: true, at: 10) == 0)
        var timed = thick
        let mass = timed.spillFromCorner(left: true, at: 10)
        precondition(mass > 0 && timed.heights[0] > 0 && timed.heights[4] == thick.heights[4])
        precondition(abs(thick.heights.reduce(0, +) - timed.heights.reduce(0, +) - mass) < 0.001)
        timed.depositImpact(at: 3, mass: 43, width: 9)
        precondition(timed.spillFromCorner(left: true, at: 11) == 0)
        precondition(timed.spillFromCorner(left: true, at: 16) > 0)

        let masked = SnowSurface(id: upper.id, rect: rect, visible: [186...540], floor: false, cornerRadius: 18)
        let nearCover = CGRect(x: 170, y: 117, width: 24, height: 80)
        let covered = SnowSurface(id: upper.id, rect: rect, visible: upper.visible, floor: false,
                                  occluders: [nearCover], cornerRadius: 18)
        precondition(masked.overflowCorner(left: true, on: floor.rect) == nil)
        precondition(covered.overflowCorner(left: true, on: floor.rect) == nil)

        var settings = SnowSettings()
        settings.intensity = 0
        settings.automaticPlowing = false
        let quietFlake = Flake(x: 0, y: 0, radius: 1, speed: 0, phase: 0, depth: 0)
        for support in [lower, dock, floor] {
            let shared = WindowSnowpack()
            shared[id] = thick
            var scene = DisplayScene(id: 9, windowSnow: shared)
            scene.flakes = Array(repeating: quietFlake, count: 32)
            scene.setSurfaces(support.floor ? [upper, floor] : [upper, support, floor])
            scene.step(size: region.size, delta: 0.18, time: 10, settings: settings, reduced: false)
            precondition(scene.fallingSnow.count == 1 && scene.fallingSnow[0].followsCorner)
            let clump = scene.fallingSnow[0]
            let moved = SnowSurface(id: upper.id, rect: rect.offsetBy(dx: 14, dy: 0),
                                    visible: [194...554], floor: false, cornerRadius: 18)
            scene.setSurfaces(support.floor ? [moved, floor] : [moved, support, floor])
            scene.stepFallingSnow(delta: 1.0 / 60, reduced: false)
            precondition(scene.fallingSnow[0].center.x > clump.center.x + 10, "Sliding snow follows the moving corner")
            for _ in 0..<120 { scene.stepFallingSnow(delta: 1.0 / 60, reduced: false) }
            precondition(scene.fallingSnow.isEmpty && shared[id]!.heights[0] > 0)
            precondition(abs(scene.drift(on: support.id)!.heights.reduce(0, +) - clump.mass) < 0.001)
            if !support.floor { precondition(scene.drift(on: .floor) == nil) }
        }
    }

    private static func checkSnowPause(in region: CGRect) {
        let sill = SnowSurface(id: .window(17), rect: CGRect(x: 100, y: 220, width: 300, height: 200),
                               visible: [100...400], floor: false, cornerRadius: 18)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let shared = WindowSnowpack()
        var bank = SnowDrift(width: sill.rect.width, floor: false, seed: 91)
        bank.depositImpact(at: 90, mass: 25, width: 14)
        shared[17] = bank
        var scene = DisplayScene(id: 23, windowSnow: shared)
        scene.setSurfaces([sill, floor])
        var settings = SnowSettings()
        settings.wind = 0
        settings.automaticPlowing = false
        let delta: CGFloat = 1.0 / 30
        scene.step(size: region.size, delta: 0, time: 0, settings: settings, reduced: false)
        scene.flakes = [Flake(x: 500, y: -30, radius: 2, speed: 80, phase: 0, depth: 1),
                        Flake(x: 550, y: 95, radius: 2, speed: 80, phase: 0, depth: 1),
                        Flake(x: 600, y: region.maxY - 1, radius: 2, speed: 80, phase: 0, depth: 1)]
        scene.step(size: region.size, delta: delta, time: delta, settings: settings, reduced: false, emitting: false)
        precondition(scene.flakes.count == 1 && scene.flakes[0].y > 95, "Pause drains visible snow and discards queued flakes")
        let floorMass = scene.drift(on: .floor)!.heights.reduce(0, +)
        for frame in 2...260 {
            scene.step(size: region.size, delta: delta, time: CGFloat(frame) * delta,
                       settings: settings, reduced: false, emitting: false)
        }
        precondition(scene.flakes.isEmpty && scene.drift(on: .floor)!.heights.reduce(0, +) > floorMass)
        precondition(abs(shared[17]!.heights.reduce(0, +) - bank.heights.reduce(0, +)) < 0.001)
        scene.step(size: region.size, delta: 0.001, time: 9, settings: settings, reduced: false)
        precondition(!scene.flakes.isEmpty && scene.flakes.allSatisfy { $0.y < 0 }, "Resumed flakes arrive from above")
        scene.clearAccumulation()
        precondition(scene.drift(on: .floor) == nil && shared.isEmpty)
    }

    private static func checkPausedSnowPlay(in region: CGRect) {
        let window: SurfaceID = .window(54)
        let sill = SnowSurface(id: window, rect: CGRect(x: 120, y: 210, width: 320, height: 170),
                               visible: [120...440], floor: false, cornerRadius: 18)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let shared = WindowSnowpack()
        var bank = SnowDrift(width: sill.rect.width, floor: false, seed: 92)
        bank.depositImpact(at: 97, mass: 2.4, width: 7)
        bank.depositImpact(at: 193, mass: 32, width: 24)
        shared[54] = bank
        var scene = DisplayScene(id: 12, windowSnow: shared)
        scene.setSurfaces([sill, floor])
        var settings = SnowSettings()
        settings.enabled = false
        scene.step(size: region.size, delta: 1.0 / 60, time: 2, settings: settings, reduced: false, emitting: false)
        var rolled = RolledSnow()
        let point = p(217, 209)
        rolled.take(at: point, time: 2, snow: &scene)
        let mass = rolled.balls[0].mass
        precondition(mass > 0 && mass < 1.4, "Thin retained snow can form a small ball")
        rolled.release(at: 2.13)
        precondition(rolled.held == nil && rolled.balls.count == 1)
        precondition(abs(bank.heights.reduce(0, +) - shared[54]!.heights.reduce(0, +) - mass) < 0.001)
        let y = sill.rect.minY - shared[54]!.height(at: 193)
        precondition(scene.sweepSnow(from: p(302, y), to: p(330, y), delta: 1.0 / 60, reduced: false))
        precondition(!scene.looseSnow.isEmpty && scene.flakes.isEmpty)

        let blocker = CGRect(x: 200, y: 181, width: 42, height: 44)
        scene.setSurfaces([SnowSurface(id: window, rect: sill.rect, visible: sill.visible, floor: false,
                                      occluders: [blocker], cornerRadius: sill.cornerRadius), floor])
        precondition(scene.harvestSnow(from: point, to: point) == 0)
    }

    private static func checkDirectSnowRolling(in region: CGRect) {
        var settings = SnowSettings()
        precondition(settings.rollSnowballs)
        settings.rollSnowballs = false
        precondition(!(try! JSONDecoder().decode(SnowSettings.self, from: JSONEncoder().encode(settings))).rollSnowballs)
        settings.rollSnowballs = true
        settings.enabled = false

        let shelf = SnowSurface(id: .window(59), rect: CGRect(x: 120, y: 210, width: 400, height: 170),
                                visible: [120...520], floor: false, cornerRadius: 18)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let shared = WindowSnowpack()
        let id: UInt32 = 59
        var pack = SnowDrift(width: shelf.rect.width, floor: false, seed: 162)
        for x in stride(from: 24, to: 285, by: 12) { pack.depositImpact(at: CGFloat(x), mass: 26, width: 20) }
        shared[id] = pack
        var scene = DisplayScene(id: 73, windowSnow: shared)
        scene.setSurfaces([shelf, floor])
        let point = p(204, 206)
        let hit = scene.rollHandle(at: point)!
        precondition(hit.contains(point) && hit.maxY <= shelf.rect.minY)
        precondition(scene.rollHandle(at: p(204, 218)) == nil && scene.rollHandle(at: p(440, 206)) == nil)
        scene.setSurfaces([SnowSurface(id: shelf.id, rect: shelf.rect, visible: shelf.visible, floor: false,
                                      occluders: [CGRect(x: 195, y: 185, width: 20, height: 37)], cornerRadius: 18), floor])
        precondition(scene.rollHandle(at: point) == nil)
        scene.setSurfaces([shelf, floor])

        var rolled = RolledSnow()
        rolled.take(at: point, time: 1, snow: &scene)
        for i in 1...8 { rolled.roll(to: p(point.x + CGFloat(i) * 13, 205), time: 1 + Double(i) * 0.035, snow: &scene) }
        let grown = rolled.balls[0]
        precondition(grown.mass > 6 && grown.rotation > 3)
        precondition(scene.rollingContact(near: rolled.pointer).map { abs(grown.center.y + grown.radius - $0) < 9 } == true)
        rolled.roll(to: p(445, 270), time: 1.34, snow: &scene)
        rolled.release(at: 1.51)
        var bounced = false
        for _ in 0..<170 {
            rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: false)
            bounced = bounced || (rolled.balls.first?.velocity.dy ?? 0) < 0
        }
        precondition(bounced && rolled.balls.count == 1 && !rolled.animating && scene.flakes.isEmpty)
    }

    private static func checkRolledSnowman(in region: CGRect) {
        let sill = SnowSurface(id: .window(77), rect: CGRect(x: 100, y: 228, width: 600, height: 190),
                               visible: [100...700], floor: false, cornerRadius: 18)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let shared = WindowSnowpack()
        var pack = SnowDrift(width: sill.rect.width, floor: false, seed: 27)
        for x in stride(from: 15, through: 560, by: 10) { pack.depositImpact(at: CGFloat(x), mass: 22, width: 17) }
        shared[77] = pack
        var scene = DisplayScene(id: 80, windowSnow: shared)
        scene.setSurfaces([sill, floor])
        var rolled = RolledSnow()
        for (index, strip) in [(135.0, 260.0), (355.0, 414.0), (520.0, 548.0)].enumerated() {
            let time = Double(index) * 4
            rolled.take(at: p(strip.0, 223), time: time, snow: &scene)
            rolled.roll(to: p(strip.1, 223), time: time + 0.45, snow: &scene)
            rolled.release(at: time + 0.62)
            for _ in 0..<150 { rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: false) }
        }
        precondition(rolled.balls.count == 3 && rolled.balls.allSatisfy { $0.rest != nil })
        let base = rolled.balls[0], middle = rolled.balls[1], top = rolled.balls[2]
        let grip = p(middle.center.x + 3, middle.center.y - 3)
        rolled.take(at: grip, time: 13, snow: &scene)
        rolled.roll(to: p(base.center.x + 3, base.center.y - base.radius - 6), time: 13.05, snow: &scene)
        precondition(rolled.release(at: 13.05) == middle.id, "A quick, centered drop still snaps to the lower ball")
        precondition(rolled.canFinishStack(containing: middle.id) && rolled.takeStack(containing: middle.id, minimum: 3) == nil)

        let stackedMiddle = rolled.balls.first { $0.id == middle.id }!
        rolled.take(at: top.center, time: 14, snow: &scene)
        rolled.roll(to: p(stackedMiddle.center.x + 4, stackedMiddle.center.y - stackedMiddle.radius - 3), time: 14.04, snow: &scene)
        precondition(rolled.release(at: 14.04) == top.id)
        let ready = rolled.takeStack(containing: top.id, minimum: 3, automatic: true)
        precondition(ready?.count == 3 && ready?.surface == sill.id && ready?.base.id == base.id && rolled.balls.isEmpty)
    }

    private static func snowPlayFixture(in region: CGRect) -> (DisplayScene, SnowSurface) {
        let ledge = SnowSurface(id: .window(67), rect: CGRect(x: 24, y: region.maxY - 150, width: region.width - 48, height: 90),
                                visible: [24...(region.maxX - 24)], floor: false)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let store = WindowSnowpack()
        var pack = SnowDrift(width: ledge.rect.width, floor: false, seed: 81)
        for x in stride(from: CGFloat(0), to: ledge.rect.width, by: 6) {
            pack.depositImpact(at: x, mass: 18, width: 15)
        }
        store[67] = pack
        var scene = DisplayScene(id: 19, windowSnow: store)
        scene.setSurfaces([ledge, floor])
        return (scene, ledge)
    }

    private static func checkFreeSnowPlay(in region: CGRect) {
        var (scene, ledge) = snowPlayFixture(in: region)
        let height = ledge.rect.minY - 8
        let initialMass = scene.drift(on: ledge.id)!.heights.reduce(0, +)
        var growing = RolledSnow()
        growing.take(at: p(45, height), time: 1, snow: &scene)
        for i in 1...48 { growing.roll(to: p(45 + CGFloat(i) * 14.5, height), time: 1 + Double(i) * 0.026, snow: &scene) }
        let firstPass = growing.balls[0].radius
        precondition(firstPass > 48, "A normal pass over a deep layer can make a ball substantially bigger than the old limit")
        growing.release(at: 2.6)
        for _ in 0..<60 { growing.advance(1.0 / 60, size: region.size, snow: &scene, reduced: false) }
        let big = growing.balls[0]
        growing.take(at: big.center, time: 4, snow: &scene, preferred: big.id)
        for i in 1...45 {
            growing.roll(to: p(big.center.x - CGFloat(i) * 14.5, big.center.y),
                         time: 4 + Double(i) * 0.035, snow: &scene)
        }
        let heavier = growing.balls[0]
        let remainingMass = scene.drift(on: ledge.id)!.heights.reduce(0, +)
        precondition(heavier.radius >= firstPass && abs(heavier.radius - RolledSnowball.maximumRadius) < 0.001)
        precondition(abs(initialMass - remainingMass - heavier.mass) < 0.001)
        growing.roll(to: p(168, big.center.y), time: 6, snow: &scene)
        precondition(scene.drift(on: ledge.id)!.heights.reduce(0, +) == remainingMass)

        (scene, ledge) = snowPlayFixture(in: region)
        var rolled = RolledSnow()
        let strips: [(CGFloat, CGFloat)] = [(48, 226), (333, 409), (478, 512), (602, 616), (688, 695)]
        for (index, strip) in strips.enumerated() {
            let time = Double(index) * 4
            rolled.take(at: p(strip.0, height), time: time, snow: &scene)
            rolled.roll(to: p(strip.1, height), time: time + 0.46, snow: &scene)
            rolled.release(at: time + 0.62)
            for _ in 0..<70 { rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: false) }
        }
        let ids = rolled.balls.map(\.id)
        precondition(ids.count == 5 && rolled.balls[0].radius > rolled.balls[1].radius * 1.3
                     && rolled.balls[1].radius > rolled.balls[2].radius)
        rolled.setFree(true, for: ids[0])

        func stack(_ index: Int, on parent: Int, offset: CGFloat) {
            let ball = rolled.ball(ids[index])!, lower = rolled.ball(ids[parent])!
            let height = (ball.radius + lower.radius) * 0.92
            let seat = p(lower.center.x + offset, lower.center.y - sqrt(height * height - offset * offset))
            let start = Double(20 + index * 3)
            rolled.take(at: ball.center, time: start, snow: &scene, preferred: ball.id)
            rolled.roll(to: p(ball.center.x, ball.center.y - 39), time: start + 0.13, snow: &scene)
            rolled.roll(to: seat, time: start + 0.36, snow: &scene)
            precondition(rolled.release(at: start + 0.50, within: region.size) == ball.id, "An offset ball seats on its support")
            precondition(rolled.ball(ball.id)?.rest == .ball(lower.id, offset: offset))
        }
        let baseRadius = rolled.balls[0].radius
        stack(1, on: 0, offset: -floor(baseRadius * 0.59))
        stack(2, on: 1, offset: 3)
        precondition(rolled.takeStack(containing: ids[2], minimum: 3, automatic: true) == nil)
        stack(3, on: 2, offset: 2)
        stack(4, on: 0, offset: floor(baseRadius * 0.63))
        let headBefore = rolled.ball(ids[2])!
        let bodyBefore = rolled.ball(ids[1])!
        for choice in [SnowballPropChoice.eyes, .carrot, .feltHat] { rolled.addProp(choice, to: ids[2], at: headBefore.center) }
        for choice in [SnowballPropChoice.leftTwig, .rightTwig, .scarf, .coal] {
            rolled.addProp(choice, to: ids[1], at: bodyBefore.center)
        }
        rolled.addProp(.woolHat, to: ids[2], at: headBefore.center)
        precondition(rolled.ball(ids[2])!.props.map(\.kind) == [.eye, .eye, .carrot, .woolHat])
        precondition(rolled.ball(ids[1])!.props.map(\.kind) == [.leftTwig, .rightTwig, .scarf, .coal])
        precondition(!rolled.canFinishStack(containing: ids[2]) && rolled.balls.allSatisfy(\.freeStack))
        let eye = rolled.ball(ids[2])!.props[0]
        let eyeAnchor = p(headBefore.center.x - 3, headBefore.center.y - 5)
        rolled.moveProp(eye.id, on: ids[2], to: eyeAnchor)
        let movedEye = rolled.ball(ids[2])!.props[0]
        precondition(hypot(movedEye.worldAnchor(on: headBefore).x - eyeAnchor.x,
                           movedEye.worldAnchor(on: headBefore).y - eyeAnchor.y) < 0.001)
        rolled.removeProp(eye.id, from: ids[2])
        precondition(rolled.ball(ids[2])!.props.contains { $0.kind == .eye })

        let pose = rolled.snowmanPose(containing: ids[2])!
        let suite = "local.snowglow.self-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = SnowModel(defaults: defaults)
        library.collectSnowman(pose)
        let stored = SnowModel(defaults: defaults).collectedSnowmen.first!
        precondition(stored.pose == pose && pose.parts.count == 5)
        let restoredBase = p(region.midX, 0)
        let rebuilt = stored.pose.balls(at: restoredBase)
        let originalBase = rolled.ball(ids[0])!.center
        for (part, ball) in zip([0, 1, 4, 2, 3], rebuilt) {
            let original = rolled.ball(ids[part])!
            precondition(abs((original.center.x - originalBase.x) - (ball.center.x - restoredBase.x)) < 0.001)
            precondition(abs((original.center.y - originalBase.y) - (ball.center.y - restoredBase.y)) < 0.001)
            precondition(original.id != ball.id && original.rotation == ball.rotation
                         && original.mass == ball.mass && original.textureSeed == ball.textureSeed)
            precondition(original.props.map(\.kind) == ball.props.map(\.kind))
            for (old, new) in zip(original.props, ball.props) {
                let oldPosition = old.worldAnchor(on: original)
                let newPosition = new.worldAnchor(on: ball)
                let dx = (oldPosition.x - original.center.x) - (newPosition.x - ball.center.x)
                let dy = (oldPosition.y - original.center.y) - (newPosition.y - ball.center.y)
                precondition(old.id != new.id && hypot(dx, dy) < 0.001)
            }
        }
        var rePlaced = RolledSnow()
        precondition(rePlaced.place(stored.pose, near: p(region.midX, region.maxY - 2), size: region.size, snow: scene))
        precondition(!rePlaced.place(stored.pose, near: p(region.midX, region.maxY - 2), size: region.size, snow: scene))
        precondition(rePlaced.balls.count == pose.parts.count && rePlaced.canToggleFree(for: rePlaced.balls[0].id) == false)

        let foot = rolled.ball(ids[0])!
        let originalTwigs = rolled.ball(ids[1])!.props
        rolled.take(at: foot.center, time: 42, snow: &scene, preferred: foot.id)
        rolled.roll(to: p(foot.center.x, foot.center.y - 65), time: 42.19, snow: &scene)
        precondition(abs(rolled.ball(ids[2])!.center.y - headBefore.center.y + 65) < 0.001)
        precondition(rolled.ball(ids[1])!.props.map(\.id) == originalTwigs.map(\.id))
        rolled.release(at: 42.4)

        var settings = SnowSettings()
        precondition(settings.automaticallyFinishSnowman)
        settings.automaticallyFinishSnowman = false
        precondition(!(try! JSONDecoder().decode(SnowSettings.self, from: JSONEncoder().encode(settings))).automaticallyFinishSnowman)
        if Bundle.main.bundleURL.pathExtension == "app" {
            precondition(RolledSnowArt.photosAvailable && SnowballPropArt.isAvailable)
            let dressed = rolled.ball(ids[2])!
            let carrot = dressed.props.first { $0.kind == .carrot }!
            precondition(SnowballPropArt.hit(at: carrot.worldAnchor(on: dressed), on: dressed)?.id == carrot.id)
            precondition(SnowballPropArt.bounds(of: dressed, including: CGRect(around: dressed.center, radius: dressed.radius))
                .minY < dressed.center.y - dressed.radius)
        }
        let floor = scene.surfaces.first(where: \.floor)!
        scene.setSurfaces([floor])
        for _ in 0..<120 { rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: false) }
        var pass = PlowPass(direction: 1)
        var pushedProps = false
        for _ in 0..<480 {
            let old = pass
            pass.advance(1.0 / 60, width: floor.rect.width)
            let contact = SnowplowContact(pass: pass, previous: old, floor: floor.rect)
            if rolled.contactPlow(contact) {
                pushedProps = rolled.plowed.contains { $0.ball.id == ids[1] && $0.ball.props.map(\.id) == originalTwigs.map(\.id) }
            }
            rolled.advancePlowed(1.0 / 60, contact: contact, floor: floor.rect, reduced: false)
        }
        precondition(pushedProps && rolled.isEmpty)
        precondition(SnowModel(defaults: defaults).collectedSnowmen.first?.pose == pose)
    }

    private static func checkSnowballThrows(in region: CGRect) {
        func throwBall(from start: CGPoint, to end: CGPoint, in interval: Double, delay: Double = 0,
                       reduced: Bool = false) -> (velocity: CGVector, broke: Bool, deposited: CGFloat) {
            var (scene, ledge) = snowPlayFixture(in: region)
            var rolled = RolledSnow()
            let snow = ledge.rect.minY - 7
            rolled.take(at: p(360, snow), time: 0, snow: &scene)
            rolled.roll(to: p(428, snow), time: 0.4, snow: &scene)
            rolled.release(at: 0.62)
            for _ in 0..<80 { rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: reduced) }
            let center = rolled.balls[0].center
            rolled.take(at: center, time: 3, snow: &scene)
            rolled.roll(to: p(center.x, center.y - 55), time: 3.22, snow: &scene, within: region.size, reduced: reduced)
            rolled.roll(to: start, time: 4, snow: &scene, within: region.size, reduced: reduced)
            rolled.roll(to: end, time: 4 + interval, snow: &scene, within: region.size, reduced: reduced)
            rolled.release(at: 4 + interval + delay, within: region.size)
            let thrown = rolled.balls[0]
            var fragments: CGFloat = 0
            for _ in 0..<180 {
                rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: reduced)
                if rolled.balls.isEmpty && fragments == 0 {
                    fragments = scene.looseSnow.reduce(0) { $0 + $1.mass }
                }
                scene.stepFallingSnow(delta: 1.0 / 60, reduced: reduced)
            }
            let deposited = scene.drift(on: .floor)?.heights.reduce(0, +) ?? 0
            if fragments > 0 {
                precondition(abs(fragments - thrown.mass) < 0.001, "The impact redistributes all rolled snow into physical pieces")
                precondition(abs(deposited - fragments) < 0.001 && scene.looseSnow.isEmpty, "Fragments settle all the way to the floor while snowfall is paused")
            }
            precondition(scene.flakes.isEmpty)
            return (thrown.velocity, rolled.balls.isEmpty && fragments > 0, deposited)
        }
        let slow = throwBall(from: p(520, 135), to: p(583, 134), in: 0.35)
        let fast = throwBall(from: p(520, 135), to: p(583, 134), in: 0.033)
        let stopped = throwBall(from: p(520, 135), to: p(583, 134), in: 0.033, delay: 0.22)
        precondition(fast.velocity.dx > slow.velocity.dx * 5 && !slow.broke && fast.broke && fast.deposited > 5)
        precondition(stopped.velocity == .zero && !stopped.broke)
        precondition(throwBall(from: p(250, 145), to: p(174, 142), in: 0.034, reduced: true).broke)
        precondition(throwBall(from: p(310, 105), to: p(309, 53), in: 0.032).broke)
        precondition(throwBall(from: p(782, 479), to: p(782, 541), in: 0.035).broke)
    }

    private static func checkSnowballLedgeFalls(in region: CGRect) {
        let floor = SnowSurface(id: .floor,
                                rect: CGRect(x: region.minX, y: region.maxY, width: region.width, height: 1),
                                visible: [region.minX...region.maxX], floor: true)

        func ledge(_ id: UInt32, at y: CGFloat, from left: CGFloat, to right: CGFloat,
                   behind higher: [SnowSurface] = []) -> SnowSurface {
            let frame = CGRect(x: left, y: y, width: right - left, height: 210)
            let cover = higher.map(\.rect)
            return SnowSurface(id: .window(id), rect: frame, visible: exposedEdge(frame, inside: region, blockedBy: cover),
                               floor: false, occluders: cover, cornerRadius: 18)
        }

        func fixture(_ windows: [SnowSurface]) -> DisplayScene {
            let pack = WindowSnowpack()
            let upper = windows[0]
            if case let .window(id) = upper.id {
                var source = SnowDrift(width: upper.rect.width, floor: false, seed: 81)
                for x in stride(from: CGFloat(7), to: source.width, by: 6) {
                    source.depositImpact(at: x, mass: 20, width: 14)
                }
                pack[id] = source
            }
            var scene = DisplayScene(id: 83, windowSnow: pack)
            scene.setSurfaces(windows + [floor])
            return scene
        }

        let high = ledge(81, at: 118, from: 100, to: 290)
        let middle = ledge(82, at: 247, from: 230, to: 557, behind: [high])
        let low = ledge(83, at: 377, from: 470, to: 751, behind: [high, middle])
        var scene = fixture([high, middle, low])
        precondition(middle.visible == [290...557] && low.visible == [557...751])
        let swept = scene.sweptLanding(from: p(535, 245), to: p(580, 250), excluding: high.id)
        precondition(swept?.surface.id == middle.id && abs((swept?.point.x ?? 0) - 553) < 0.01,
                     "The lower ledge is hit at the instant of crossing even when the next sample has already passed the edge")
        precondition(scene.sweptLanding(from: p(267, 243), to: p(287, 255), excluding: high.id) == nil,
                     "A covered section of the lower window cannot catch the ball")
        precondition(scene.sweptLanding(from: p(271, 249), to: p(332, 256), excluding: high.id) == nil,
                     "Moving into a ledge from below does not put the ball on top")
        let lipStart = p(565, 243), lipEnd = p(569, 260)
        precondition(scene.sweptLanding(from: lipStart, to: lipEnd, excluding: high.id) == nil)
        let corner = scene.sweptLanding(from: lipStart, to: lipEnd, radius: 28, excluding: high.id)
        precondition(corner?.surface.id == middle.id && corner?.onCorner == true && corner?.point.x == 555,
                     "The underside of a ball can land on an exposed lip even when its centre never crosses the top")
        precondition(scene.sweptLanding(from: p(576, 246), to: p(581, 265), radius: 28, excluding: high.id) == nil,
                     "The far side of a ball does not stick to a wall")
        precondition(scene.sweptLanding(from: p(564, 278), to: p(552, 292), radius: 28, excluding: high.id) == nil,
                     "The underside of a window does not catch a passing ball")

        var rolled = RolledSnow()
        rolled.take(at: p(200, 109), time: 1, snow: &scene)
        rolled.roll(to: p(246, 109), time: 1.18, snow: &scene, within: region.size)
        rolled.roll(to: p(270, 109), time: 1.30, snow: &scene, within: region.size)
        precondition(rolled.held != nil && rolled.balls.first?.rest != nil)
        rolled.roll(to: p(299, 109), time: 1.337, snow: &scene, within: region.size)
        let departure = rolled.balls[0]
        precondition(rolled.held == nil && departure.rest == nil && departure.velocity.dx > 50)
        precondition(abs(departure.center.x - 290) < 0.01 && abs(departure.ledgeTravel!.originY - 118) < 0.01)
        rolled.roll(to: p(720, 198), time: 1.41, snow: &scene, within: region.size)
        precondition(rolled.balls[0].center == departure.center, "The ball has already slipped away while the mouse is still pressed")

        var caught: [CGFloat] = []
        for _ in 0..<300 {
            rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: false)
            if let height = rolled.balls.first?.ledgeTravel?.originY, caught.last != height { caught.append(height) }
        }
        precondition(caught == [118, 247, 377, 600], "The same ball must hit each exposed step in order and survive across several shorter falls, got \(caught)")
        precondition(rolled.balls[0].id == departure.id && rolled.balls[0].rest != nil
                     && rolled.balls[0].mass == departure.mass && scene.looseSnow.isEmpty && scene.drift(on: .floor) == nil)

        func drop(from top: CGFloat, catchAt lower: CGFloat? = nil, reduced: Bool = false,
                  afterRelease: Bool = false) -> (broke: Bool, support: SurfaceID?) {
            let upper = ledge(85, at: top, from: 200, to: 375)
            let catcher = lower.map { ledge(86, at: $0, from: 350, to: 746, behind: [upper]) }
            var scene = fixture([upper] + (catcher.map { [$0] } ?? []))
            var rolled = RolledSnow()
            let pathY = top - 8
            rolled.take(at: p(246, pathY), time: 1, snow: &scene)
            rolled.roll(to: p(351, pathY), time: 1.38, snow: &scene, within: region.size, reduced: reduced)
            if afterRelease {
                rolled.release(at: 1.38, within: region.size)
                precondition(rolled.balls[0].rest != nil && rolled.balls[0].ledgeTravel == nil)
            } else {
                rolled.roll(to: p(391, pathY), time: 1.55, snow: &scene, within: region.size, reduced: reduced)
                precondition(rolled.held == nil && rolled.balls[0].ledgeTravel != nil)
            }
            let original = rolled.balls[0]
            var broke = false
            for _ in 0..<300 {
                rolled.advance(1.0 / 60, size: region.size, snow: &scene, reduced: reduced)
                if rolled.balls.isEmpty && !broke {
                    broke = true
                    precondition(!scene.looseSnow.isEmpty && scene.looseSnow.allSatisfy { $0.position.y > region.maxY - 30 })
                    precondition(abs(scene.looseSnow.reduce(0) { $0 + $1.mass } - original.mass) < 0.001)
                }
                scene.stepFallingSnow(delta: 1.0 / 60, reduced: reduced)
            }
            precondition(scene.flakes.isEmpty && scene.looseSnow.isEmpty)
            if broke {
                precondition(abs(scene.drift(on: .floor)!.heights.reduce(0, +) - original.mass) < 0.001,
                             "Every fragment settles into the ground pile while regular snowfall is paused")
            } else {
                precondition(rolled.balls[0].id == original.id && scene.drift(on: .floor) == nil)
            }
            if case let .surface(id, _) = rolled.balls.first?.rest { return (broke, id) }
            return (broke, nil)
        }

        let half = region.maxY - region.height / 2
        precondition(drop(from: half + 1).support == .floor)
        precondition(drop(from: half).support == .floor, "Exactly half of the screen is a safe fall")
        precondition(drop(from: half - 1, reduced: true).broke, "Only a fall strictly over half the screen shatters on the ground")
        precondition(drop(from: 146, afterRelease: true).broke, "A ball rolled off a ledge by momentum after mouse-up has the same ground impact")
        precondition(drop(from: 70, catchAt: 446).support == .window(86), "Even a long fall stays intact when caught by a lower window")

        let upper = ledge(87, at: 126, from: 180, to: 365)
        var narrowScene = fixture([upper])
        var flick = RolledSnow()
        flick.take(at: p(215, 118), time: 1, snow: &narrowScene)
        flick.roll(to: p(350, 118), time: 1.44, snow: &narrowScene, within: region.size)
        flick.roll(to: p(417, 117), time: 1.47, snow: &narrowScene, within: region.size)
        let thrown = flick.balls[0]
        precondition(flick.held == nil && thrown.velocity.dx <= 580 && thrown.velocity.dx > 0)
        let catchY: CGFloat = 281
        var originalTrajectory = flick
        var traceScene = narrowScene
        while originalTrajectory.balls[0].center.y + thrown.radius < catchY {
            originalTrajectory.advance(1.0 / 240, size: region.size, snow: &traceScene, reduced: false)
        }
        let firstReach = originalTrajectory.balls[0].center.x
        let exposedLip = ledge(88, at: catchY, from: firstReach + thrown.radius * 0.24, to: 780, behind: [upper])
        narrowScene.setSurfaces([upper, exposedLip, floor])
        var contacted = false
        for _ in 0..<170 {
            flick.advance(1.0 / 60, size: region.size, snow: &narrowScene, reduced: false)
            if let startY = flick.balls.first?.ledgeTravel?.originY, abs(startY - catchY) < 0.01 { contacted = true }
        }
        precondition(contacted && flick.balls.first?.id == thrown.id,
                     "A fast push can still be caught by a low window when the ball clips the exposed lip")
    }

    private static func checkFestiveEffects(in region: CGRect) {
        let second = region.offsetBy(dx: region.width, dy: 0)
        precondition(DesktopWeatherPower.fullscreen(region, on: region))
        precondition(!DesktopWeatherPower.fullscreen(region.insetBy(dx: 0, dy: 24), on: region))
        precondition(!DesktopWeatherPower.fullscreen(region, on: second))
        let gust = SnowGust(time: 3, width: region.width, amount: 1, seed: 0)
        precondition(gust.push(at: region.midX) > 100 && gust.push(at: 0) == 0)
        precondition(SnowGust(time: 8, width: region.width, amount: 1, seed: 0).strength == 0)

        var normal = DisplayScene(id: 18), saved = DisplayScene(id: 18)
        let settings = SnowSettings()
        normal.step(size: region.size, delta: 0, time: 0, settings: settings, reduced: false)
        saved.step(size: region.size, delta: 0, time: 0, settings: settings, reduced: false, lowPower: true)
        precondition(saved.flakes.count < normal.flakes.count && saved.flakes.count > normal.flakes.count / 2)
        precondition(normal.flakes.contains { $0.crystal < settings.crystalMix })

        let hooks = [p(0.12, 0.17), p(0.50, 0.17), p(0.81, 0.33)]
        let strand = LightStrand(hooks: hooks, slack: 1.2)
        let anchors = strand.anchors(in: region.size)
        let points = LightStrand.points(anchors, slack: strand.slack, at: 0, wind: 0, spacing: 12)
        precondition(points.first == anchors.first && points.last == anchors.last && points.contains(anchors[1]))
        precondition(points[points.count / 4].y > anchors[0].y && anchors.allSatisfy(strand.bounds(in: region.size, bulbScale: 1).contains))
        var decoration = Ornament(kind: .lights, display: 1, x: 0.5, y: 0.5)
        decoration.lightStrand = strand
        precondition((try! JSONDecoder().decode(Ornament.self, from: JSONEncoder().encode(decoration))).lightStrand == strand)

        var tree = Ornament(kind: .tree, display: 1, x: 0.5, y: 0.5)
        let treeFrame = CGRect(x: 120, y: 115, width: 160, height: 190)
        let treeHost = LightStrand.Host(ornament: tree, frame: treeFrame)
        let customPoints = [p(180, 185), p(242, 228), p(400, 297)]
        let attachments = LightStrand.attachments(for: customPoints, on: [treeHost])
        precondition(attachments.keys.sorted() == [0, 1])
        var mounted = strand
        mounted.attachments = attachments
        let decoded = try! JSONDecoder().decode(LightStrand.self, from: JSONEncoder().encode(mounted))
        precondition(decoded == mounted)
        let movedFrame = treeFrame.offsetBy(dx: 786, dy: -42)
        let moved = LightStrand.Host(ornament: tree, frame: movedFrame)
        let resolved = decoded.resolvedAnchors(free: customPoints, hosts: [tree.id: moved])!
        precondition(resolved[0] == p(966, 143) && resolved[1] == p(1028, 186) && resolved[2] == customPoints[2])
        tree.rotation = 32
        let rotated = LightStrand.Host(ornament: tree, frame: movedFrame.insetBy(dx: -25, dy: -29))
        let rotatedPoint = rotated.point(for: attachments[0]!)
        let restoredAttachment = rotated.attachment(at: rotatedPoint)!
        precondition(hypot(restoredAttachment.position.x - attachments[0]!.position.x,
                           restoredAttachment.position.y - attachments[0]!.position.y) < 0.0001)
        precondition(decoded.resolvedAnchors(free: customPoints, hosts: [:]) == nil)

        let sill = SnowSurface(id: .window(41), rect: CGRect(x: 100, y: 180, width: 440, height: 210),
                               visible: [100...540], floor: false, cornerRadius: 18)
        let floor = SnowSurface(id: .floor, rect: CGRect(x: 0, y: region.maxY, width: region.width, height: 1),
                                visible: [0...region.width], floor: true)
        let shared = WindowSnowpack()
        var pack = SnowDrift(width: sill.rect.width, floor: false, seed: 66)
        for x in stride(from: 24, to: 220, by: 16) { pack.depositImpact(at: CGFloat(x), mass: 22, width: 17) }
        shared[41] = pack
        var scene = DisplayScene(id: 91, windowSnow: shared)
        scene.setSurfaces([sill, floor])
        var rolled = RolledSnow()
        rolled.take(at: p(133, 174), time: 0, snow: &scene)
        rolled.roll(to: p(230, 174), time: 0.15, snow: &scene)
        let ball = rolled.balls[0]
        precondition(ball.mass > 4 && abs(pack.heights.reduce(0, +) - shared[41]!.heights.reduce(0, +) - ball.mass) < 0.001)
        rolled.release(at: 0.15)
        rolled.advance(0.015, size: region.size, snow: &scene, reduced: false)
        precondition(rolled.balls[0].center.x > ball.center.x && rolled.held == nil)

        var branch = TreeBranchSnow()
        branch.step(15, density: 0.8)
        let before = branch.loads.reduce(0, +)
        let fallen = branch.shake(at: p(140, 300), in: CGRect(x: 130, y: 240, width: 150, height: 180))
        precondition(!fallen.isEmpty && branch.loads.reduce(0, +) < before && branch.animating)
        for (point, mass) in fallen { scene.shedBranchSnow(at: point, load: mass) }
        precondition(!scene.released.isEmpty)

        var parade = FestiveTraffic()
        parade.launch()
        for _ in 0..<660 { parade.step(1.0 / 60, size: region.size, snow: scene, automatic: false, reduced: false) }
        precondition(parade.flight == nil && parade.gifts.count == 3 && parade.gifts.allSatisfy { $0.rest != nil })
        let gift = parade.gifts[0].id
        parade.open(gift)
        for _ in 0..<120 { parade.step(1.0 / 60, size: region.size, snow: scene, automatic: false, reduced: false) }
        precondition(!parade.gifts.contains { $0.id == gift } && parade.gifts.count == 2)
        checkReindeerStride()
    }

    private static func checkReindeerStride() {
        let interval = ReindeerPose.cycle / 120
        let sequence = (0...120).map { ReindeerPose(age: CGFloat($0) * interval, offset: 0.0, reduced: false) }
        var aired = false
        for (first, next) in zip(sequence, sequence.dropFirst()) {
            let supporting = next.legs.filter(\.planted).count
            precondition(next.legs.count == 4 && supporting <= 2)
            aired = aired || supporting == 0
            for (before, after) in zip(first.legs, next.legs) {
                precondition(hypot(before.ankle.x - after.ankle.x, before.ankle.y - after.ankle.y) < 17)
                precondition(abs(before.hoofAngle - after.hoofAngle) < 0.18)
                if let stifle = after.stifle {
                    precondition(abs(hypot(stifle.x - after.root.x, stifle.y - after.root.y) - 146) < 0.01)
                }
            }
        }
        precondition(aired, "The stride alternates stance, push-off, and suspension")
        let parked = ReindeerPose(age: 0, offset: 0.0, reduced: true)
        let stationary = ReindeerPose(age: 2.4, offset: 0.34, reduced: true)
        precondition(parked.body == stationary.body && parked.legs.map(\.ankle) == stationary.legs.map(\.ankle))
        let screen = CGSize(width: 640, height: 540)
        let forward = SleighFlight(direction: 1, age: 4.5)
        let reverse = SleighFlight(direction: -1, age: 4.5)
        precondition(abs(forward.giftAnchor(in: screen).x + reverse.giftAnchor(in: screen).x - screen.width) < 0.001)
        if Bundle.main.bundleURL.pathExtension == "app" { precondition(SleighFlightArt.spritesAvailable) }
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

    private static func checkSnowmanWardrobeFrame() {
        let preferred = CGSize(width: 344, height: 452)
        let display = CGRect(x: -640, y: 982, width: 640, height: 700)
        let bottomRight = CGRect(x: -100, y: 988, width: 86, height: 100)
        let placed = SnowmanWardrobe.windowFrame(preferredSize: preferred, beside: bottomRight,
                                                currentFrame: .zero, in: display)
        precondition(placed.size == preferred && placed.minY == display.minY + 9)
        precondition(placed.maxX == bottomRight.minX - 13 && display.contains(placed))

        let compactDisplay = CGRect(x: 0, y: -300, width: 320, height: 300)
        let fitted = SnowmanWardrobe.windowFrame(preferredSize: preferred, beside: nil,
                                                currentFrame: placed, in: compactDisplay)
        precondition(fitted == compactDisplay.insetBy(dx: 9, dy: 9))
    }

    private static func checkWreathRemoval() {
        let tree = Ornament(kind: .tree, display: 2, x: 0.2, y: 0.5)
        let wreath = Ornament(kind: .wreath, display: 2, x: 0.8, y: 0.5)
        var legacy = SnowSettings()
        legacy.ornaments = [wreath, tree]
        let scene = SavedScene(name: "Legacy decorations", settings: legacy)
        let oldData = try! JSONEncoder().encode(SnowStorage(settings: legacy, scenes: [scene]))
        var decoded = try! JSONDecoder().decode(SnowStorage.self, from: oldData)
        decoded.removeWreaths()
        precondition(OrnamentKind.allCases.contains(.tree) && !OrnamentKind.allCases.contains(.wreath))
        precondition(decoded.settings.ornaments == [tree] && decoded.scenes.first?.settings.ornaments == [tree])

        let model = SnowModel(defaults: nil)
        model.restoreScene(scene)
        model.add(wreath)
        precondition(model.settings.ornaments == [tree] && model.selectedOrnament == tree.id)
    }

    private static func checkSnowmanGroundAndPlow() {
        let display = CGRect(x: 200, y: -80, width: 800, height: 700)
        let dock = CGRect(x: 355, y: -72, width: 390, height: 62)
        precondition(SnowmanGround.foot(at: 480, screen: display, dock: nil) == -79)
        precondition(SnowmanGround.foot(at: 480, screen: display, dock: dock) == -9)
        precondition(SnowmanGround.foot(at: 310, screen: display, dock: dock) == -79)

        var snowman = Ornament(kind: .snowman, display: 1, x: 0.77, y: 0.29)
        let oldSave = try! JSONEncoder().encode(snowman)
        snowman = try! JSONDecoder().decode(Ornament.self, from: oldSave)
        precondition(SnowmanGround.followsSupport(snowman, usableHeight: 680))
        snowman.snowmanFollowsGround = false
        let dragged = try! JSONEncoder().encode(snowman)
        snowman = try! JSONDecoder().decode(Ornament.self, from: dragged)
        precondition(!SnowmanGround.followsSupport(snowman, usableHeight: 680))
        let size = OrnamentKind.snowman.size
        let bottom = SnowmanGround.frame(center: p(display.minX, display.minY), size: size, inside: display)
        precondition(bottom.minX == display.minX && bottom.maxY - SnowmanArt.baseline == display.minY)

        snowman.hat = .santa
        snowman.costume.scarf = .red
        snowman.costume.arms = true
        let floor = CGRect(x: 0, y: 700, width: 800, height: 1)
        for (count, direction) in [(2, CGFloat(-1)), (3, CGFloat(1))] {
            snowman.snowballs = count
            var pass = PlowPass(direction: direction)
            pass.advance(1.8, width: floor.width)
            let first = SnowplowContact(pass: pass, previous: nil, floor: floor)
            let pose = CGRect(x: first.blade + 17 * direction - size.width / 2,
                              y: floor.minY - SnowmanArt.baseline, width: size.width, height: size.height)
            let parts = SnowmanArt.parts(for: snowman, in: pose)
            precondition(parts.count == count && parts.last?.tone == 2)
            precondition(first.hits(parts[0]))
            let high = SnowmanArt.parts(for: snowman, in: pose.offsetBy(dx: 0, dy: -70))
            precondition(!high.contains(where: first.hits))
            var next = pass
            next.advance(0.5, width: floor.width)
            precondition(!SnowplowContact(pass: next, previous: nil, floor: floor).hits(parts[0]))
            precondition(SnowplowContact(pass: next, previous: pass, floor: floor).hits(parts[0]))

            var knocked = SnowmanWorkshop(knocking: snowman, from: pose, direction: direction, reduced: false)
            let head = knocked.balls[count - 1]
            knocked.grab(head.id, at: head.center)
            let moved = p(head.center.x + 20, head.center.y + 90)
            knocked.drag(to: moved, platforms: [])
            precondition(knocked.balls[head.id].center == moved && knocked.tone(for: head) == 2)

            var wreck = PlowedSnowman(ornament: snowman, parts: parts, contact: first)
            let delta: CGFloat = 1.0 / 60
            var visible = true
            for _ in 0..<300 where visible {
                let previous = pass
                pass.advance(delta, width: floor.width)
                let contact = SnowplowContact(pass: pass, previous: previous, floor: floor)
                visible = wreck.advance(delta, contact: contact, floor: floor, reduced: false)
            }
            precondition(!visible && wreck.ornament == snowman)
            precondition(wreck.parts.allSatisfy { direction * ($0.center.x - first.blade) > 350 && $0.angle != 0 })
        }
    }

    private static func checkDecorationPlacement() {
        let display = CGRect(x: -900, y: 982, width: 900, height: 640)
        let usable = display.insetBy(dx: 12, dy: 58)
        let floor = CGRect(x: 0, y: display.height, width: display.width, height: 1)
        var pass = PlowPass(direction: 1)
        pass.advance((floor.midX + PlowPass.approach - SnowplowArt.bladeNoseOffset) / pass.speed(width: floor.width), width: floor.width)
        let contact = SnowplowContact(pass: pass, previous: nil, floor: floor)
        for kind in OrnamentKind.allCases {
            var item = Ornament(kind: kind, display: 1, x: 0.5, y: 0.04)
            item.scale = 1.6
            if kind == .gift { item.rotation = 28 }
            precondition(!item.usesFreePlacement && usable.contains(item.desktopFrame(in: display, usable: usable)))
            item.anchor = WindowAnchor(id: 19, owner: "Test", pid: 19, x: 100, y: 100)
            let preview = item.desktopFrame(center: p(display.midX, display.minY), inside: display, free: true)
            item.placeOnDesktop(at: p(preview.midX, preview.midY), displayID: 9, display: display)
            let reloaded = try! JSONDecoder().decode(Ornament.self, from: JSONEncoder().encode(item))
            let settled = reloaded.desktopFrame(in: display, usable: usable)
            precondition(reloaded.anchor == nil && reloaded.display == 9 && reloaded.usesFreePlacement)
            precondition(abs(settled.minX - preview.minX) < 0.001 && abs(settled.minY - preview.minY) < 0.001)

            let frame = CGRect(x: settled.minX - display.minX, y: display.maxY - settled.maxY,
                               width: settled.width, height: settled.height)
            if kind != .snowman {
                let body = item.interactionFrame(in: frame)
                precondition(contact.hits(body) && !contact.hits(body.offsetBy(dx: 0, dy: -64)))
                var wreck = PlowedDecoration(ornament: item, frame: frame, contact: contact)
                precondition(wreck.advance(0.2, floor: floor, reduced: false))
                precondition(wreck.frame.midX > frame.midX && wreck.ornament.rotation > item.rotation)
                precondition(!wreck.advance(0.75, floor: floor, reduced: false))
            }
        }

        var lights = Ornament(kind: .lights, display: 9, x: 0.5, y: 0.5)
        let window = CGRect(x: 240, y: 120, width: 420, height: floor.minY - 120)
        let windowCenter = p(window.midX, window.midY)
        let topLights = DecorationArt.windowLightHitRegions(lights, in: window)
        precondition(topLights.contains { $0.contains(p(window.midX, window.minY + 22)) })
        precondition(!topLights.contains { $0.contains(windowCenter) } && !topLights.contains(where: contact.hits))
        lights.placement = .windowFrame
        let frameLights = DecorationArt.windowLightHitRegions(lights, in: window)
        precondition(!frameLights.contains { $0.contains(windowCenter) } && frameLights.contains(where: contact.hits))
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
