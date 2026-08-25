import DiscleanKit
import SwiftUI

/// 探した結果の但し書き。「0 件でした」と「見えていなかった」を混同させないために持つ。
struct BigSearchNotes {
    let blocked: Bool
    let truncated: Bool
    let datalessSkipped: Bool
    let scannedEntries: Int
    let roots: [String]
    let minimumBytes: Int64

    init(result: BigItemResult) {
        blocked = result.blocked
        truncated = result.truncated
        datalessSkipped = result.datalessSkipped
        scannedEntries = result.scannedEntries
        roots = result.roots
        minimumBytes = result.minimumBytes
    }
}

/// S-37 大きいもの（GUI）。書類の中にある大きいものを探し、選んだものだけを隔離庫へ移す。
///
/// ここに並ぶのは「作り直せるキャッシュ」ではなく、多くが自分のファイルなので、
/// 既定では 1 件も選ばれない。選ぶのは必ず人で、押す前に失うものを平文で見せる。
struct BigItemsView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AppModel

    private let thresholds = [200, 500, 1000]

    var body: some View {
        let surface = Surface(scheme: scheme)
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    controls
                    if model.bigSearching {
                        BusyBoard(busy: model.busy, onStop: { model.stopWork() })
                    }
                    if let outcome = model.bigOutcome, !outcome.quarantined.isEmpty {
                        movedCard(outcome)
                    }
                    notes
                    ForEach(Array(model.bigItems.enumerated()), id: \.element.path) { index, item in
                        BigItemCard(
                            item: item,
                            selected: model.bigSelection.contains(item.path),
                            home: model.env.home,
                            onToggle: { model.toggleBig(item) },
                            onInspect: { model.inspect(big: item) },
                            onReveal: { model.revealInFinder(path: item.path) }
                        )
                        .plopIn(index: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 16) {
                HardCard(fill: Tokens.paper) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("えらんだ量")
                            .font(Tokens.data(11))
                            .foregroundStyle(Tokens.ink)
                        Text(Format.bytes(model.selectedBigBytes))
                            .font(Tokens.weightedData(26, bytes: model.selectedBigBytes))
                            .foregroundStyle(Tokens.ink)
                            .contentTransition(.numericText())
                            .animation(Motion.gummy, value: model.selectedBigBytes)
                        Text("\(model.selectedBigItems.count) / \(model.bigItems.count) 件")
                            .font(Tokens.body(12))
                            .foregroundStyle(Tokens.ink)
                    }
                    .padding(16)
                    .frame(width: 200, alignment: .leading)
                }
                Button("隔離庫へうつす") { model.showBigConfirmSheet = true }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                    .disabled(model.selectedBigItems.isEmpty)
                Text("えらんだものだけを移します。何もえらんでいなければ、何も起きません。")
                    .font(Tokens.body(11))
                    .foregroundStyle(surface.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 230)
        }
    }

    private var header: some View {
        let surface = Surface(scheme: scheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text("大きいもの")
                .font(Tokens.display(44))
                .foregroundStyle(surface.text)
            Text(
                "書類・ダウンロード・ムービーなど、ホームの見えるフォルダの中から大きいものを探します。"
                    + "探すだけでは何も消えません。"
            )
            .font(Tokens.body(13))
            .foregroundStyle(surface.text)
            .fixedSize(horizontal: false, vertical: true)
            // ここに並ぶのは自分のファイルであることがある。安全に関わるので装飾しない（§1.3）。
            Text("ここにあるものは、作り直せるとは限りません。移す前に、ほかに控えがあるか確かめてください。")
                .font(Tokens.bodyBold(13))
                .foregroundStyle(surface.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        let surface = Surface(scheme: scheme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("これより大きいもの")
                    .font(Tokens.body(12))
                    .foregroundStyle(surface.text)
                ForEach(thresholds, id: \.self) { megabytes in
                    Button(label(for: megabytes)) { model.bigMinimumMegabytes = megabytes }
                        .buttonStyle(
                            CandyButtonStyle(
                                fill: model.bigMinimumMegabytes == megabytes ? Tokens.sunbeam : surface.card)
                        )
                        .accessibilityAddTraits(
                            model.bigMinimumMegabytes == megabytes ? [.isSelected] : [])
                }
            }
            HStack(spacing: 8) {
                Button(model.bigIncludeLibrary ? "✓ ~/Library も見る" : "~/Library も見る") {
                    model.bigIncludeLibrary.toggle()
                }
                .buttonStyle(
                    CandyButtonStyle(fill: model.bigIncludeLibrary ? Tokens.sky : surface.card)
                )
                .accessibilityAddTraits(model.bigIncludeLibrary ? [.isSelected] : [])
                if !model.bigSearching {
                    Button(model.bigDone ? "もう一度さがす" : "さがす") {
                        Task { await model.findBigItems() }
                    }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                }
            }
            Text("~/Library の中は、ふだんは「片づける」とルールの担当です。ここでは既定で見ません。")
                .font(Tokens.body(11))
                .foregroundStyle(surface.text)
        }
    }

    private func label(for megabytes: Int) -> String {
        megabytes >= 1000 ? "1GB" : "\(megabytes)MB"
    }

    /// 探し終わったあとに、見えていない範囲まで含めて必ず書く。
    @ViewBuilder private var notes: some View {
        let surface = Surface(scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            if model.bigStopped {
                Text("途中でやめました。ここまでに見つかったぶんだけを出しています。")
                    .font(Tokens.bodyBold(13))
            } else if model.bigDone && model.bigItems.isEmpty, let notes = model.bigNotes {
                Text(
                    "\(label(for: model.bigMinimumMegabytes)) 以上のものは見つかりませんでした"
                        + "（\(notes.scannedEntries) 件みました）。"
                )
                .font(Tokens.body(13))
            }
            if let notes = model.bigNotes {
                if notes.truncated {
                    Text("多いため、大きいものだけを出しています。")
                        .font(Tokens.body(12))
                }
                if notes.blocked {
                    Text("読めない場所がありました。フルディスクアクセスを付けると全部見えます。")
                        .font(Tokens.body(12))
                }
                if notes.datalessSkipped {
                    Text("まだ手元に降りていないもの（iCloud）は、開かずに飛ばしました。")
                        .font(Tokens.body(12))
                }
                Text("ホームのすぐ下に直接置かれたファイルは扱いません（隔離庫へ移せる範囲の外です）。")
                    .font(Tokens.body(12))
            }
        }
        .foregroundStyle(surface.text)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 移したあとに「何が起きたか」を出す。空き容量はまだ増えていないことも書く。
    private func movedCard(_ outcome: ApplyOutcome) -> some View {
        let bytes = outcome.quarantined.reduce(Int64(0)) { $0 + $1.bytes }
        return HardCard(fill: Tokens.lime) {
            VStack(alignment: .leading, spacing: 6) {
                Text("隔離庫へうつしました \(outcome.quarantined.count) 件 / " + Format.bytes(bytes))
                    .font(Tokens.bodyBold(15))
                ForEach(outcome.quarantined.prefix(6), id: \.quarantinePath) { entry in
                    Text(
                        Format.bytes(entry.bytes) + "  "
                            + ScanItemFormat.shortPath(entry.originalPath, home: model.env.home)
                    )
                    .font(Tokens.data(11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Text(
                    "\(model.config.quarantineTtlDays) 日以内なら、隔離庫から元の場所へ戻せます。"
                        + "空き容量が増えるのは、完全に削除したあとです。"
                )
                .font(Tokens.body(12))
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("隔離庫を見る") { model.section = .quarantine }
                        .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
                }
                if !outcome.skipped.isEmpty {
                    let grouped = Dictionary(grouping: outcome.skipped, by: \.reason)
                    ForEach(grouped.sorted { $0.value.count > $1.value.count }, id: \.key) { reason, items in
                        Text("・見送り \(SkipReason.describe(reason, japanese: true)) \(items.count) 件")
                            .font(Tokens.body(12))
                    }
                }
                if !outcome.failed.isEmpty {
                    Text("失敗 \(outcome.failed.count) 件（履歴に記録しています）")
                        .font(Tokens.bodyBold(12))
                }
            }
            .foregroundStyle(Tokens.ink)
            .padding(18)
        }
    }
}

/// 見つけた 1 件。大きさ・何のかたまりか・いつから触っていないか・消すとどうなるかを 1 枚に載せる。
struct BigItemCard: View {
    @Environment(\.colorScheme) private var scheme
    let item: BigItem
    let selected: Bool
    let home: String
    let onToggle: () -> Void
    let onInspect: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HardCard(fill: selected ? Tokens.lime : Tokens.paper) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(get: { selected }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(item.name) をえらぶ")
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(Format.bytes(item.bytes))
                            .font(Tokens.weightedData(22, bytes: item.bytes))
                        BigGroupChip(group: item.group, marker: item.marker)
                    }
                    Text(item.name)
                        .font(Tokens.bodyBold(15))
                    Text(ScanItemFormat.shortPath(item.path, home: home))
                        .font(Tokens.data(11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(facts)
                        .font(Tokens.body(11))
                    // 「消すとどうなるか」は装飾しない（§1.3）。
                    Text(item.adviceJa)
                        .font(Tokens.body(12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Tokens.ink)
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Button("なかを見る", action: onInspect)
                        .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
                    Button("Finder で見る", action: onReveal)
                        .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
                }
            }
            .padding(14)
        }
    }

    /// 数字には必ず意味を添える（§1.2）。
    private var facts: String {
        var parts: [String] = []
        if item.isDirectory { parts.append("\(item.fileCount) ファイル") }
        parts.append(ageText)
        return parts.joined(separator: " ・ ")
    }

    private var ageText: String {
        guard let days = item.ageDays() else { return "最後にさわった日は分かりません" }
        if days >= 365 { return "\(days / 365) 年以上さわっていません" }
        if days >= 30 { return "\(days / 30) か月さわっていません" }
        if days == 0 { return "今日さわりました" }
        return "\(days) 日前にさわりました"
    }
}

/// まとめかたのチップ。色だけで伝えず、必ず文字を併記する（§1.2）。
struct BigGroupChip: View {
    @Environment(\.colorScheme) private var scheme
    let group: BigItemGroup
    let marker: String?

    private var fill: Color {
        switch group {
        case .bundle: Tokens.grape
        case .parts: Tokens.sky
        case .file: Tokens.sunbeam
        }
    }

    private var textColor: Color { group == .bundle ? Tokens.paper : Tokens.ink }

    var body: some View {
        let surface = Surface(scheme: scheme)
        let label = marker.map { "\(group.labelJa)・\($0)" } ?? group.labelJa
        return Text(label)
            .font(Tokens.data(11))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    Capsule().fill(surface.keyline)
                        .offset(x: Tokens.chipShadowOffset, y: Tokens.chipShadowOffset)
                    Capsule().fill(fill)
                    Capsule().strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth)
                }
            )
            .accessibilityLabel("まとめかた: " + label)
    }
}

/// 押す前に、失うものと戻せる期限を平文で見せる。
struct BigConfirmSheet: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        let surface = Surface(scheme: scheme)
        let items = model.selectedBigItems
        let expires = Date().addingTimeInterval(TimeInterval(model.config.quarantineTtlDays) * 86_400)
        return VStack(alignment: .leading, spacing: 14) {
            Text("これからうつします")
                .font(Tokens.display(30))
                .foregroundStyle(surface.text)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.bytes(item.bytes) + "  " + item.name)
                                .font(Tokens.bodyBold(13))
                            Text(ScanItemFormat.shortPath(item.path, home: model.env.home))
                                .font(Tokens.data(11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(item.adviceJa)
                                .font(Tokens.body(12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(surface.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            // 安全に関わる 3 行。ここは跳ねさせない（§1.3）。
            VStack(alignment: .leading, spacing: 4) {
                Text("合計 " + Format.bytes(model.selectedBigBytes) + "（\(items.count) 件）")
                    .font(Tokens.bodyBold(15))
                Text("いまは消しません。同じディスクの中の隔離庫へ移すだけです。")
                    .font(Tokens.body(13))
                Text(
                    "\(dateText(expires)) までは元の場所へ戻せます。そのあとは自動で完全に削除され、戻せなくなります。"
                )
                .font(Tokens.body(13))
                Text("これはあなたのファイルであることがあります。ほかに控えがあるか、先に確かめてください。")
                    .font(Tokens.body(13))
            }
            .foregroundStyle(surface.text)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("うつす") { Task { await model.applyBigItems() } }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                Button("やめる") { model.showBigConfirmSheet = false }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(surface.background)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}
