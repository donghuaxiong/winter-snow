import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct SnowmanWardrobe: View {
    private enum Category: String, CaseIterable, Identifiable {
        case hats = "帽饰", face = "表情", body = "身体", clothes = "衣物"
        var id: Self { self }
    }

    @ObservedObject var model: SnowModel
    let id: UUID
    let close: () -> Void
    let share: () -> Void
    @State private var category: Category = .hats
    private let highlight = Color(red: 0.63, green: 0.88, blue: 0.95)
    private let soft = Color(red: 0.67, green: 0.77, blue: 0.84)
    private let tiles = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var item: Ornament? { model.settings.ornaments.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item {
                hero(item)
                Picker("换装类别", selection: $category) {
                    ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("换装类别")
                ScrollView {
                    PickList(item: item)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
                HStack {
                    Button("重置装扮") {
                        model.change(id) {
                            $0.hat = .none
                            $0.snowballs = 3
                            $0.costume = SnowmanCostume()
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(soft)
                    if category == .hats && item.hat != .none {
                        Button("摘下帽子") { model.change(id) { $0.hat = .none } }
                            .buttonStyle(.borderless)
                            .foregroundStyle(soft)
                    }
                    Spacer()
                    Button(action: share) {
                        Label("分享雪人", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.23))
                            .padding(.horizontal, 11)
                            .frame(minHeight: 31)
                            .background(highlight, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 13)
        .padding(.top, 24)
        .frame(width: 344, height: 456)
        .background {
            LinearGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.23),
                                    Color(red: 0.05, green: 0.099, blue: 0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .preferredColorScheme(.dark)
        .onChange(of: item == nil) { _, missing in if missing { close() } }
        .accessibilityAction(.escape) { close() }
    }

    private func hero(_ item: Ornament) -> some View {
        HStack(spacing: 13) {
            Canvas { context, size in
                context.withCGContext { ctx in
                    let shape = OrnamentKind.snowman.size
                    let scale = min(size.width / shape.width, size.height / shape.height)
                    let rect = CGRect(x: (size.width - shape.width * scale) / 2, y: (size.height - shape.height * scale) / 2,
                                      width: shape.width * scale, height: shape.height * scale)
                    DecorationArt.draw(item, in: rect, with: Ink(ctx: ctx), time: 0, now: Date())
                }
            }
            .frame(width: 66, height: 68)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("雪人衣帽间")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                Text("装扮会实时显示在桌面上。")
                    .font(.system(size: 11))
                    .foregroundStyle(soft)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.08), in: Circle())
            .accessibilityLabel("关闭衣帽间")
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func PickList(item: Ornament) -> some View {
        switch category {
        case .hats:
            LazyVGrid(columns: tiles, spacing: 6) {
                ForEach(Hat.allCases.filter { $0 != .none }) { hat in
                    tile(hat.title, selected: item.hat == hat, art: { ink in
                        SnowmanArt.drawHat(hat, at: p(33, 26), accent: 0xf47e79, ink: ink)
                    }) { model.change(id) { $0.hat = hat } }
                }
            }
        case .face:
            LazyVGrid(columns: tiles, spacing: 6) {
                ForEach(SnowmanFace.allCases) { face in
                    tile(face.title, selected: item.costume.face == face, art: { ink in
                        SnowmanArt.ball(p(33, 16), radius: 15.5, ink: ink)
                        SnowmanArt.drawFace(face, at: p(33, 14.5), ink: ink)
                    }) { model.change(id) { $0.costume.face = face } }
                }
            }
        case .body:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach([2, 3], id: \.self) { count in
                        tile(count == 2 ? "两层雪球" : "三层雪球", selected: item.snowballs == count, art: { ink in
                            ink.circle(33, 25, 8.5, 0xc9dff5)
                            if count == 3 { ink.circle(33, 15, 6.8, 0xecf6ff) }
                            ink.circle(33, count == 3 ? 5.8 : 11.6, 5.2, 0xffffff)
                        }) { model.change(id) { $0.snowballs = count } }
                    }
                }
                Toggle("树枝手臂", isOn: costumeBinding(\.arms))
                Toggle("煤球纽扣", isOn: costumeBinding(\.buttons))
            }
        case .clothes:
            LazyVGrid(columns: tiles, spacing: 6) {
                ForEach(SnowmanScarf.allCases) { scarf in
                    tile(scarf.title, selected: item.costume.scarf == scarf, art: { ink in
                        SnowmanArt.ball(p(33, 9), radius: 10, ink: ink)
                        SnowmanArt.drawScarf(scarf, palette: item.colors[0], at: p(33, 18), ink: ink)
                    }) { model.change(id) { $0.costume.scarf = scarf } }
                }
            }
        }
    }

    private func tile(_ name: String, selected: Bool, art: @escaping (Ink) -> Void,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Canvas { context, size in
                    context.withCGContext { ctx in
                        ctx.saveGState()
                        ctx.translateBy(x: (size.width - 66) / 2, y: 1.1)
                        art(Ink(ctx: ctx))
                        ctx.restoreGState()
                    }
                }
                .frame(height: 33)
                .accessibilityHidden(true)
                Text(name).font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? highlight : .white.opacity(0.89))
                    .lineLimit(1)
            }
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, minHeight: 49)
            .background(selected ? highlight.opacity(0.14) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? highlight.opacity(0.8) : .white.opacity(0.10), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func costumeBinding(_ key: WritableKeyPath<SnowmanCostume, Bool>) -> Binding<Bool> {
        Binding(get: { item?.costume[keyPath: key] ?? false },
                set: { value in model.change(id) { $0.costume[keyPath: key] = value } })
    }
}

enum SnowmanPortrait {
    static func write(_ ornament: Ornament, to url: URL) throws {
        let size = OrnamentKind.snowman.size
        var portrait = ornament
        portrait.rotation = 0
        let scale: CGFloat = 4
        guard let bitmap = WinterArtwork.bitmap(width: Int(size.width * scale), height: Int(size.height * scale), draw: { ink in
            DecorationArt.draw(portrait, in: CGRect(origin: .zero, size: CGSize(width: size.width * scale,
                                                                             height: size.height * scale)),
                               with: ink, time: 0, now: Date())
        }), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
