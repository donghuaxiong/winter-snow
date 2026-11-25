import AppKit

enum LockScreenSnow {
    private static let asset = "571D41C4-ADF7-4CC3-BA0A-310173605F15"
    private static let category = "909AA2AC-0A2C-4C9C-A91F-63AE0F80E28A"
    private static let subcategory = "A28B6192-5485-48D3-970C-9632F9664B52"
    private static let provider = "com.apple.wallpaper.choice.aerials"
    private static let defaults = ["AllSpacesAndDisplays", "SystemDefault"]
    private static let aerialProcess = "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/MacOS/WallpaperAerialsExtension"
    private static let agentProcess = "/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent"
    private static let wallpaper = URL.applicationSupportDirectory.appending(path: "com.apple.wallpaper", directoryHint: .isDirectory)
    private static let aerials = wallpaper.appending(path: "aerials", directoryHint: .isDirectory)
    private static let manifest = aerials.appending(path: "manifest/entries.json")
    private static let index = wallpaper.appending(path: "Store/Index.plist")
    private static let backup = URL.applicationSupportDirectory.appending(path: "Snowglow/WallpaperBeforeLockSnow.plist")

    static var supported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    private static var available: Bool { supported && FileManager.default.fileExists(atPath: manifest.path) }

    static var isEnabled: Bool {
        guard available, let data = try? Data(contentsOf: index), let root = try? plist(data) else { return false }
        // Check the selections macOS can use on each live display and Space.
        return activePaths().filter { $0 != ["SystemDefault"] }.allSatisfy { usesSnow(selection(at: $0, in: root)) }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard available else { throw LockSnowError.catalogueMissing }
        if enabled { try registerMovie() }
        for attempt in 0..<2 {
            if enabled {
                try selectMovie(rememberOriginal: attempt == 0)
            } else {
                try restoreWallpaper()
            }
            try reloadWallpaperService()
            if enabled ? isEnabled : !hasSnowSelection() { return }
        }
        throw LockSnowError.wallpaperChanged
    }

    private static func registerMovie() throws {
        guard let movie = Bundle.main.url(forResource: "LockSnow", withExtension: "mov"),
              let poster = Bundle.main.url(forResource: "LockSnow", withExtension: "png") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let original = try Data(contentsOf: manifest)
        guard var catalogue = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              var assets = catalogue["assets"] as? [[String: Any]],
              var categories = catalogue["categories"] as? [[String: Any]] else {
            throw LockSnowError.invalidCatalogue
        }
        let video = aerials.appending(path: "videos/\(asset).mov")
        let thumbnail = aerials.appending(path: "thumbnails/\(asset).png")
        try install(movie, at: video)
        try install(poster, at: thumbnail)

        let scene = "雪夜木屋 · 飘雪"
        let shot = "SNOWGLOW_WINTER_CABIN"
        let image = thumbnail.absoluteString
        assets.removeAll { $0["id"] as? String == asset }
        assets.append([
            "id": asset, "shotID": shot, "localizedNameKey": scene, "accessibilityLabel": scene,
            "categories": [category], "subcategories": [subcategory], "pointsOfInterest": ["0": "\(shot)_0"],
            "previewImage": image, "url-4K-SDR-240FPS": video.absoluteString, "preferredOrder": 0,
            "includeInShuffle": false, "showInTopLevel": true,
        ])
        categories.removeAll { $0["id"] as? String == category }
        let summary: [String: Any] = ["localizedNameKey": "Snowglow", "localizedDescriptionKey": scene,
                                       "previewImage": image, "representativeAssetID": asset]
        let group = summary.merging(["id": subcategory, "preferredOrder": 0]) { _, new in new }
        categories.append(summary.merging(["id": category, "preferredOrder": 90, "subcategories": [group]]) { _, new in new })
        catalogue["assets"] = assets
        catalogue["categories"] = categories
        let updated = try JSONSerialization.data(withJSONObject: catalogue, options: [.sortedKeys, .withoutEscapingSlashes])
        try write(updated, to: manifest, replacing: original)
    }

    private static func selectMovie(rememberOriginal: Bool) throws {
        let original = try Data(contentsOf: index)
        var root = try plist(original)
        guard defaults.allSatisfy({ root[$0] is [String: Any] }), root["Spaces"] is [String: Any] else {
            throw LockSnowError.invalidCatalogue
        }
        let paths = activePaths()
        if rememberOriginal {
            var previous = (try? plist(Data(contentsOf: backup))) ?? root
            for path in paths {
                let current = selection(at: path, in: root)
                if !usesSnow(current) { setSelection(current, at: path[...], in: &previous) }
            }
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plistData(previous).write(to: backup, options: .atomic)
        }

        let configuration = try plistData(["assetID": asset])
        let options = try plistData(["values": [String: String]()])
        let now = Date()
        let choice: [String: Any] = ["Provider": provider, "Files": [String](), "Configuration": configuration]
        let content: [String: Any] = ["Choices": [choice], "EncodedOptionValues": options, "Shuffle": "$null"]
        let linked: [String: Any] = ["Content": content, "LastSet": now, "LastUse": now]
        for path in paths {
            var chosen = selection(at: path, in: root) ?? [:]
            chosen["Type"] = "linked"
            chosen["Linked"] = linked
            setSelection(chosen, at: path[...], in: &root)
        }
        try write(plistData(root), to: index, replacing: original)
    }

    private static func restoreWallpaper() throws {
        let saved = try plist(Data(contentsOf: backup))
        let original = try Data(contentsOf: index)
        var root = try plist(original)
        for path in allPaths(in: root) where usesSnow(selection(at: path, in: root)) {
            setSelection(selection(at: path, in: saved), at: path[...], in: &root)
        }
        try write(plistData(root), to: index, replacing: original)
    }

    private static func activePaths() -> [[String]] {
        var screens = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let result = CGGetActiveDisplayList(UInt32(screens.count), &screens, &count)
        let displayIDs = result == .success ? screens.prefix(Int(count)).compactMap(displayUUID) : []
        var paths = defaults.map { [$0] } + displayIDs.map { ["Displays", $0] }
        let active = Set(displayIDs).union(["Main"])
        let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences/com.apple.spaces.plist")
        guard let data = try? Data(contentsOf: file), let root = try? plist(data),
              let config = root["SpacesDisplayConfiguration"] as? [String: Any],
              let manager = config["Management Data"] as? [String: Any],
              let monitors = manager["Monitors"] as? [[String: Any]] else { return paths }
        let spaces = Set(monitors.compactMap { monitor -> String? in
            guard let id = monitor["Display Identifier"] as? String, active.contains(id) else { return nil }
            return (monitor["Current Space"] as? [String: Any])?["uuid"] as? String
        })
        for space in spaces.sorted() {
            paths.append(["Spaces", space, "Default"])
            paths += displayIDs.map { ["Spaces", space, "Displays", $0] }
        }
        return paths
    }

    private static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func allPaths(in root: [String: Any]) -> [[String]] {
        var paths = defaults.map { [$0] }
        if let displays = root["Displays"] as? [String: Any] { paths += displays.keys.map { ["Displays", $0] } }
        if let spaces = root["Spaces"] as? [String: [String: Any]] {
            for (id, value) in spaces {
                paths.append(["Spaces", id, "Default"])
                if let displays = value["Displays"] as? [String: Any] {
                    paths += displays.keys.map { ["Spaces", id, "Displays", $0] }
                }
            }
        }
        return paths
    }

    private static func selection(at path: [String], in root: [String: Any]) -> [String: Any]? {
        path.reduce(Optional(root)) { $0?[$1] as? [String: Any] }
    }

    private static func setSelection(_ value: [String: Any]?, at path: ArraySlice<String>, in root: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            root[key] = value
            return
        }
        if var child = root[key] as? [String: Any] ?? (value == nil ? nil : [:]) {
            setSelection(value, at: path.dropFirst(), in: &child)
            root[key] = child
        }
    }

    private static func hasSnowSelection() -> Bool {
        guard let data = try? Data(contentsOf: index), let root = try? plist(data) else { return false }
        return allPaths(in: root).contains { usesSnow(selection(at: $0, in: root)) }
    }

    private static func usesSnow(_ value: Any?) -> Bool {
        guard let selection = value as? [String: Any], selection["Type"] as? String == "linked",
              let linked = selection["Linked"] as? [String: Any], let content = linked["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first, choice["Provider"] as? String == provider,
              let data = choice["Configuration"] as? Data, let configuration = try? plist(data) else { return false }
        return configuration["assetID"] as? String == asset
    }

    private static func reloadWallpaperService() throws {
        func agentPID() -> Int32? {
            let output = run("/usr/bin/pgrep", match(agentProcess), capture: true)
            return output.split(whereSeparator: \.isWhitespace).first.flatMap { Int32($0) }
        }
        let previous = agentPID()
        for path in [aerialProcess, agentProcess] { _ = run("/usr/bin/pkill", ["-TERM"] + match(path)) }
        // The retiring agent can still write its old selection before it exits.
        for _ in 0..<24 {
            Thread.sleep(forTimeInterval: 0.12)
            if let current = agentPID(), current != previous {
                Thread.sleep(forTimeInterval: 0.16)
                return
            }
        }
        throw LockSnowError.serviceUnavailable
    }

    private static func match(_ path: String) -> [String] {
        ["-u", String(getuid()), "-f", "^\(NSRegularExpression.escapedPattern(for: path))([[:space:]]|$)"]
    }

    private static func run(_ executable: String, _ arguments: [String], capture: Bool = false) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = capture ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return capture ? String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) : ""
    }

    private static func install(_ source: URL, at destination: URL) throws {
        let files = FileManager.default
        if files.contentsEqual(atPath: source.path, andPath: destination.path) { return }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: source, options: .mappedIfSafe).write(to: destination, options: .atomic)
    }

    private static func write(_ data: Data, to file: URL, replacing original: Data) throws {
        guard try Data(contentsOf: file) == original else { throw LockSnowError.wallpaperChanged }
        try data.write(to: file, options: .atomic)
    }

    private static func plist(_ data: Data) throws -> [String: Any] {
        guard let document = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw LockSnowError.invalidCatalogue
        }
        return document
    }

    private static func plistData(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
}

private enum LockSnowError: LocalizedError {
    case catalogueMissing, invalidCatalogue, wallpaperChanged, serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .catalogueMissing: "macOS 需要先下载任意一款系统动态壁纸。"
        case .invalidCatalogue: "当前 macOS 的壁纸格式无法读取。"
        case .wallpaperChanged: "系统正在更新壁纸，请再试一次。"
        case .serviceUnavailable: "macOS 壁纸服务还没有准备好，请稍后重试。"
        }
    }
}
