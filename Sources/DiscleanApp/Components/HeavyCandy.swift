import SwiftUI
import DiscleanKit

/// ぼかし 0 のハードオフセット影 + 3px キーライン（§4）。`.shadow` は使わない。
struct HardCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var fill: Color?
    var radius: CGFloat = Tokens.cardRadius
    var offset: CGFloat = Tokens.cardShadowOffset
    var rotation: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        let surface = Surface(scheme: scheme)
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(surface.keyline)
                        .offset(x: offset, y: offset)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill ?? surface.card)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth)
                }
            )
            .rotationEffect(.degrees(rotation))
    }
}

/// Tier のチップ。色だけで伝えず、必ず文字ラベルを併記する（§2.4 / D-04）。
struct TierChip: View {
    @Environment(\.colorScheme) private var scheme
    let tier: Tier

    private var fill: Color {
        switch tier {
        case .a: Tokens.lime
        case .b: Tokens.sunbeam
        case .c: Tokens.sky
        }
    }

    private var label: String {
        switch tier {
        case .a: "A"
        case .b: "B"
        case .c: "見るだけ"
        }
    }

    var body: some View {
        Text(label)
            .font(Tokens.data(11))
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    Capsule().fill(Surface(scheme: scheme).keyline)
                        .offset(x: Tokens.chipShadowOffset, y: Tokens.chipShadowOffset)
                    Capsule().fill(fill)
                    Capsule().strokeBorder(Surface(scheme: scheme).keyline, lineWidth: Tokens.keylineWidth)
                }
            )
            .accessibilityLabel(tier == .c ? "見るだけ、削除されません" : "リスク階層 \(label)")
    }
}

/// 容量 1 件を表す塊。高さが容量に比例する（§5.1）。
struct ChunkView: View {
    @Environment(\.colorScheme) private var scheme
    let item: ScanItem
    let selected: Bool
    let onToggle: () -> Void

    private var fill: Color {
        if item.state == .blocked { return Surface(scheme: scheme).card }
        switch item.tier {
        case .a: return Tokens.lime
        case .b: return Tokens.sunbeam
        case .c: return Tokens.sky
        }
    }

    private var sizeText: String { ScanItemFormat.size(item) }

    var body: some View {
        let surface = Surface(scheme: scheme)
        HStack(alignment: .top, spacing: 14) {
            if item.state != .blocked && item.tier != .c {
                Toggle("", isOn: Binding(get: { selected }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(item.title) を選ぶ")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(sizeText)
                        .font(Tokens.weightedData(22, bytes: item.bytes))
                        .foregroundStyle(Tokens.ink)
                    TierChip(tier: item.tier)
                    if !item.undoable {
                        Text("取り消せません")
                            .font(Tokens.data(11))
                            .foregroundStyle(Tokens.ink)
                    }
                }
                Text(item.title)
                    .font(Tokens.bodyBold(15))
                    .foregroundStyle(Tokens.ink)
                // 「何を失うか」は装飾しない（§1.1）。
                Text(item.whatIsLost)
                    .font(Tokens.body(12))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if item.state == .blocked {
                    Text("フルディスクアクセスが要ります")
                        .font(Tokens.body(12))
                        .foregroundStyle(Tokens.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: Tokens.chunkHeight(bytes: item.bytes), alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.chunkRadius, style: .continuous)
                    .fill(surface.keyline)
                    .offset(x: selected ? 8 : Tokens.chipShadowOffset, y: selected ? 8 : Tokens.chipShadowOffset)
                RoundedRectangle(cornerRadius: Tokens.chunkRadius, style: .continuous).fill(fill)
                RoundedRectangle(cornerRadius: Tokens.chunkRadius, style: .continuous)
                    .strokeBorder(
                        surface.keyline,
                        style: StrokeStyle(
                            lineWidth: selected ? 5 : Tokens.keylineWidth,
                            dash: item.state == .blocked ? [8, 6] : []))
            }
        )
        .jelly(on: selected)
        .gummyPress(strength: item.state == .blocked || item.tier == .c ? 0 : 0.035)
        .animation(Motion.gummy, value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "\(sizeText)、\(item.tier == .c ? "見るだけ" : "Tier " + item.tier.rawValue)、"
                + "\(selected ? "選択済み" : "未選択")、失うもの: \(item.whatIsLost)")
    }
}

/// 実行レバー。クリックでは発火せず、120px 引き下げるか、キーボードで明示操作する（§5.2 / D-05）。
struct LeverView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let enabled: Bool
    let onFire: () -> Void

    @State private var drag: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        let surface = Surface(scheme: scheme)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(surface.keyline)
                    .frame(width: 10, height: 200)
                VStack(spacing: 4) {
                    Text(reduceMotion ? "おして実行" : "ひきさげて実行")
                        .font(Tokens.display(15))
                        .foregroundStyle(Tokens.paper)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                            .fill(surface.keyline)
                            .offset(x: Tokens.cardShadowOffset, y: Tokens.cardShadowOffset)
                        RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                            .fill(enabled ? Tokens.grape : Tokens.grape.opacity(0.45))
                        RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                            .strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth)
                    }
                )
                // 引くほど握りが縦に伸びる（ゴムを引く手応え）
                .scaleEffect(
                    x: 1 - min(1, drag / Tokens.leverThrow) * 0.06,
                    y: 1 + min(1, drag / Tokens.leverThrow) * 0.1,
                    anchor: .top
                )
                .offset(y: drag)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .local)
                        .onChanged { value in
                            guard enabled, !reduceMotion else { return }
                            drag = max(0, min(Tokens.leverThrow + 20, value.translation.height))
                        }
                        .onEnded { _ in
                            guard enabled, !reduceMotion else { return }
                            if drag >= Tokens.leverThrow { onFire() }
                            withAnimation(Motion.gummy) { drag = 0 }
                        }
                )
                // reduce-motion のときだけ単一クリックで確認シートへ進む（§6 / D-06）。
                .onTapGesture { if enabled && reduceMotion { onFire() } }
            }
            .frame(height: 220, alignment: .top)
        }
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled(false)
        .onKeyPress(.return) {
            guard enabled else { return .ignored }
            onFire()
            return .handled
        }
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(focused ? surface.focus : .clear, lineWidth: 3)
                .padding(-3)
        )
        .accessibilityLabel("実行レバー")
        .accessibilityHint("引き下げるか、フォーカスして Return を押すと確認画面が出ます")
        .accessibilityAddTraits(.isButton)
    }
}

/// 表示用の整形。CLI と同じ考え方で、外部ツール任せの項目は数値を約束しない。
enum ScanItemFormat {
    static func size(_ item: ScanItem) -> String {
        if item.state == .blocked { return "測れません" }
        if !item.sizeKnown { return "実行後に判明" }
        return Format.bytes(item.bytes)
    }
}

/// 量の表記はここに集約する。`ByteCountFormatter` は 0 を "Zero KB" と書くため直接使わない。
enum Format {
    static func bytes(_ value: Int64) -> String {
        value <= 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "測っていません" }
        return bytes(value)
    }
}
