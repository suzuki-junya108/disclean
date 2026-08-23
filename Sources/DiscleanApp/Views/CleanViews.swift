import DiscleanKit
import SwiftUI

struct ScanningView: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("しらべています")
                .font(Tokens.display(44))
                .foregroundStyle(Surface(scheme: scheme).text)
            Text(model.scanProgressLabel)
                .font(Tokens.body())
                .foregroundStyle(Surface(scheme: scheme).text)
            ProgressView().progressViewStyle(.linear)
            Text("読み取りだけを行います。この間、何も消えません。")
                .font(Tokens.body(12))
                .foregroundStyle(Surface(scheme: scheme).text)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResultListView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AppModel

    var body: some View {
        let surface = Surface(scheme: scheme)
        let result = model.scanResult
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let result, result.readyItems.isEmpty {
                        EmptyStateView(model: model)
                    } else if let result {
                        ForEach([Tier.a, Tier.b, Tier.c], id: \.self) { tier in
                            let items = result.items.filter {
                                $0.tier == tier && ($0.state == .ready || $0.state == .blocked)
                            }
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(sectionTitle(tier))
                                        .font(Tokens.display(28))
                                        .foregroundStyle(surface.text)
                                    Text(sectionNote(tier))
                                        .font(Tokens.body(13))
                                        .foregroundStyle(surface.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                    ForEach(numbered(items), id: \.item.ruleId) { entry in
                                        ChunkView(
                                            item: entry.item,
                                            selected: model.selection.contains(entry.item.ruleId),
                                            home: model.env.home,
                                            index: entry.index,
                                            pulse: model.chainPulse,
                                            onToggle: {
                                                toggle(entry.item)
                                                // 押した塊を起点に、隣へ波が伝わる
                                                model.pulse(from: entry.index, strength: 1.2)
                                            },
                                            onInspect: { model.inspect(item: entry.item) }
                                        )
                                        .plopIn(index: entry.index)
                                    }
                                }
                            }
                        }
                    }
                    UncoveredSection(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 16) {
                HardCard(fill: Tokens.paper) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("えらんだ量")
                            .font(Tokens.data(11))
                            .foregroundStyle(Tokens.ink)
                        Text(Format.bytes(model.selectedBytes))
                            .font(Tokens.weightedData(26, bytes: model.selectedBytes))
                            .foregroundStyle(Tokens.ink)
                            .contentTransition(.numericText())
                            .jelly(on: model.selectedBytes, strength: 0.1)
                            .animation(Motion.gummy, value: model.selectedBytes)
                        Text("\(model.selectedItems.count) 件")
                            .font(Tokens.body(12))
                            .foregroundStyle(Tokens.ink)
                    }
                    .padding(16)
                    .frame(width: 200, alignment: .leading)
                }
                LeverView(enabled: !model.selectedItems.isEmpty) {
                    model.showConfirmSheet = true
                }
                Button("もう一度しらべる") {
                    Task { await model.scan() }
                }
                .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
            }
            .frame(width: 230)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("片づける")
                .font(Tokens.display(44))
                .foregroundStyle(Surface(scheme: scheme).text)
            if let capacity = model.scanResult?.capacity, let strict = capacity.strictBytes {
                Text("空き容量 " + Format.bytes(strict))
                    .font(Tokens.data(12))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }
            if let snapshots = model.scanResult?.capacity.snapshotCount, snapshots > 0 {
                Text("ローカルスナップショットが \(snapshots) 件あります。消しても空きが即時に増えないことがあります。")
                    .font(Tokens.body(12))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }
        }
    }

    /// 積み上がる順（下から何番目か）を持たせる。
    private func numbered(_ items: [ScanItem]) -> [(index: Int, item: ScanItem)] {
        items.enumerated().map { (index: $0.offset, item: $0.element) }
    }

    private func sectionTitle(_ tier: Tier) -> String {
        switch tier {
        case .a: "ふつうに消せるもの"
        case .b: "中身を見てから消すもの"
        case .c: "見るだけ（消しません）"
        }
    }

    /// 見出しだけでは伝わらない「なぜこの分け方なのか」を 1 行で足す。
    private func sectionNote(_ tier: Tier) -> String {
        switch tier {
        case .a: "作り直せるものだけです。消しても、次に使うときに自動で用意し直されます。"
        case .b: "人によっては、まだ要るものが混じります。「なかを見る」で確かめてから選んでください。"
        case .c: "ディスクリンは触りません。大きいものの置き場所を知らせるだけです。"
        }
    }

    private func toggle(_ item: ScanItem) {
        if model.selection.contains(item.ruleId) {
            model.selection.remove(item.ruleId)
        } else {
            model.selection.insert(item.ruleId)
        }
    }
}

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        HardCard(fill: Tokens.paper) {
            VStack(alignment: .leading, spacing: 10) {
                Text("片づけるものはありません")
                    .font(Tokens.display(28))
                    .foregroundStyle(Tokens.ink)
                Text("いま回収できるものは見つかりませんでした。大きいものを見るだけなら「見るだけ」の一覧を確認してください。")
                    .font(Tokens.body())
                    .foregroundStyle(Tokens.ink)
                Button("もう一度しらべる") { Task { await model.scan() } }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
            }
            .padding(20)
        }
    }
}

struct ApplyProgressView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("うつしています")
                .font(Tokens.display(44))
                .foregroundStyle(Surface(scheme: scheme).text)
            ProgressView().progressViewStyle(.linear)
            Text("同じディスクの中を移動しているだけなので、容量によらず短時間で終わります。")
                .font(Tokens.body(12))
                .foregroundStyle(Surface(scheme: scheme).text)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompletionSummaryView: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        let outcome = model.applyOutcome
        VStack(alignment: .leading, spacing: 16) {
            Text("おわりました")
                .font(Tokens.display(44))
                .foregroundStyle(Surface(scheme: scheme).text)
            HardCard(fill: Tokens.lime) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        Format.bytes(outcome?.reclaimedBytes ?? 0)
                            + (outcome?.hasUnmeasuredCommand == true ? " 以上" : "")
                    )
                    .font(Tokens.weightedData(32, bytes: outcome?.reclaimedBytes ?? 0))
                    .foregroundStyle(Tokens.ink)
                    Text("片づけました")
                        .font(Tokens.bodyBold())
                        .foregroundStyle(Tokens.ink)

                    if let moved = outcome?.quarantined, !moved.isEmpty {
                        Text(
                            "隔離庫へ移動 \(moved.count) 件 / "
                                + Format.bytes(moved.reduce(Int64(0)) { $0 + $1.bytes })
                        )
                        .font(Tokens.body(13))
                        .foregroundStyle(Tokens.ink)
                        // 「何が動いたのか」をその場で見せる。あとで隔離庫を開かなくても分かるように。
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(moved.prefix(6), id: \.quarantinePath) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(Format.bytes(entry.bytes))
                                        .font(Tokens.data(11))
                                        .frame(width: 72, alignment: .leading)
                                    Text(ScanItemFormat.shortPath(entry.originalPath, home: model.env.home))
                                        .font(Tokens.body(12))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundStyle(Tokens.ink)
                            }
                            if moved.count > 6 {
                                Text("ほか \(moved.count - 6) 件")
                                    .font(Tokens.body(11))
                                    .foregroundStyle(Tokens.ink)
                            }
                        }
                        Text("\(model.config.quarantineTtlDays) 日以内なら、そのまま元の場所に戻せます。実際に空きが増えるのは失効後です。")
                            .font(Tokens.body(12))
                            .foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let commands = outcome?.commandsRun, !commands.isEmpty {
                        let freed = commands.reduce(Int64(0)) { $0 + ($1.reclaimedBytes ?? 0) }
                        Text("外部ツールが解放 " + Format.bytes(freed) + "（取り消せません）")
                            .font(Tokens.body(13))
                            .foregroundStyle(Tokens.ink)
                        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                            Text("・\(command.ruleId)  " + Format.bytes(command.reclaimedBytes))
                                .font(Tokens.body(12))
                                .foregroundStyle(Tokens.ink)
                        }
                    }

                    if outcome?.quarantined.isEmpty == true && outcome?.commandsRun.isEmpty == true {
                        Text("動かせるものがありませんでした。対象は空だったか、条件に合いませんでした。")
                            .font(Tokens.body(12))
                            .foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            if let skipped = outcome?.skipped, !skipped.isEmpty {
                let grouped = Dictionary(grouping: skipped, by: \.reason)
                VStack(alignment: .leading, spacing: 4) {
                    Text("今回は見送り \(skipped.count) 件")
                        .font(Tokens.bodyBold(13))
                    ForEach(grouped.sorted { $0.value.count > $1.value.count }, id: \.key) { reason, items in
                        Text("・\(SkipReason.describe(reason, japanese: true)) \(items.count) 件")
                            .font(Tokens.body(12))
                    }
                }
                .foregroundStyle(Surface(scheme: scheme).text)
            }
            if let failed = outcome?.failed, !failed.isEmpty {
                Text("失敗 \(failed.count) 件（履歴に記録しています）")
                    .font(Tokens.bodyBold(13))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }
            if let moved = outcome?.quarantined, !moved.isEmpty, !model.purgedLastRun,
                !model.lastRunUndone
            {
                let bytes = moved.reduce(Int64(0)) { $0 + $1.bytes }
                VStack(alignment: .leading, spacing: 6) {
                    Text("空き容量は、まだ増えていません")
                        .font(Tokens.bodyBold(14))
                    Text(
                        "隔離庫は同じディスクの中にあります。\(model.config.quarantineTtlDays) 日たてば自動で空きますが、"
                            + "いま空けることもできます（戻せなくなります）。"
                    )
                    .font(Tokens.body(12))
                    .fixedSize(horizontal: false, vertical: true)
                    Button("いま完全に削除して " + Format.bytes(bytes) + " を空ける") {
                        model.purgeLastRun()
                    }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.tomato))
                }
                .foregroundStyle(Surface(scheme: scheme).text)
            }

            if model.lastRunUndone {
                Text("元に戻しました。片づける前と同じ状態です。")
                    .font(Tokens.bodyBold(14))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }

            if model.purgedLastRun {
                Text("完全に削除しました。空き容量に反映されています。")
                    .font(Tokens.bodyBold(14))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }

            HStack(spacing: 12) {
                Button("隔離庫を見る") { model.section = .quarantine }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
                Button("もう一度しらべる") { Task { await model.scan() } }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PermissionGuideView: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        HardCard(fill: Tokens.sunbeam) {
            VStack(alignment: .leading, spacing: 8) {
                Text("フルディスクアクセスが未付与です")
                    .font(Tokens.bodyBold(15))
                    .foregroundStyle(Tokens.ink)
                Text("この状態でも片づけは動きます。ゴミ箱・ダウンロード・書類・デスクトップの大きさだけが測れません。")
                    .font(Tokens.body(13))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("システム設定を開く") { model.openFullDiskAccessSettings() }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
            }
            .padding(16)
        }
        .padding(.bottom, 16)
    }
}

/// S-36 まだ見ていない大きな場所。ルールをいくら足しても世の中すべては網羅できないため、
/// 「見えていないこと」自体を見せる。ここからは消せない（見るだけ）。
struct UncoveredSection: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        let surface = Surface(scheme: scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text("まだ見ていない大きな場所")
                .font(Tokens.display(28))
                .foregroundStyle(surface.text)
            Text("ディスクリンのルールがどれも見ていない場所を探します。**消しません**。大きいのに知らなかったものが見つかったら、中身を確かめてください。")
                .font(Tokens.body(13))
                .foregroundStyle(surface.text)
                .fixedSize(horizontal: false, vertical: true)

            if model.uncoveredSearching {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("探しています…").font(Tokens.body(13))
                }
                .foregroundStyle(surface.text)
            } else {
                Button(model.uncoveredDone ? "もう一度さがす" : "ほかに大きな場所をさがす") {
                    Task { await model.findUncovered() }
                }
                .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
            }

            if model.uncoveredDone && model.uncovered.isEmpty {
                Text("200MB 以上で、ルールの外にある場所は見つかりませんでした。")
                    .font(Tokens.body(13))
                    .foregroundStyle(surface.text)
            }

            ForEach(Array(model.uncovered.enumerated()), id: \.element.path) { index, place in
                HardCard(fill: Tokens.paper) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Format.bytes(place.bytes))
                                .font(Tokens.weightedData(18, bytes: place.bytes))
                            Text(ScanItemFormat.shortPath(place.path, home: model.env.home))
                                .font(Tokens.data(11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(place.fileCount) ファイル")
                                .font(Tokens.body(11))
                        }
                        .foregroundStyle(Tokens.ink)
                        Spacer(minLength: 0)
                        Button("なかを見る") { model.inspect(place: place) }
                            .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                    }
                    .padding(14)
                }
                .plopIn(index: index)
            }
        }
        .padding(.top, 8)
    }
}
