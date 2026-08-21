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
                                    ForEach(items, id: \.ruleId) { item in
                                        ChunkView(
                                            item: item,
                                            selected: model.selection.contains(item.ruleId)
                                        ) {
                                            toggle(item)
                                        }
                                    }
                                }
                            }
                        }
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
                        Text(Format.bytes(model.selectedBytes))
                            .font(Tokens.weightedData(26, bytes: model.selectedBytes))
                            .foregroundStyle(Tokens.ink)
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

    private func sectionTitle(_ tier: Tier) -> String {
        switch tier {
        case .a: "ふつうに消せるもの"
        case .b: "中身を見てから消すもの"
        case .c: "見るだけ（消しません）"
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("スキップ \(skipped.count) 件")
                        .font(Tokens.bodyBold(13))
                        .foregroundStyle(Surface(scheme: scheme).text)
                    ForEach(Array(skipped.prefix(8).enumerated()), id: \.offset) { _, skip in
                        Text("\(skip.ruleId): \(skip.reason)")
                            .font(Tokens.body(12))
                            .foregroundStyle(Surface(scheme: scheme).text)
                    }
                }
            }
            if let failed = outcome?.failed, !failed.isEmpty {
                Text("失敗 \(failed.count) 件（履歴に記録しています）")
                    .font(Tokens.bodyBold(13))
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
