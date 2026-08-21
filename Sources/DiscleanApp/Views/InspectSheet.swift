import DiscleanKit
import SwiftUI

/// S-33 なかみ。「何が入っていて、実行すると何が起きるか」をファイル単位で見せる。
struct InspectSheet: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel
    let session: InspectSession

    var body: some View {
        let surface = Surface(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(surface.keyline).padding(.vertical, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explanationCards
                    locationBar
                    if session.showsRootList {
                        rootList
                    } else {
                        contents
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            footer
        }
        .padding(24)
        .frame(width: 840, height: 780)
        .background(surface.background)
    }

    // MARK: - 見出し

    private var header: some View {
        let surface = Surface(scheme: scheme)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("なかみ")
                    .font(Tokens.display(34))
                    .foregroundStyle(surface.text)
                Text(session.title)
                    .font(Tokens.bodyBold(16))
                    .foregroundStyle(surface.text)
            }
            Spacer(minLength: 0)
            UndoableBadge(undoable: session.undoable)
        }
    }

    // MARK: - 説明

    private var explanationCards: some View {
        HStack(alignment: .top, spacing: 12) {
            ExplainCard(fill: Tokens.lime, title: "これは何？", message: session.whatItIs)
            ExplainCard(fill: Tokens.sky, title: "このあとどうなる？", message: session.fate)
        }
    }

    // MARK: - 現在地

    private var locationBar: some View {
        let surface = Surface(scheme: scheme)
        return HStack(spacing: 10) {
            if session.canGoBack {
                Button("← もどる") { session.back(to: session.trail.count - 2) }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
            }
            if !session.locationLabel.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("いま見ている場所")
                        .font(Tokens.body(11))
                    Text(ScanItemFormat.shortPath(session.locationLabel, home: model.env.home))
                        .font(Tokens.data(12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .foregroundStyle(surface.text)
            }
            Spacer(minLength: 0)
            if let path = session.currentPath {
                Button("Finder で見る") { model.revealInFinder(path: path) }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
            }
        }
    }

    // MARK: - 根が複数あるとき（隔離庫の run など）

    private var rootList: some View {
        let surface = Surface(scheme: scheme)
        return VStack(alignment: .leading, spacing: 10) {
            Text("片づけた場所 \(session.roots.count) 件")
                .font(Tokens.bodyBold(14))
                .foregroundStyle(surface.text)
            ForEach(Array(session.roots.enumerated()), id: \.element.id) { index, root in
                HardCard(fill: Tokens.paper) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Format.bytes(root.bytes))
                                .font(Tokens.weightedData(18, bytes: root.bytes ?? 0))
                            Text(ScanItemFormat.shortPath(root.label, home: model.env.home))
                                .font(Tokens.data(12))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                KindChip(
                                    kind: root.isDirectory
                                        ? .folder
                                        : FileKind.infer(name: root.label, isDirectory: false))
                                if let note = root.note {
                                    Text(note).font(Tokens.body(11))
                                }
                                if let files = root.fileCount, root.isDirectory {
                                    Text("\(files) ファイル").font(Tokens.body(11))
                                }
                            }
                        }
                        .foregroundStyle(Tokens.ink)
                        Spacer(minLength: 0)
                        if root.isDirectory {
                            Button("なかを見る") { session.open(root) }
                                .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                        } else {
                            Button("Finder で見る") { model.revealInFinder(path: root.path) }
                                .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
                        }
                    }
                    .padding(14)
                }
                .plopIn(index: index)
            }
            if session.loading {
                Text("大きさを数えています…")
                    .font(Tokens.body(12))
                    .foregroundStyle(surface.text)
            }
        }
    }

    // MARK: - 中身

    @ViewBuilder private var contents: some View {
        let surface = Surface(scheme: scheme)
        if session.isEmptyTarget {
            ExplainCard(
                fill: Tokens.sunbeam, title: "場所の一覧はありません",
                message: "この項目は外部ツールが自分で消します。ディスクリンは場所を持っていないため、ファイル単位では見せられません。")
        } else if session.loading && session.inventory == nil {
            Text("中を見ています…")
                .font(Tokens.body(14))
                .foregroundStyle(surface.text)
        } else if let inventory = session.inventory {
            if inventory.notFound {
                ExplainCard(fill: Tokens.sunbeam, title: "この場所はもうありません", message: "すでに片づけられたか、移動されたようです。")
            } else if inventory.entries.isEmpty {
                ExplainCard(fill: Tokens.sunbeam, title: "空っぽです", message: "この場所にはファイルが入っていません。")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    totalsLine(inventory)
                    KindBreakdownView(inventory: inventory)
                    Text("入っているもの（大きい順）")
                        .font(Tokens.display(20))
                        .foregroundStyle(surface.text)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(inventory.entries.enumerated()), id: \.element.id) { index, entry in
                            InventoryRow(
                                entry: entry,
                                largest: inventory.entries.first?.bytes ?? entry.bytes,
                                onOpen: entry.isDirectory ? { session.open(entry) } : nil,
                                onReveal: { model.revealInFinder(path: entry.path) }
                            )
                            .plopIn(index: index)
                        }
                    }
                    if inventory.hiddenCount > 0 {
                        Text("ほか \(inventory.hiddenCount) 件（小さいものは省略しています）")
                            .font(Tokens.body(12))
                            .foregroundStyle(surface.text)
                    }
                }
            }
        }
    }

    private func totalsLine(_ inventory: Inventory) -> some View {
        let surface = Surface(scheme: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.bytes(inventory.totalBytes))
                    .font(Tokens.weightedData(24, bytes: inventory.totalBytes))
                Text("\(inventory.totalFiles) ファイル")
                    .font(Tokens.body(13))
            }
            .foregroundStyle(surface.text)
            if inventory.blocked {
                Text("読めない場所があります。フルディスクアクセスを許可すると全部見えます。")
                    .font(Tokens.body(12))
                    .foregroundStyle(surface.text)
            }
        }
    }

    // MARK: - 下

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button("閉じる") { model.inspectSession = nil }
                .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.top, 12)
    }
}

/// 戻せるかどうかは、色だけでなく必ず文字で言う（§2.4 / D-04）。
struct UndoableBadge: View {
    @Environment(\.colorScheme) private var scheme
    let undoable: Bool

    var body: some View {
        Text(undoable ? "戻せます" : "戻せません")
            .font(Tokens.bodyBold(12))
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule().fill(Surface(scheme: scheme).keyline)
                        .offset(x: Tokens.chipShadowOffset, y: Tokens.chipShadowOffset)
                    Capsule().fill(undoable ? Tokens.lime : Tokens.tomato)
                    Capsule().strokeBorder(Surface(scheme: scheme).keyline, lineWidth: Tokens.keylineWidth)
                }
            )
    }
}

/// 説明のカード。見出し 1 行と本文だけ。
struct ExplainCard: View {
    let fill: Color
    let title: String
    let message: String

    var body: some View {
        HardCard(fill: fill) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Tokens.bodyBold(14))
                Text(message)
                    .font(Tokens.body(13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Tokens.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 種類ごとの割合を 1 本の帯で見せ、出てきた種類だけ言葉で説明する。
struct KindBreakdownView: View {
    @Environment(\.colorScheme) private var scheme
    let inventory: Inventory

    private var slices: [(kind: FileKind, bytes: Int64)] {
        Dictionary(grouping: inventory.entries, by: \.kind)
            .map { (kind: $0.key, bytes: $0.value.reduce(Int64(0)) { $0 + $1.bytes }) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        let surface = Surface(scheme: scheme)
        let total = max(1, slices.reduce(Int64(0)) { $0 + $1.bytes })
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(slices, id: \.kind) { slice in
                        Rectangle()
                            .fill(InspectPalette.color(for: slice.kind))
                            .frame(width: max(3, geometry.size.width * CGFloat(slice.bytes) / CGFloat(total)))
                    }
                }
                .frame(height: 22)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth))
            }
            .frame(height: 22)
            .accessibilityLabel("種類ごとの割合")

            ForEach(slices.prefix(4), id: \.kind) { slice in
                HStack(alignment: .top, spacing: 8) {
                    KindChip(kind: slice.kind)
                    Text(slice.kind.explanationJa)
                        .font(Tokens.body(12))
                        .foregroundStyle(surface.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 種類のチップ。色は補助で、必ず文字ラベルを併記する。
struct KindChip: View {
    @Environment(\.colorScheme) private var scheme
    let kind: FileKind

    var body: some View {
        Text(kind.labelJa)
            .font(Tokens.data(10))
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                ZStack {
                    Capsule().fill(InspectPalette.color(for: kind))
                    Capsule().strokeBorder(Surface(scheme: scheme).keyline, lineWidth: 2)
                }
            )
            .fixedSize()
    }
}

enum InspectPalette {
    static func color(for kind: FileKind) -> Color {
        switch kind {
        case .folder: Tokens.sky
        case .archive: Tokens.lime
        case .contentBlob: Tokens.bubblegum
        case .log: Tokens.paper
        case .database: Tokens.sunbeam
        case .buildArtifact: Tokens.sunbeam
        case .code: Tokens.tomato
        case .image, .video, .audio: Tokens.tomato
        case .document: Tokens.paper
        case .other: Tokens.paper
        }
    }
}

/// ファイル 1 行。名前・種類・大きさ・最終更新を、太い線の中に 2 段で並べる。
/// 行を低く保つほど一度に見える件数が増え、「何が入っているか」が掴みやすい。
struct InventoryRow: View {
    @Environment(\.colorScheme) private var scheme
    let entry: InventoryEntry
    let largest: Int64
    let onOpen: (() -> Void)?
    let onReveal: () -> Void

    var body: some View {
        let surface = Surface(scheme: scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                KindChip(kind: entry.kind)
                Text(entry.name)
                    .font(Tokens.bodyBold(13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isSymlink {
                    Text("リンク（先は数えていません）").font(Tokens.body(11))
                }
                Spacer(minLength: 8)
                Text(Format.bytes(entry.bytes))
                    .font(Tokens.weightedData(14, bytes: entry.bytes))
                if let onOpen {
                    Button("ひらく", action: onOpen)
                        .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                }
                Button("Finder", action: onReveal)
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
            }
            HStack(spacing: 10) {
                sizeBar
                if entry.isDirectory {
                    Text("\(entry.fileCount) ファイル").font(Tokens.body(11)).fixedSize()
                }
                if let modified = entry.modified {
                    Text(modified.formatted(date: .abbreviated, time: .omitted))
                        .font(Tokens.body(11))
                        .fixedSize()
                }
            }
        }
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.chunkRadius, style: .continuous)
                    .fill(surface.keyline)
                    .offset(x: Tokens.chipShadowOffset, y: Tokens.chipShadowOffset)
                RoundedRectangle(cornerRadius: Tokens.chunkRadius, style: .continuous)
                    .fill(Tokens.paper)
                RoundedRectangle(cornerRadius: Tokens.chunkRadius, style: .continuous)
                    .strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth)
            }
        )
        .gummyPress(strength: onOpen == nil ? 0 : 0.03)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.name)、\(entry.kind.labelJa)、\(Format.bytes(entry.bytes))、\(entry.kind.explanationJa)")
    }

    /// 一番大きいものを基準にした帯。数字だけより量の差が伝わる。
    private var sizeBar: some View {
        let ratio = largest > 0 ? CGFloat(entry.bytes) / CGFloat(largest) : 0
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.ink.opacity(0.12))
                Capsule()
                    .fill(InspectPalette.color(for: entry.kind))
                    .frame(width: max(6, geometry.size.width * max(0.02, ratio)))
            }
        }
        .frame(height: 8)
    }
}
