import SwiftUI

private let ink = Color(red: 0.047, green: 0.09, blue: 0.15)
private let sidebar = Color(red: 0.060, green: 0.112, blue: 0.175)
private let card = Color(red: 0.083, green: 0.145, blue: 0.210)
private let mist = Color(red: 0.68, green: 0.77, blue: 0.85)
private let ice = Color(red: 0.63, green: 0.89, blue: 0.96)
private let amber = Color(red: 1, green: 0.83, blue: 0.58)
private let divider = Color.white.opacity(0.105)

enum StudioPage: String, CaseIterable, Identifiable {
    case snowfall, decorations, wallpapers, scenes
    var id: Self { self }

    var title: String {
        switch self {
        case .snowfall: "降雪"
        case .decorations: "装饰"
        case .wallpapers: "壁纸"
        case .scenes: "场景"
        }
    }

    var icon: String {
        switch self {
        case .snowfall: "snowflake"
        case .decorations: "sparkles"
        case .wallpapers: "photo.on.rectangle"
        case .scenes: "square.stack"
        }
    }

    var heading: String {
        switch self {
        case .snowfall: "桌面开始下雪"
        case .decorations: "装点你的桌面"
        case .wallpapers: "冬日壁纸"
        case .scenes: "保存冬日场景"
        }
    }

    var detail: String {
        switch self {
        case .snowfall: "雪会落在窗口和程序坞上。轻晃窗口即可抖落积雪。"
        case .decorations: "挑选装饰，用摆放模式在桌面上拖动。"
        case .wallpapers: "32 张原创冬景。选择一张，即可应用到所有显示器。"
        case .scenes: "保存当前的雪况、壁纸和装饰布局，随时恢复。"
        }
    }
}

struct StudioView: View {
    @ObservedObject var model: SnowModel
    @State var page: StudioPage
    @State private var collection = 0
    @State private var wallpaper = 8
    @State private var sceneName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            navigation
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    Group {
                        switch page {
                        case .snowfall: weather
                        case .decorations: decorations
                        case .wallpapers: wallpaperGallery
                        case .scenes: savedScenes
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
                    .padding(.bottom, 25)
                }
                footer
            }
            .background(ink)
        }
        .frame(minWidth: 865, minHeight: 610)
        .preferredColorScheme(.dark)
        .tint(ice)
        .onChange(of: model.selectedOrnament) { _, value in
            if value != nil && page == .decorations { model.feedback = nil }
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Color(red: 0.13, green: 0.25, blue: 0.34))
                    Image(systemName: "snowflake").font(.system(size: 19, weight: .medium)).foregroundStyle(ice)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Snowglow").font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text("雪灯桌面").font(.system(size: 11, weight: .medium)).foregroundStyle(mist)
                }
            }
            .padding(.top, 45)
            VStack(spacing: 4) {
                ForEach(StudioPage.allCases) { destination in
                    Button {
                        page = destination
                        model.feedback = nil
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: destination.icon)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(destination.title).font(.system(size: 14, weight: page == destination ? .semibold : .medium))
                            Spacer()
                        }
                        .foregroundStyle(page == destination ? ice : mist)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(page == destination ? ice.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == destination ? .isSelected : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(divider)
                Button {
                    model.settings.enabled.toggle()
                } label: {
                    Label(model.settings.enabled ? "暂停降雪" : "开始降雪",
                          systemImage: model.settings.enabled ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ice)
                .padding(.horizontal, 5)
            }
            .padding(.bottom, 15)
        }
        .padding(.horizontal, 16)
        .frame(width: 176)
        .background(sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(divider).frame(width: 1) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.heading).font(.system(size: 35, weight: .semibold, design: .serif))
                .foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Text(page.detail)
                .font(.system(size: 13)).foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.running ? ice : mist.opacity(0.55)).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(model.feedback ?? (model.preview ? "正在预览" : model.running ? "桌面正在下雪" :
                                        model.settings.enabled ? "等待空闲" : "降雪已暂停"))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(mist)
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer()
            if model.editMode {
                Button("退出摆放模式") { model.editMode = false }
                    .buttonStyle(.borderless)
                    .foregroundStyle(ice)
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 38)
        .background(sidebar.opacity(0.85))
        .overlay(alignment: .top) { Rectangle().fill(divider).frame(height: 1) }
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 17) {
                    sectionTitle("雪况", icon: "snowflake")
                    slider("降雪密度", value: $model.settings.intensity, range: 0...1)
                    slider("下落速度", value: $model.settings.speed, range: 0...1)
                    slider("风向与风力", value: $model.settings.wind, range: -1...1, wind: true)
                    Toggle("在窗口和屏幕底部积雪", isOn: $model.settings.accumulate)
                    Toggle("形成冰柱", isOn: $model.settings.icicles)
                        .disabled(!model.settings.accumulate)
                    Picker("降雪位置", selection: $model.settings.layer) {
                        ForEach(SnowLayer.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()

                VStack(alignment: .leading, spacing: 10) {
                    WeatherPreview(wallpaper: currentArtwork,
                                   intensity: model.settings.intensity,
                                   speed: model.settings.speed,
                                   wind: model.settings.wind,
                                   animated: model.settings.enabled && !reduceMotion)
                        .frame(height: 218)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("冬季壁纸和降雪效果预览")
                    HStack(spacing: 10) {
                        Button {
                            model.startPreview?()
                        } label: {
                            Label("预览桌面", systemImage: "play.rectangle")
                        }
                        .buttonStyle(StudioButton(prominent: true))
                        .help("全屏预览。移动鼠标或按键退出。")
                        Button("清除积雪") { model.clearSnow?(); model.feedback = "积雪已清除。" }
                            .buttonStyle(StudioButton())
                        Spacer(minLength: 0)
                    }
                    Divider()
                    HStack(spacing: 8) {
                        Toggle("自动铲雪", isOn: $model.settings.automaticPlowing)
                            .help("屏幕底部积雪够厚时自动发车，清完后重新积雪。")
                        Spacer(minLength: 4)
                        Button("立即铲雪") { model.runPlow?() }
                            .buttonStyle(StudioButton())
                            .disabled(!model.running)
                    }
                    .disabled(!model.settings.accumulate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
            }
            cabinScene
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("空闲模式", icon: "moon.stars")
                HStack(alignment: .center, spacing: 14) {
                    Picker("空闲后开启", selection: $model.settings.idleSeconds) {
                        Text("关闭").tag(0)
                        Text("30 秒").tag(30)
                        Text("1 分钟").tag(60)
                        Text("2 分钟").tag(120)
                        Text("5 分钟").tag(300)
                        Text("10 分钟").tag(600)
                    }
                    .fixedSize()
                    Toggle("仅空闲时降雪", isOn: $model.settings.onlyWhenIdle)
                        .disabled(model.settings.idleSeconds == 0)
                    Toggle("空闲时调暗桌面", isOn: $model.settings.idleDim)
                        .disabled(model.settings.idleSeconds == 0)
                }
                .onChange(of: model.settings.idleSeconds) { _, new in
                    if new == 0 { model.settings.onlyWhenIdle = false }
                }
                if LockScreenSnow.supported {
                    Divider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("锁屏飘雪").font(.system(size: 13, weight: .semibold))
                            Text("macOS 会把「雪夜木屋」同时用于锁屏和桌面壁纸。")
                                .font(.system(size: 12)).foregroundStyle(mist)
                        }
                        Spacer(minLength: 0)
                        Button(model.lockSnowActive ? "恢复原壁纸" : "启用锁屏飘雪") { model.toggleLockSnow?() }
                            .buttonStyle(StudioButton())
                            .disabled(model.lockSnowChanging)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        }
    }

    private var currentArtwork: NSImage? {
        let id = model.settings.wallpaper ?? 8
        let art = Wallpaper.all.first(where: { $0.id == id }) ?? Wallpaper.all[8]
        return model.wallpaperService?.thumbnail(art)
    }

    private var cabinScene: some View {
        HStack(spacing: 12) {
            if let image = model.wallpaperService?.thumbnail(.cabin) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 103, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                sectionTitle("雪夜木屋", icon: "moon.stars")
                Text("暖窗、夜山、飘雪和自动铲雪一起开启。")
                    .font(.system(size: 11))
                    .foregroundStyle(mist)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("堆雪人…") { model.startSnowman?() }
                .buttonStyle(StudioButton())
            Button("应用场景") { model.applyCabinScene() }
                .buttonStyle(StudioButton(prominent: true))
                .accessibilityLabel("应用雪夜木屋场景")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }

    private var decorations: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(OrnamentKind.allCases) { kind in
                    Button {
                        model.add(kind)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.icon).foregroundStyle(kind == .lights || kind == .lantern ? amber : ice)
                                .accessibilityHidden(true)
                            Text(kind.title).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "plus").font(.system(size: 9, weight: .semibold)).foregroundStyle(mist)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(StudioButton())
                    .accessibilityLabel("添加\(kind.title)")
                }
                Button {
                    model.pickWindow()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "macwindow.badge.plus").accessibilityHidden(true)
                        Text("选窗口挂灯").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(StudioButton(prominent: true))
            }
            HStack {
                Button("拖雪球堆人…") { model.startSnowman?() }
                    .buttonStyle(StudioButton(prominent: true))
                Button(model.settings.ornamentsVisible ? "收起装饰" : "恢复装饰") {
                    model.settings.ornamentsVisible.toggle()
                }
                .buttonStyle(StudioButton())
                .disabled(model.settings.ornaments.isEmpty)
                Button(model.editMode ? "退出摆放" : "在桌面摆放") {
                    model.editMode.toggle()
                    if model.editMode { model.hideStudio?() }
                }
                .buttonStyle(StudioButton())
                .disabled(model.settings.ornaments.isEmpty)
                Spacer()
            }
            if model.settings.ornaments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("已摆放的装饰", icon: "sparkles")
                    Text("添加的装饰会出现在这里。").foregroundStyle(mist).font(.system(size: 13))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        sectionTitle("已摆放", icon: "sparkles")
                        ForEach(Array(model.settings.ornaments.enumerated()), id: \.element.id) { index, ornament in
                            Button { model.selectedOrnament = ornament.id } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: ornament.kind.icon).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ornament.kind.title)
                                        if let owner = ornament.anchor?.owner {
                                            Text(owner).font(.system(size: 10)).foregroundStyle(mist).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 1)
                                    Text(String(index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(mist)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(StudioButton(selected: selectedDecoration?.id == ornament.id))
                            .accessibilityAddTraits(selectedDecoration?.id == ornament.id ? .isSelected : [])
                        }
                    }
                    .frame(width: 165)
                    .surface()
                    if let item = selectedDecoration { decorationSettings(item) }
                }
            }
        }
    }

    private var selectedDecoration: Ornament? {
        model.settings.ornaments.first { $0.id == model.selectedOrnament } ?? model.settings.ornaments.first
    }

    private func decorationSettings(_ ornament: Ornament) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(ornament.kind.title, icon: ornament.kind.icon)
                Spacer()
                Button(role: .destructive) {
                    model.remove(ornament.id)
                } label: {
                    Image(systemName: "trash").frame(width: 20)
                }
                .buttonStyle(StudioButton())
                .accessibilityLabel("移除\(ornament.kind.title)")
            }
            if ornament.kind != .calendar {
                Picker("配色", selection: ornamentBinding(ornament, \.palette)) {
                    ForEach(FestivePalette.allCases) { Text($0.title).tag($0) }
                }
                if ornament.palette == .custom {
                    ColorPicker("装饰颜色", selection: Binding(get: {
                        Color(nsColor: NSColor(rgb: ornament.customColor))
                    }, set: { value in
                        model.change(ornament.id) { $0.customColor = NSColor(value).snowRGB }
                    }), supportsOpacity: false)
                }
            }
            if ornament.kind == .snowman {
                Picker("雪球", selection: ornamentBinding(ornament, \.snowballs)) {
                    Text("两个").tag(2)
                    Text("三个").tag(3)
                }
                .pickerStyle(.segmented)
                Picker("帽子", selection: ornamentBinding(ornament, \.hat)) {
                    ForEach(Hat.allCases) { Text($0.title).tag($0) }
                }
                Button("打开衣帽间") { model.showWardrobe?(ornament.id, nil) }
                    .buttonStyle(StudioButton())
            }
            if ornament.kind == .tree {
                Toggle("挂上彩球", isOn: ornamentBinding(ornament, \.extras))
            }
            if ornament.kind == .lights {
                Picker("灯泡", selection: ornamentBinding(ornament, \.bulb)) {
                    ForEach(Bulb.allCases) { Text($0.title).tag($0) }
                }
                Picker("灯效", selection: ornamentBinding(ornament, \.lightMotion)) {
                    ForEach(LightMotion.allCases) { Text($0.title).tag($0) }
                }
                if ornament.anchor != nil {
                    Picker("悬挂位置", selection: ornamentBinding(ornament, \.placement)) {
                        ForEach(Placement.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            slider("大小", value: ornamentBinding(ornament, \.scale), range: 0.5...2.0)
            if ornament.kind != .lights {
                HStack(spacing: 8) {
                    Button(ornament.anchor == nil ? "放到窗口上" : "更换窗口") {
                        model.pickWindow(for: ornament.id)
                    }
                    .buttonStyle(StudioButton())
                    if ornament.anchor != nil {
                        Button("移回桌面") { model.change(ornament.id) { $0.anchor = nil } }
                            .buttonStyle(StudioButton())
                    }
                }
            }
            if ornament.anchor == nil {
                slider("水平位置", value: ornamentBinding(ornament, \.x), range: 0.02...0.98)
                slider("垂直位置", value: ornamentBinding(ornament, \.y), range: 0.02...0.98)
                if ornament.kind != .calendar {
                    slider("旋转", value: ornamentBinding(ornament, \.rotation), range: -180...180, wind: true)
                }
            } else if ornament.kind != .lights {
                slider("沿窗口移动", value: ornamentBinding(ornament, \.x), range: 0.02...0.98)
            }
            if ornament.kind == .calendar {
                let available = ornament.availableDoors(on: Date())
                Text("每天可开启一格惊喜。今天可开启 \(available) 格。")
                    .font(.system(size: 12)).foregroundStyle(mist)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5), spacing: 5) {
                    ForEach(1...25, id: \.self) { day in
                        let opened = ornament.opened.contains(day)
                        Button {
                            model.openDoor(day, in: ornament.id)
                            model.feedback = "已打开第 \(day) 格惊喜。"
                        } label: {
                            if opened { Image(systemName: "star.fill").foregroundStyle(amber).frame(maxWidth: .infinity) }
                            else { Text("\(day)").monospacedDigit().frame(maxWidth: .infinity) }
                        }
                        .buttonStyle(StudioButton(selected: opened))
                        .disabled(day > available)
                        .accessibilityLabel("第 \(day) 格\(opened ? "，已打开" : "")")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }

    private var wallpaperGallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("系列", selection: $collection) {
                    ForEach(Wallpaper.collections.indices, id: \.self) { Text(Wallpaper.collections[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 350)
                Spacer(minLength: 12)
                Button("恢复原壁纸") { model.wallpaperService?.restore() }.buttonStyle(StudioButton())
                    .disabled(model.originals.isEmpty)
                Button("设为壁纸") { model.wallpaperService?.apply(wallpaper) }.buttonStyle(StudioButton(prominent: true))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 3), spacing: 11) {
                ForEach(Wallpaper.all.filter { $0.collection == collection }) { art in
                    Button {
                        wallpaper = art.id
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            if let thumb = model.wallpaperService?.thumbnail(art) {
                                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                                    .frame(height: 102).clipped().accessibilityHidden(true)
                            }
                            HStack {
                                Text(art.name).font(.system(size: 12, weight: .medium))
                                Spacer()
                                if model.settings.wallpaper == art.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(ice)
                                        .accessibilityLabel("当前壁纸")
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.bottom, 9)
                        }
                        .background(card)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay { RoundedRectangle(cornerRadius: 9).stroke(wallpaper == art.id ? ice : divider, lineWidth: 1.3) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(wallpaper == art.id ? .isSelected : [])
                }
            }
        }
        .onAppear {
            let art = Wallpaper.all.first { $0.id == (model.settings.wallpaper ?? 8) }
            wallpaper = art?.id ?? 8
            collection = art?.collection ?? 1
        }
        .onChange(of: collection) { _, new in
            if Wallpaper.all.first(where: { $0.id == wallpaper })?.collection != new {
                wallpaper = Wallpaper.all.first(where: { $0.collection == new })?.id ?? 0
            }
        }
    }

    private var savedScenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("新场景", icon: "square.stack")
                HStack(spacing: 12) {
                    TextField("场景名称", text: $sceneName, prompt: Text("例如：平安夜"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveScene)
                    Button("保存当前场景", action: saveScene).buttonStyle(StudioButton(prominent: true))
                        .disabled(sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .surface()
            VStack(alignment: .leading, spacing: 11) {
                sectionTitle("已保存", icon: "tray.full")
                if model.scenes.isEmpty {
                    Text("保存的场景会显示在这里。").foregroundStyle(mist).font(.system(size: 13))
                }
                ForEach(model.scenes) { scene in
                    HStack(spacing: 10) {
                        Text(scene.name).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("载入") { model.restoreScene(scene) }.buttonStyle(StudioButton())
                        Button(role: .destructive) {
                            model.scenes.removeAll { $0.id == scene.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(StudioButton())
                            .accessibilityLabel("删除场景 \(scene.name)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        }
    }

    private func saveScene() {
        model.saveScene(named: sceneName)
        sceneName = ""
    }

    private func ornamentBinding<Value>(_ ornament: Ornament, _ keyPath: WritableKeyPath<Ornament, Value>) -> Binding<Value> {
        Binding(get: {
            (model.settings.ornaments.first { $0.id == ornament.id } ?? ornament)[keyPath: keyPath]
        }, set: { value in model.change(ornament.id) { $0[keyPath: keyPath] = value } })
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ice)
            .accessibilityAddTraits(.isHeader)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, wind: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 5)
                Text(range.upperBound == 180 ? "\(Int(value.wrappedValue.rounded()))°" :
                        "\(wind && value.wrappedValue > 0 ? "+" : "")\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(mist).font(.system(size: 11))
                    .accessibilityHidden(true)
            }
            Slider(value: value, in: range) { Text(title) }.labelsHidden().accessibilityLabel(title)
        }
    }
}

private extension View {
    func surface() -> some View {
        padding(15)
            .background(card, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(divider, lineWidth: 1).allowsHitTesting(false) }
    }
}

private struct StudioButton: ButtonStyle {
    var prominent = false
    var selected = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .foregroundStyle(prominent && enabled ? ink : selected ? ice : Color.white.opacity(enabled ? 0.91 : 0.42))
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(prominent && enabled ? ice.opacity(configuration.isPressed ? 0.73 : 1) :
                            ice.opacity(selected ? 0.17 : configuration.isPressed ? 0.14 : 0.08))
            }
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? ice.opacity(0.52) : divider, lineWidth: 1) }
            .contentShape(Rectangle())
    }
}

private struct WeatherPreview: View {
    var wallpaper: NSImage?
    var intensity: Double
    var speed: Double
    var wind: Double
    var animated: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let wallpaper {
                    Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped().accessibilityHidden(true)
                } else {
                    LinearGradient(colors: [sidebar, card], startPoint: .top, endPoint: .bottom)
                }
                TimelineView(.animation(minimumInterval: 1 / 23, paused: !animated)) { timeline in
                    Canvas { context, size in
                        guard intensity >= 0 else { return }
                        let t = animated ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 135) : 10
                        var rng = SnowRandom(state: 195_127)
                        for _ in 0..<Int(24 + intensity * 86) {
                            let radius = rng.inRange(0.42, 2.1)
                            let baseX = rng.next() * size.width
                            let baseY = rng.next() * size.height
                            let rate = rng.inRange(8, 34) * (0.35 + speed * 1.7)
                            let rawX = (baseX + t * wind * 18 + sin(t * 0.65 + baseY) * 5)
                                .truncatingRemainder(dividingBy: size.width)
                            let x = rawX < 0 ? rawX + size.width : rawX
                            let y = (baseY + t * rate).truncatingRemainder(dividingBy: size.height)
                            let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.42 + radius / 5)))
                        }
                    }
                }
                LinearGradient(colors: [.clear, ink.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 6) {
                    Image(systemName: "snowflake").accessibilityHidden(true)
                    Text("效果预览")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(11)
            }
            .clipped()
        }
    }
}
