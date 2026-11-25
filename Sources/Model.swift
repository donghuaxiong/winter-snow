import AppKit
import SwiftUI

enum SnowLayer: String, Codable, CaseIterable, Identifiable {
    case behindWindows, behindFrontWindow, inFront
    var id: Self { self }

    var title: String {
        switch self {
        case .behindWindows: "所有窗口后方"
        case .behindFrontWindow: "当前窗口后方"
        case .inFront: "所有窗口前方"
        }
    }
}

enum OrnamentKind: String, Codable, CaseIterable, Identifiable {
    case snowman, tree, lights, lantern, gift, calendar
    case wreath // Kept for decoding older scenes.

    static let allCases: [Self] = [.snowman, .tree, .lights, .lantern, .gift, .calendar]
    var id: Self { self }

    var title: String {
        switch self {
        case .snowman: "雪人"
        case .tree: "圣诞树"
        case .lights: "窗边彩灯"
        case .lantern: "提灯"
        case .gift: "礼物"
        case .wreath: "花环"
        case .calendar: "倒数日历"
        }
    }

    var size: CGSize {
        switch self {
        case .snowman: CGSize(width: 124, height: 160)
        case .tree: CGSize(width: 154, height: 185)
        case .lights: CGSize(width: 260, height: 54)
        case .lantern: CGSize(width: 80, height: 100)
        case .gift: CGSize(width: 84, height: 82)
        case .wreath: CGSize(width: 102, height: 105)
        case .calendar: CGSize(width: 272, height: 225)
        }
    }
}

enum FestivePalette: Int, Codable, CaseIterable, Identifiable {
    case winter, classic, gold, aurora, candy, custom
    var id: Self { self }

    var title: String {
        switch self {
        case .winter: "冰蓝"
        case .classic: "经典"
        case .gold: "暖金"
        case .aurora: "极光"
        case .candy: "红白"
        case .custom: "自定义"
        }
    }

    var colors: [UInt32] {
        switch self {
        case .winter: [0x73e9ff, 0xc6efff, 0x8eafff, 0xf0fffa]
        case .classic: [0xff757e, 0xffce79, 0x72edab, 0xa0b4ff]
        case .gold: [0xffd58f, 0xffe7b1, 0xffaf6e]
        case .aurora: [0x86edd5, 0xb9a4ff, 0x74cdfb, 0xf6a0d1]
        case .candy: [0xff5a72, 0xfff1ed]
        case .custom: [0xffc26e]
        }
    }
}

enum Bulb: String, Codable, CaseIterable, Identifiable {
    case globe, mini, fairy, retro, icicle
    var id: Self { self }

    var title: String {
        switch self {
        case .globe: "圆灯"
        case .mini: "迷你灯"
        case .fairy: "星星灯"
        case .retro: "复古大灯"
        case .icicle: "冰柱灯"
        }
    }
}

enum LightMotion: String, Codable, CaseIterable, Identifiable {
    case steady, twinkle, chase
    var id: Self { self }
    var title: String {
        switch self {
        case .steady: "常亮"
        case .twinkle: "闪烁"
        case .chase: "追逐"
        }
    }
}

enum Placement: String, Codable, CaseIterable, Identifiable {
    case windowTop, windowFrame
    var id: Self { self }
    var title: String { self == .windowTop ? "窗口上沿" : "围绕窗口" }
}

enum Hat: String, Codable, CaseIterable, Identifiable {
    case top, knit, crown, cowboy, party, earmuffs, viking, santa, elf, antlers, headphones, pirate, none
    var id: Self { self }
    var title: String {
        switch self {
        case .top: "礼帽"
        case .knit: "毛球帽"
        case .crown: "皇冠"
        case .cowboy: "牛仔帽"
        case .party: "派对帽"
        case .earmuffs: "耳罩"
        case .viking: "维京头盔"
        case .santa: "圣诞帽"
        case .elf: "精灵帽"
        case .antlers: "鹿角"
        case .headphones: "耳机"
        case .pirate: "海盗帽"
        case .none: "无"
        }
    }
}

enum SnowmanFace: String, Codable, CaseIterable, Identifiable {
    case smile, happy, sleepy, plain
    var id: Self { self }

    var title: String {
        switch self {
        case .smile: "胡萝卜笑脸"
        case .happy: "眯眼笑"
        case .sleepy: "打瞌睡"
        case .plain: "留白"
        }
    }
}

enum SnowmanScarf: String, Codable, CaseIterable, Identifiable {
    case red, blue, green, plaid, palette, none
    var id: Self { self }

    var title: String {
        switch self {
        case .red: "暖红"
        case .blue: "霜蓝"
        case .green: "松绿"
        case .plaid: "格纹"
        case .palette: "跟随配色"
        case .none: "无"
        }
    }
}

struct SnowmanCostume: Codable, Equatable {
    var face: SnowmanFace = .smile
    var scarf: SnowmanScarf = .red
    var arms = true
    var buttons = true
}

struct WindowAnchor: Codable, Equatable {
    var id: UInt32
    var owner: String
    var pid: Int32
    var x: Double
    var y: Double
}

struct Ornament: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: OrnamentKind
    var display: UInt32
    var x: Double
    var y: Double
    var scale = 1.0
    var rotation = 0.0
    var palette: FestivePalette = .classic
    var customColor: UInt32 = 0xffbd71
    var bulb: Bulb = .globe
    var lightMotion: LightMotion = .steady
    var placement: Placement = .windowTop
    var anchor: WindowAnchor?
    var hat: Hat = .top
    var snowballs = 3
    var snowmanFollowsGround: Bool?
    var usesDisplayCoordinates: Bool?
    var extras = true
    private var snowmanCostume: SnowmanCostume?
    var calendarStart = Date()
    var opened: Set<Int> = []

    init(kind: OrnamentKind, display: UInt32, x: Double, y: Double, calendarStart: Date = Date()) {
        self.kind = kind
        self.display = display
        self.x = x
        self.y = y
        self.calendarStart = calendarStart
    }

    var colors: [UInt32] { palette == .custom ? [customColor] : palette.colors }

    var costume: SnowmanCostume {
        get { snowmanCostume ?? SnowmanCostume(scarf: extras ? .palette : .none, arms: extras) }
        set { snowmanCostume = newValue }
    }

    func availableDoors(on date: Date, using calendar: Calendar = .current) -> Int {
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: calendarStart),
                                              to: calendar.startOfDay(for: date)).day ?? 0
        let december = calendar.component(.month, from: date) == 12 ? calendar.component(.day, from: date) : 0
        return min(25, max(elapsed + 1, december, 0))
    }
}

struct SnowSettings: Codable, Equatable {
    var enabled = true
    var intensity = 0.45
    var speed = 0.55
    var wind = 0.12
    var accumulate = true
    var icicles = true
    private var automaticPlowingOverride: Bool?
    private var plowDestroysDecorationsOverride: Bool?
    var layer: SnowLayer = .behindWindows
    var idleSeconds = 0
    var onlyWhenIdle = false
    var idleDim = true
    var ornaments: [Ornament] = []
    var ornamentsVisible = true
    var wallpaper: Int?

    var automaticPlowing: Bool {
        get { automaticPlowingOverride ?? true }
        set { automaticPlowingOverride = newValue ? nil : false }
    }

    var plowDestroysDecorations: Bool {
        get { plowDestroysDecorationsOverride ?? false }
        set { plowDestroysDecorationsOverride = newValue ? true : nil }
    }

    mutating func removeWreaths() {
        ornaments.removeAll { $0.kind == .wreath }
    }
}

struct SavedScene: Codable, Identifiable {
    var id = UUID()
    var name: String
    var settings: SnowSettings
}

struct OriginalWallpaper: Codable {
    var url: URL
    var scaling: Int?
    var clipping: Bool?
}

struct SnowStorage: Codable {
    var settings = SnowSettings()
    var scenes: [SavedScene] = []
    var originals: [UInt32: OriginalWallpaper] = [:]
    var welcomeSeen = false

    mutating func removeWreaths() {
        settings.removeWreaths()
        for index in scenes.indices { scenes[index].settings.removeWreaths() }
    }

    mutating func migrateRetiredWallpapers() {
        if Wallpaper.isRetired(settings.wallpaper) {
            settings.wallpaper = nil
        }
        for index in scenes.indices where Wallpaper.isRetired(scenes[index].settings.wallpaper) {
            scenes[index].settings.wallpaper = Wallpaper.cabin.id
        }
    }
}

@MainActor
final class SnowModel: ObservableObject {
    @Published var settings: SnowSettings { didSet { scheduleSave() } }
    @Published var scenes: [SavedScene] { didSet { scheduleSave() } }
    @Published var editMode = false
    @Published var preview = false
    @Published var idleActive = false
    @Published private(set) var pickingWindow = false
    @Published var buildingSnowman = false
    @Published var feedback: String?
    @Published var selectedOrnament: UUID?
    @Published var lockSnowActive = false
    @Published var lockSnowChanging = false

    var originals: [UInt32: OriginalWallpaper]
    var welcomeSeen: Bool
    var showStudio: (() -> Void)?
    var hideStudio: (() -> Void)?
    var clearSnow: (() -> Void)?
    var runPlow: (() -> Void)?
    var startPreview: (() -> Void)?
    var toggleLockSnow: (() -> Void)?
    var startPicking: (() -> Void)?
    var startSnowman: (() -> Void)?
    var cancelSnowman: (() -> Void)?
    var assembleSnowman: (() -> Void)?
    var showWardrobe: ((UUID, CGRect?) -> Void)?
    var wallpaperService: WallpaperService?
    private let defaults: UserDefaults?
    private var saveTask: Task<Void, Never>?

    var running: Bool { preview || (settings.enabled && (!settings.onlyWhenIdle || idleActive)) }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        var storage = defaults?.data(forKey: "snowglow-state-v1")
            .flatMap { try? JSONDecoder().decode(SnowStorage.self, from: $0) } ?? SnowStorage()
        storage.removeWreaths()
        storage.migrateRetiredWallpapers()
        settings = storage.settings
        scenes = storage.scenes
        originals = storage.originals
        welcomeSeen = storage.welcomeSeen
    }

    func persist() {
        let storage = SnowStorage(settings: settings, scenes: scenes, originals: originals, welcomeSeen: welcomeSeen)
        if let data = try? JSONEncoder().encode(storage) {
            defaults?.set(data, forKey: "snowglow-state-v1")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func add(_ kind: OrnamentKind, anchor: WindowAnchor? = nil) {
        if kind == .calendar, let existing = settings.ornaments.first(where: { $0.kind == .calendar }) {
            settings.ornamentsVisible = true
            selectedOrnament = existing.id
            return
        }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.screens.first
        let offset = Double(settings.ornaments.count % 5) * 0.052
        var ornament = Ornament(kind: kind, display: screen?.snowScreenID ?? 0,
                                x: 0.77 - offset, y: 0.29 + offset)
        if kind == .calendar { ornament.y = 0.42 }
        if kind == .snowman { ornament.snowmanFollowsGround = true }
        ornament.anchor = anchor
        add(ornament)
    }

    func add(_ ornament: Ornament) {
        guard ornament.kind != .wreath else { return }
        settings.ornamentsVisible = true
        settings.ornaments.append(ornament)
        selectedOrnament = ornament.id
    }

    func applyCabinScene() {
        var scene = settings
        scene.enabled = true
        scene.intensity = 0.63
        scene.speed = 0.46
        scene.wind = 0.10
        scene.accumulate = true
        scene.automaticPlowing = true
        scene.layer = .behindFrontWindow
        scene.onlyWhenIdle = false
        settings = scene
        wallpaperService?.apply(Wallpaper.cabin.id)
    }

    func change(_ id: UUID, _ apply: (inout Ornament) -> Void) {
        guard let index = settings.ornaments.firstIndex(where: { $0.id == id }) else { return }
        apply(&settings.ornaments[index])
    }

    func remove(_ id: UUID) {
        remove([id])
    }

    func remove(_ ids: Set<UUID>) {
        settings.ornaments.removeAll { ids.contains($0.id) }
        if let selectedOrnament, ids.contains(selectedOrnament) { self.selectedOrnament = settings.ornaments.first?.id }
    }

    func openDoor(_ day: Int, in id: UUID, now: Date = Date()) {
        guard let ornament = settings.ornaments.first(where: { $0.id == id }),
              day >= 1, day <= ornament.availableDoors(on: now), !ornament.opened.contains(day) else { return }
        change(id) { $0.opened.insert(day) }
    }

    private(set) var ornamentToAttach: UUID?

    func pickWindow(for ornament: UUID? = nil) {
        ornamentToAttach = ornament
        pickingWindow = true
        startPicking?()
    }

    func finishPickingWindow(_ anchor: WindowAnchor?) {
        pickingWindow = false
        defer { ornamentToAttach = nil }
        guard let anchor else { return }
        if let id = ornamentToAttach {
            change(id) {
                $0.anchor = anchor
                if $0.kind != .lights { $0.x = 0.72 }
            }
        } else {
            add(.lights, anchor: anchor)
        }
    }

    func saveScene(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let index = scenes.firstIndex(where: { $0.name == name }) {
            scenes[index].settings = settings
        } else {
            scenes.append(SavedScene(name: name, settings: settings))
        }
        feedback = "已保存「\(name)」"
    }

    func restoreScene(_ scene: SavedScene) {
        let currentWallpaper = settings.wallpaper
        let sceneWallpaper = Wallpaper.isRetired(scene.settings.wallpaper) ? Wallpaper.cabin.id : scene.settings.wallpaper
        var restored = scene.settings
        restored.removeWreaths()
        restored.wallpaper = currentWallpaper
        settings = restored
        if sceneWallpaper != currentWallpaper {
            if let index = sceneWallpaper {
                wallpaperService?.apply(index)
            } else {
                wallpaperService?.restore()
            }
        }
        selectedOrnament = settings.ornaments.first?.id
        feedback = "已载入「\(scene.name)」"
    }
}

extension NSScreen {
    var snowScreenID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                  green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }

    var snowRGB: UInt32 {
        guard let color = usingColorSpace(.sRGB) else { return 0xffbd71 }
        return UInt32((color.redComponent * 255).rounded()) << 16
            | UInt32((color.greenComponent * 255).rounded()) << 8
            | UInt32((color.blueComponent * 255).rounded())
    }
}
