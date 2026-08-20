import DiscleanKit
import SwiftUI

/// S-16 実行確認シート。取り消せない項目は帯で明示する。
struct ConfirmSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AppModel

    var body: some View {
        let expires = Date().addingTimeInterval(TimeInterval(model.config.quarantineTtlDays) * 86_400)
        VStack(alignment: .leading, spacing: 16) {
            Text("これから隔離庫へ移します")
                .font(Tokens.display(28))
                .foregroundStyle(Surface(scheme: scheme).text)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.selectedItems, id: \.ruleId) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.title).font(Tokens.bodyBold(14))
                                TierChip(tier: item.tier)
                                Spacer()
                                Text(ScanItemFormat.size(item))
                                    .font(Tokens.data(13))
                            }
                            Text(item.whatIsLost).font(Tokens.body(12))
                        }
                        .foregroundStyle(Surface(scheme: scheme).text)
                    }
                }
            }
            .frame(maxHeight: 240)

            if model.selectedItems.contains(where: { !$0.undoable }) {
                Text("外部ツールに任せる項目は取り消せません")
                    .font(Tokens.bodyBold(13))
                    .foregroundStyle(Tokens.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.tomato)
                    .overlay(
                        Rectangle().strokeBorder(Surface(scheme: scheme).keyline, lineWidth: Tokens.keylineWidth))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("合計 " + ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))
                    .font(Tokens.data(15))
                Text("隔離庫 \(model.env.quarantineDir)").font(Tokens.body(12))
                Text("失効 \(expires.formatted(date: .abbreviated, time: .shortened))").font(Tokens.body(12))
            }
            .foregroundStyle(Surface(scheme: scheme).text)

            HStack(spacing: 12) {
                Button("実行する") {
                    model.showConfirmSheet = false
                    Task { await model.apply() }
                }
                .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                .keyboardShortcut(.defaultAction)
                Button("やめる") { model.showConfirmSheet = false }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Surface(scheme: scheme).background)
    }
}

/// S-32 更新シート。拡大差分（消す対象が増える変更）を最上部に、装飾せず出す。
struct UpdateSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AppModel

    var body: some View {
        let diff = model.updateOutcome?.diff
        VStack(alignment: .leading, spacing: 14) {
            Text("掃除ルールの更新")
                .font(Tokens.display(28))
                .foregroundStyle(Surface(scheme: scheme).text)
            if let version = model.updateState.stagedCatalogVersion {
                Text("カタログ \(version)").font(Tokens.data(12))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }

            if let expanding = diff?.expanding, !expanding.isEmpty {
                Text("承認が必要な変更（消す対象が増えます）")
                    .font(Tokens.bodyBold(14))
                    .foregroundStyle(Surface(scheme: scheme).text)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(expanding.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.ruleId): \(entry.change.rawValue)")
                                    .font(Tokens.bodyBold(13))
                                ForEach(entry.newPaths, id: \.self) { path in
                                    Text("+ \(path)").font(Tokens.data(11))
                                }
                            }
                            .foregroundStyle(Surface(scheme: scheme).text)
                        }
                    }
                }
                .frame(maxHeight: 220)
                Text("承認するまで、これらは消える対象になりません。")
                    .font(Tokens.body(13))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }

            if let shrinking = diff?.shrinking, !shrinking.isEmpty {
                Text("消す対象が減る変更 \(shrinking.count) 件は自動で反映されます")
                    .font(Tokens.body(12))
                    .foregroundStyle(Surface(scheme: scheme).text)
            }

            HStack(spacing: 12) {
                Button("承認して適用") { Task { await model.applyStagedUpdate() } }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                Button("あとで") { model.showUpdateSheet = false }
                    .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Surface(scheme: scheme).background)
    }
}

/// S-19 隔離庫。
struct QuarantineView: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        let surface = Surface(scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            Text("隔離庫")
                .font(Tokens.display(44))
                .foregroundStyle(surface.text)
            if model.quarantineRuns.isEmpty {
                Text("隔離中の項目はありません。")
                    .font(Tokens.body())
                    .foregroundStyle(surface.text)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.quarantineRuns, id: \.runId) { run in
                        HardCard(fill: Tokens.paper) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ByteCountFormatter.string(fromByteCount: run.totalBytes, countStyle: .file))
                                        .font(Tokens.data(22))
                                    Text("\(run.entries.count) 件 / \(run.runId)")
                                        .font(Tokens.data(11))
                                    Text(
                                        "失効まで \(daysLeft(run)) 日（\(run.expiresAt.formatted(date: .abbreviated, time: .shortened))）"
                                    )
                                    .font(Tokens.body(12))
                                }
                                .foregroundStyle(Tokens.ink)
                                Spacer()
                                VStack(spacing: 8) {
                                    Button("元に戻す") { model.undo(runId: run.runId) }
                                        .buttonStyle(CandyButtonStyle(fill: Tokens.grape, textColor: Tokens.paper))
                                    Button("いま完全に削除") { model.purge(runId: run.runId) }
                                        .buttonStyle(CandyButtonStyle(fill: Tokens.tomato))
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            Button("Finder で開く") { model.openQuarantineInFinder() }
                .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.refreshQuarantine() }
    }

    /// 「あと何日戻せるか」は切り上げる（6 日と 23 時間を「6 日」と見せない）。
    private func daysLeft(_ run: QuarantineRun) -> Int {
        max(0, Int(ceil(run.expiresAt.timeIntervalSinceNow / 86_400)))
    }
}

/// S-20 履歴。
struct HistoryView: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        let surface = Surface(scheme: scheme)
        let reclaimed = model.auditRecords.filter { $0.action == .apply }.reduce(Int64(0)) { $0 + $1.bytes }
        VStack(alignment: .leading, spacing: 14) {
            Text("履歴")
                .font(Tokens.display(44))
                .foregroundStyle(surface.text)
            Text("これまでに片づけた量 " + ByteCountFormatter.string(fromByteCount: reclaimed, countStyle: .file))
                .font(Tokens.data(14))
                .foregroundStyle(surface.text)
            Table(rows) {
                TableColumn("日時") { row in
                    Text(row.record.ts.formatted(date: .abbreviated, time: .shortened)).font(Tokens.body(12))
                }
                TableColumn("操作") { row in Text(row.record.action.rawValue).font(Tokens.body(12)) }
                TableColumn("ルール") { row in Text(row.record.ruleId).font(Tokens.body(12)) }
                TableColumn("結果") { row in Text(row.record.result.rawValue).font(Tokens.body(12)) }
                TableColumn("量") { row in
                    Text(ByteCountFormatter.string(fromByteCount: row.record.bytes, countStyle: .file))
                        .font(Tokens.data(11))
                }
            }
            .frame(minHeight: 320)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.refreshHistory() }
    }

    /// `Table` は行に Identifiable を求めるため、表示用に包む。
    private var rows: [HistoryRow] {
        model.auditRecords.enumerated().map { HistoryRow(id: $0.offset, record: $0.element) }
    }
}

private struct HistoryRow: Identifiable {
    let id: Int
    let record: AuditRecord
}

/// S-21 設定（更新の扱いを含む）。
struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AppModel
    @State private var checking = false

    var body: some View {
        let surface = Surface(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("設定")
                    .font(Tokens.display(44))
                    .foregroundStyle(surface.text)

                HardCard(fill: Tokens.paper) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(
                            "隔離庫に置いておく日数: \(model.config.quarantineTtlDays) 日",
                            value: Binding(
                                get: { model.config.quarantineTtlDays },
                                set: {
                                    model.config.quarantineTtlDays = $0; model.saveConfig()
                                }),
                            in: 1...90)
                        Stepper(
                            "同時に調べる数: \(model.config.concurrency)",
                            value: Binding(
                                get: { model.config.concurrency },
                                set: {
                                    model.config.concurrency = $0; model.saveConfig()
                                }),
                            in: 1...32)
                        Button("ルールの上書きフォルダを開く") { model.openRulesFolder() }
                            .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
                    }
                    .font(Tokens.body(14))
                    .foregroundStyle(Tokens.ink)
                    .padding(18)
                }

                HardCard(fill: Tokens.paper) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "掃除ルールの更新を自動で受け取る",
                            isOn: Binding(
                                get: { model.config.autoUpdate },
                                set: {
                                    model.config.autoUpdate = $0; model.saveConfig()
                                }))
                        Text("受け取っても、消す対象が増える変更はあなたが承認するまで有効になりません。オフにすると通信そのものが起きません。")
                            .font(Tokens.body(12))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("送るのはディスクリンと macOS のバージョンだけです。ファイルの情報は送りません。")
                            .font(Tokens.body(12))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("適用中のカタログ: \(model.updateState.appliedCatalogVersion)")
                            .font(Tokens.data(12))
                        if let checked = model.updateState.lastCheckedAt {
                            Text("最終確認 \(checked.formatted(date: .abbreviated, time: .shortened))")
                                .font(Tokens.body(12))
                        }
                        Button(checking ? "確認しています…" : "いま確認する") {
                            checking = true
                            Task {
                                await model.checkForUpdates()
                                checking = false
                            }
                        }
                        .buttonStyle(CandyButtonStyle(fill: Tokens.lime))
                        .disabled(checking)
                    }
                    .font(Tokens.body(14))
                    .foregroundStyle(Tokens.ink)
                    .padding(18)
                }

                if let report = model.doctorReport {
                    HardCard(fill: Tokens.paper) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("この Mac の状態").font(Tokens.bodyBold(15))
                            Text("macOS \(report.osDrift.osVersion) (\(report.osDrift.osBuild))")
                                .font(Tokens.data(12))
                            Text("フルディスクアクセス: \(report.fullDiskAccess ? "付与済み" : "未付与")")
                                .font(Tokens.body(13))
                            if let changed = report.osDrift.changedSince {
                                Text("前回は \(changed) でした。掃除するパスが変わっている可能性があります。")
                                    .font(Tokens.body(12))
                            }
                        }
                        .foregroundStyle(Tokens.ink)
                        .padding(18)
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
        }
    }
}
