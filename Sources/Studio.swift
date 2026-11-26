import SwiftUI

private func studioColor(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(rgb: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
    })
}

private let canvas = studioColor(0xfcfdff, 0x1b202a)
private let sidebar = studioColor(0xf0f3f8, 0x171c25)
private let card = studioColor(0xf1f4f8, 0x242c38)
private let mist = studioColor(0x566278, 0xaab6c8)
private let ice = studioColor(0x235fad, 0x9bc7ff)
private let divider = studioColor(0xdce3ed, 0x394454)
private let buttonFill = studioColor(0xe5ebf4, 0x323c4c)
private let selectedFill = studioColor(0xdfe9fa, 0x2c4260)
private let previewInk = Color(red: 0.047, green: 0.09, blue: 0.15)

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

    fileprivate var icon: StudioIcon {
        switch self {
        case .snowfall: .snow
        case .decorations: .decorations
        case .wallpapers: .wallpaper
        case .scenes: .scenes
        }
    }

    var heading: String {
        switch self {
        case .snowfall: "桌面降雪"
        case .decorations: "桌面装饰"
        case .wallpapers: "冬日壁纸"
        case .scenes: "冬日场景"
        }
    }

    var searchTerms: String {
        switch self {
        case .snowfall: "实时预览 雪花 开始 暂停"
        case .decorations: "雪人 衣帽间 圣诞树 彩灯 提灯 礼物 日历 摆放"
        case .wallpapers: "背景 桌面图片 恢复原壁纸"
        case .scenes: "保存 载入 恢复"
        }
    }

    var detail: String {
        switch self {
        case .snowfall: "雪会落在窗口和程序坞上。轻晃窗口即可抖落积雪。"
        case .decorations: "用鼠标直接拖动装饰，可从窗口拖到桌面，也可跨显示器摆放。"
        case .wallpapers: "\(Wallpaper.all.count) 张冬景。选择一张，即可应用到所有显示器。"
        case .scenes: "保存当前的雪况、壁纸和装饰布局，随时恢复。"
        }
    }
}

private enum WeatherSection: String, CaseIterable, Identifiable {
    case snow = "降雪参数"
    case ground = "积雪与铲雪"
    case idle = "空闲与锁屏"
    case cabin = "雪夜木屋"

    var id: Self { self }

    var icon: StudioIcon {
        switch self {
        case .snow: .snow
        case .ground: .plow
        case .idle: .moon
        case .cabin: .cabin
        }
    }

    var searchTerms: String {
        switch self {
        case .snow: "密度 速度 风向 风力 降雪位置"
        case .ground: "积雪 冰柱 清除 铲雪车 碰撞 破坏装饰 程序坞 Dock"
        case .idle: "空闲 锁屏 调暗 屏幕保护"
        case .cabin: "木屋 场景 雪人"
        }
    }
}

struct StudioView: View {
    @ObservedObject var model: SnowModel
    @State var page: StudioPage
    @State private var wallpaper = Wallpaper.cabin.id
    @State private var sceneName = ""
    @State private var search = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { scroll in
            HStack(spacing: 0) {
                navigation(scroll: scroll)
                Divider().overlay(divider)
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
                        .padding(.bottom, 24)
                    }
                    .id(page)
                    footer
                }
                .background(alignment: .topTrailing) {
                    StudioSnowPattern()
                        .frame(width: 360, height: 164)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                .background(canvas)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 865, minHeight: 610)
        .tint(ice)
        .onChange(of: model.selectedOrnament) { _, value in
            if value != nil && page == .decorations { model.feedback = nil }
        }
    }

    private var searchQuery: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matchingPages: [StudioPage] {
        StudioPage.allCases.filter { destination in
            searchQuery.isEmpty ||
            "\(destination.title) \(destination.heading) \(destination.searchTerms)".localizedStandardContains(searchQuery)
        }
    }

    private var matchingWeatherSections: [WeatherSection] {
        guard !searchQuery.isEmpty else { return [] }
        return WeatherSection.allCases.filter {
            "\($0.rawValue) \($0.searchTerms)".localizedStandardContains(searchQuery)
        }
    }

    private func navigation(scroll: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 7) {
                StudioIconView(icon: .search, size: 17)
                TextField("搜索设置", text: $search)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if let match = matchingWeatherSections.first { show(match, scroll: scroll) }
                        else if let match = matchingPages.first { open(match); search = "" }
                    }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        StudioIconView(icon: .clear, size: 15)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(buttonFill, in: Capsule())
            .padding(.top, 45)

            VStack(alignment: .leading, spacing: 3) {
                Text(searchQuery.isEmpty ? "设置" : "搜索结果")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mist)
                    .padding(.leading, 9)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)

                ForEach(matchingPages) { destination in
                    navigationItem(destination.title, icon: destination.icon,
                                   selected: destination == page) {
                        open(destination)
                        search = ""
                    }
                }
                ForEach(matchingWeatherSections) { section in
                    navigationItem(section.rawValue, icon: section.icon) {
                        show(section, scroll: scroll)
                    }
                }
                if matchingPages.isEmpty && matchingWeatherSections.isEmpty {
                    Text("没有找到相关设置。")
                        .font(.system(size: 12)).foregroundStyle(mist)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                }
            }

            Spacer(minLength: 8)
            HStack(spacing: 9) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable().scaledToFit()
                        .frame(width: 35, height: 35)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Snowglow").font(.system(size: 13, weight: .semibold))
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("v\(version)").font(.system(size: 11)).foregroundStyle(mist)
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 13)
        .frame(width: 185)
        .background(sidebar)
    }

    private func navigationItem(_ title: String, icon: StudioIcon, selected: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StudioIconView(icon: icon, size: 25)
                Text(title).font(.system(size: 14, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 43)
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioNavigationButton(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func open(_ destination: StudioPage) {
        page = destination
        model.feedback = nil
    }

    private func show(_ section: WeatherSection, scroll: ScrollViewProxy) {
        search = ""
        open(.snowfall)
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                scroll.scrollTo(section, anchor: .top)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            StudioIconView(icon: page.icon, size: 39)
            VStack(alignment: .leading, spacing: 5) {
                Text(page.heading)
                    .font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(page.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                model.settings.enabled.toggle()
            } label: {
                Label {
                    Text(model.settings.enabled ? "暂停降雪" : "开始降雪")
                } icon: {
                    StudioIconView(icon: model.settings.enabled ? .pause : .play, size: 18)
                }
            }
            .buttonStyle(StudioButton(prominent: !model.settings.enabled))
            .fixedSize()
        }
        .padding(.horizontal, 30)
        .padding(.top, 42)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.running ? ice : mist.opacity(0.55))
                .frame(width: 6, height: 6)
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
        .frame(height: 35)
        .background(canvas)
        .overlay(alignment: .top) { Rectangle().fill(divider).frame(height: 1) }
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: 19) {
            previewPanel
            settingsGroup(.snow) {
                weatherSlider("降雪密度", icon: .snow, value: $model.settings.intensity, range: 0...1)
                rowDivider
                weatherSlider("下落速度", icon: .speed, value: $model.settings.speed, range: 0...1)
                rowDivider
                weatherSlider("风向与风力", icon: .wind, value: $model.settings.wind, range: -1...1, wind: true)
                rowDivider
                weatherSlider("晶体雪花", icon: .snow, value: $model.settings.crystalMix, range: 0...1)
                rowDivider
                weatherSlider("局部阵风", icon: .wind, value: $model.settings.gusts, range: 0...1)
                rowDivider
                settingsRow("降雪位置", icon: .layer) {
                    Picker("降雪位置", selection: $model.settings.layer) {
                        ForEach(SnowLayer.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                rowDivider
                settingsRow("全屏时自动避让", subtitle: "只隐藏全屏应用所在屏幕的效果", icon: .layer) {
                    Toggle("全屏时自动避让", isOn: $model.settings.avoidFullscreen).labelsHidden()
                }
                rowDivider
                settingsRow("自动省电", subtitle: "使用电池、低电量模式或温度较高时降低绘制频率", icon: .dim) {
                    Toggle("自动省电", isOn: $model.settings.adaptivePower).labelsHidden()
                }
            }
            settingsGroup(.ground) {
                settingsRow("在窗口和屏幕底部积雪", icon: .accumulation) {
                    Toggle("在窗口和屏幕底部积雪", isOn: $model.settings.accumulate).labelsHidden()
                }
                rowDivider
                settingsRow("鼠标搓雪球", icon: .snow) {
                    Toggle("鼠标搓雪球", isOn: $model.settings.rollSnowballs).labelsHidden()
                }
                .disabled(!model.settings.accumulate)
                rowDivider
                settingsRow("形成冰柱", icon: .icicles) {
                    Toggle("形成冰柱", isOn: $model.settings.icicles).labelsHidden()
                }
                .disabled(!model.settings.accumulate)
                rowDivider
                settingsRow("自动铲雪", subtitle: "底部积雪达到一定厚度时自动发车", icon: .plow) {
                    HStack(spacing: 12) {
                        Button("立即铲雪") { model.runPlow?() }
                            .buttonStyle(StudioButton())
                            .disabled(!model.running)
                        Toggle("自动铲雪", isOn: $model.settings.automaticPlowing).labelsHidden()
                    }
                }
                .disabled(!model.settings.accumulate)
                rowDivider
                settingsRow("铲雪车可破坏装饰", subtitle: "开启后，铲雪车撞到的装饰会被移除", icon: .trash) {
                    Toggle("铲雪车可破坏装饰", isOn: $model.settings.plowDestroysDecorations).labelsHidden()
                }
            }
            settingsGroup(.idle) {
                settingsRow("空闲后开启", icon: .idleTime) {
                    Picker("空闲后开启", selection: $model.settings.idleSeconds) {
                        Text("关闭").tag(0)
                        Text("30 秒").tag(30)
                        Text("1 分钟").tag(60)
                        Text("2 分钟").tag(120)
                        Text("5 分钟").tag(300)
                        Text("10 分钟").tag(600)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                rowDivider
                settingsRow("仅空闲时降雪", icon: .moon) {
                    Toggle("仅空闲时降雪", isOn: $model.settings.onlyWhenIdle).labelsHidden()
                }
                .disabled(model.settings.idleSeconds == 0)
                rowDivider
                settingsRow("空闲时调暗桌面", icon: .dim) {
                    Toggle("空闲时调暗桌面", isOn: $model.settings.idleDim).labelsHidden()
                }
                .disabled(model.settings.idleSeconds == 0)
                if LockScreenSnow.supported {
                    rowDivider
                    settingsRow("锁屏飘雪", subtitle: "将「雪夜木屋」同时用于锁屏和桌面壁纸", icon: .lock) {
                        Button(model.lockSnowActive ? "恢复原壁纸" : "启用锁屏飘雪") { model.toggleLockSnow?() }
                            .buttonStyle(StudioButton())
                            .disabled(model.lockSnowChanging)
                    }
                }
            }
            .onChange(of: model.settings.idleSeconds) { _, new in
                if new == 0 { model.settings.onlyWhenIdle = false }
            }
            cabinScene.id(WeatherSection.cabin)
        }
    }

    private var previewPanel: some View {
        HStack(spacing: 16) {
            WeatherPreview(wallpaper: currentArtwork,
                           intensity: model.settings.intensity,
                           speed: model.settings.speed,
                           wind: model.settings.wind,
                           animated: model.settings.enabled && !reduceMotion)
                .frame(width: 196, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("冬季壁纸和降雪效果预览")
            VStack(alignment: .leading, spacing: 5) {
                Text("实时预览").font(.system(size: 15, weight: .semibold))
                Text("调整参数时，预览中的雪会随之变化。")
                    .font(.system(size: 12)).foregroundStyle(mist)
                HStack(spacing: 8) {
                    Button {
                        model.startPreview?()
                    } label: {
                        Label {
                            Text("全屏预览")
                        } icon: {
                            StudioIconView(icon: .preview, size: 18)
                        }
                    }
                    .buttonStyle(StudioButton(prominent: true))
                    .help("全屏预览。移动鼠标或按键退出。")
                    Button("清除积雪") { model.clearSnow?(); model.feedback = "积雪已清除。" }
                        .buttonStyle(StudioButton())
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(card, in: RoundedRectangle(cornerRadius: 15))
    }

    private func settingsGroup<Content: View>(_ section: WeatherSection,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(section.rawValue, icon: section.icon)
                .padding(.leading, 3)
            VStack(spacing: 0, content: content)
                .toggleStyle(.switch)
                .background(card, in: RoundedRectangle(cornerRadius: 15))
        }
        .id(section)
    }

    private func settingsRow<Control: View>(_ title: String, subtitle: String? = nil, icon: StudioIcon,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            StudioIconView(icon: icon, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(mist) }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
        .frame(minHeight: 45)
    }

    private var rowDivider: some View {
        Rectangle().fill(divider).frame(height: 0.5)
            .padding(.leading, 49)
            .padding(.trailing, 13)
            .accessibilityHidden(true)
    }

    private func weatherSlider(_ title: String, icon: StudioIcon, value: Binding<Double>,
                               range: ClosedRange<Double>, wind: Bool = false) -> some View {
        settingsRow(title, icon: icon) {
            Slider(value: value, in: range) { Text(title) }
                .labelsHidden()
                .frame(width: 145)
            Text(sliderValue(value.wrappedValue, range: range, wind: wind))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(mist)
                .frame(width: 43, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var currentArtwork: NSImage? {
        let art = Wallpaper.all.first(where: { $0.id == model.settings.wallpaper }) ?? .cabin
        return model.wallpaperService?.thumbnail(art)
    }

    private var cabinScene: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("雪夜木屋", icon: .cabin)
                .padding(.leading, 3)
            HStack(spacing: 12) {
                if let image = model.wallpaperService?.thumbnail(.cabin) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 103, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
                Text("一键应用木屋壁纸、飘雪和自动铲雪。")
                    .font(.system(size: 12))
                    .foregroundStyle(mist)
                Spacer(minLength: 8)
                Button("堆雪人…") { model.startSnowman?() }
                    .buttonStyle(StudioButton())
                Button("应用场景") { model.applyCabinScene() }
                    .buttonStyle(StudioButton(prominent: true))
                    .accessibilityLabel("应用雪夜木屋场景")
            }
            .surface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var decorations: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("添加装饰", icon: .decorations)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(OrnamentKind.allCases) { kind in
                    Button {
                        model.add(kind)
                    } label: {
                        HStack(spacing: 8) {
                            StudioIconView(icon: StudioIcon(ornament: kind), size: 24)
                            Text(kind.title).lineLimit(1)
                            Spacer(minLength: 0)
                            StudioIconView(icon: .add, size: 13)
                        }
                    }
                    .buttonStyle(StudioButton())
                    .accessibilityLabel("添加\(kind.title)")
                }
                Button {
                    model.pickWindow()
                } label: {
                    HStack(spacing: 7) {
                        StudioIconView(icon: .windowLights, size: 24)
                        Text("选窗口挂灯").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(StudioButton())
            }
            .surface()
            HStack {
                Button("拖雪球堆人…") { model.startSnowman?() }
                    .buttonStyle(StudioButton(prominent: true))
                Button("自由挂彩灯…") { model.hangLights?(nil) }
                    .buttonStyle(StudioButton())
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
            settingsRow("雪橇送礼物", subtitle: "礼物落稳后可以点开", icon: .gift) {
                Button("让雪橇出发") { model.hideStudio?(); model.sendSleigh?() }
                    .buttonStyle(StudioButton())
                Toggle("自动雪橇送礼物", isOn: $model.settings.festiveVisits).labelsHidden()
            }
            .surface()
            if model.settings.ornaments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("已摆放的装饰", icon: .decorations)
                    Text("添加的装饰会出现在这里。").foregroundStyle(mist).font(.system(size: 13))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        sectionTitle("已摆放", icon: .decorations)
                        ForEach(Array(model.settings.ornaments.enumerated()), id: \.element.id) { index, ornament in
                            Button { model.selectedOrnament = ornament.id } label: {
                                HStack(spacing: 8) {
                                    StudioIconView(icon: StudioIcon(ornament: ornament.kind), size: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ornament.title)
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
                sectionTitle(ornament.title, icon: StudioIcon(ornament: ornament.kind))
                Spacer()
                Button(role: .destructive) {
                    model.remove(ornament.id)
                } label: {
                    StudioIconView(icon: .trash, size: 18).frame(width: 20)
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
            if ornament.lightStrand != nil {
                Button("编辑挂钩…") { model.hangLights?(ornament.id) }
                    .buttonStyle(StudioButton(prominent: true))
            } else {
            HStack(spacing: 8) {
                Button(ornament.anchor == nil ? "放到窗口上" : "更换窗口") {
                    model.pickWindow(for: ornament.id)
                }
                .buttonStyle(StudioButton())
                if ornament.anchor != nil {
                    Button("移回桌面") {
                        model.change(ornament.id) {
                            $0.anchor = nil
                            if $0.kind == .snowman { $0.snowmanFollowsGround = true }
                        }
                    }
                    .buttonStyle(StudioButton())
                }
            }
            if ornament.anchor == nil {
                slider("水平位置", value: ornamentBinding(ornament, \.x), range: 0...1)
                slider("垂直位置", value: ornamentBinding(ornament, \.y), range: 0...1)
                if ornament.kind != .calendar {
                    slider("旋转", value: ornamentBinding(ornament, \.rotation), range: -180...180, wind: true)
                }
            } else if ornament.kind != .lights {
                slider("沿窗口移动", value: ornamentBinding(ornament, \.x), range: 0.02...0.98)
            }
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
                            if opened { StudioIconView(icon: .star, size: 18).frame(maxWidth: .infinity) }
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
                Spacer()
                Button("恢复原壁纸") { model.wallpaperService?.restore() }.buttonStyle(StudioButton())
                    .disabled(model.originals.isEmpty)
                Button("设为壁纸") { model.wallpaperService?.apply(wallpaper) }.buttonStyle(StudioButton(prominent: true))
            }
            sectionTitle("圣诞夜", icon: .tree)
            wallpaperCards(Wallpaper.christmas, columns: Wallpaper.christmas.count)
            sectionTitle("冬日雪景", icon: .snow)
                .padding(.top, 4)
            wallpaperCards(Wallpaper.winter)
        }
        .onAppear {
            wallpaper = Wallpaper.all.first { $0.id == model.settings.wallpaper }?.id ?? Wallpaper.cabin.id
        }
    }

    private func wallpaperCards(_ artwork: [Wallpaper], columns: Int = 3) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: columns), spacing: 11) {
            ForEach(artwork) { art in
                Button {
                    wallpaper = art.id
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Color.clear
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .overlay {
                                if let thumb = model.wallpaperService?.thumbnail(art) {
                                    Image(nsImage: thumb).resizable().scaledToFit()
                                }
                            }
                            .accessibilityHidden(true)
                        HStack {
                            Text(art.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            if model.settings.wallpaper == art.id {
                                StudioIconView(icon: .applied, size: 16)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.bottom, 9)
                    }
                    .background(card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(wallpaper == art.id ? ice : divider, lineWidth: wallpaper == art.id ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.settings.wallpaper == art.id ? "当前壁纸" : "")
                .accessibilityAddTraits(wallpaper == art.id ? .isSelected : [])
            }
        }
    }

    private var savedScenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("新场景", icon: .scenes)
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
                sectionTitle("已保存", icon: .archive)
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
                        } label: { StudioIconView(icon: .trash, size: 18) }
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
        }, set: { value in
            model.change(ornament.id) {
                $0[keyPath: keyPath] = value
                if $0.kind == .snowman && (keyPath as AnyKeyPath) == (\Ornament.y as AnyKeyPath) {
                    $0.snowmanFollowsGround = false
                }
            }
        })
    }

    private func sectionTitle(_ title: String, icon: StudioIcon) -> some View {
        Label {
            Text(title)
        } icon: {
            StudioIconView(icon: icon, size: 16)
        }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(mist)
            .accessibilityAddTraits(.isHeader)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, wind: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 5)
                Text(sliderValue(value.wrappedValue, range: range, wind: wind))
                    .monospacedDigit().foregroundStyle(mist).font(.system(size: 11))
                    .accessibilityHidden(true)
            }
            Slider(value: value, in: range) { Text(title) }.labelsHidden().accessibilityLabel(title)
        }
    }

    private func sliderValue(_ value: Double, range: ClosedRange<Double>, wind: Bool) -> String {
        if range.upperBound == 180 { return "\(Int(value.rounded()))°" }
        let sign = wind && value > 0 ? "+" : ""
        return "\(sign)\(Int((value * 100).rounded()))%"
    }
}

private extension View {
    func surface() -> some View {
        padding(13)
            .background(card, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct StudioButton: ButtonStyle {
    var prominent = false
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let emphasized = prominent && enabled
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .foregroundStyle(emphasized ? (scheme == .dark ? previewInk : .white) : selected ? ice : .primary)
            .opacity(enabled ? 1 : 0.48)
            .background(emphasized ? ice : selected ? selectedFill : buttonFill, in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(Rectangle())
    }
}

private struct StudioNavigationButton: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? ice : .primary)
            .background(selected ? selectedFill : configuration.isPressed ? buttonFill : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum StudioIcon: String, CaseIterable {
    case snow, decorations, wallpaper, scenes, tree, snowman, lights, lantern, gift
    case speed, wind, layer, accumulation, icicles, plow, idleTime, moon, dim
    case lock, cabin, calendar, windowLights, archive, search, clear, trash, star
    case play, pause, preview, add, applied

    init(ornament: OrnamentKind) {
        switch ornament {
        case .snowman: self = .snowman
        case .tree: self = .tree
        case .lights: self = .lights
        case .lantern: self = .lantern
        case .gift: self = .gift
        case .calendar: self = .calendar
        case .wreath: self = .decorations
        }
    }

    static let artwork: [Self: NSImage] = {
        var images: [Self: NSImage] = [:]
        for icon in allCases {
            if let url = Bundle.main.url(forResource: icon.rawValue, withExtension: "png", subdirectory: "SettingsIcons") {
                images[icon] = NSImage(contentsOf: url)
            }
        }
        return images
    }()
}

private struct StudioIconView: View {
    let icon: StudioIcon
    let size: CGFloat

    var body: some View {
        Group {
            if let image = StudioIcon.artwork[icon] {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct StudioSnowPattern: View {
    var body: some View {
        Canvas { context, size in
            var random = SnowRandom(state: 77_029)
            for _ in 0..<180 {
                let x = random.inRange(0, size.width)
                let y = random.inRange(0, size.height)
                let diameter = random.inRange(0.65, 2)
                let fade = (x / size.width) * (1 - y / size.height)
                let dot = CGRect(x: x, y: y, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: dot), with: .color(ice.opacity(fade * 0.23)))
            }
        }
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
                    LinearGradient(colors: [previewInk, Color(red: 0.15, green: 0.26, blue: 0.40)],
                                   startPoint: .bottom, endPoint: .top)
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
            }
            .clipped()
        }
    }
}
