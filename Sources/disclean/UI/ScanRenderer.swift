import Foundation
import DiscleanKit

/// S-03 / S-04 / S-05 のレンダラ。
struct ScanRenderer {
    let out: Output

    func render(result: ScanResult, context: Context) {
        context.printPendingNotices()
        let ready = result.readyItems
        if ready.isEmpty {
            renderEmpty(result: result)
            return
        }

        for tier in [Tier.a, Tier.b, Tier.c] {
            let items = result.items.filter { $0.tier == tier && ($0.state == .ready || $0.state == .blocked) }
            guard !items.isEmpty else { continue }
            out.print()
            let heading =
                tier == .a
                ? (out.japanese ? "A ふつうに消せるもの" : "A safe to reclaim")
                : (tier == .b
                    ? (out.japanese ? "B 中身を見てから消すもの" : "B check before reclaiming")
                    : (out.japanese ? "見るだけ（消しません）" : "look only (never deleted)"))
            out.print(out.styled(heading, .green))
            for item in items {
                let size: String
                if item.state == .blocked {
                    size = out.japanese ? "測れません" : "unmeasurable"
                } else if !item.sizeKnown {
                    // 測る方法を持たないルールだけが「実行後に判明」になる。
                    size = out.japanese ? "実行後に判明" : "known after running"
                } else {
                    size = Output.bytes(item.bytes)
                }
                let mark = item.undoable ? "" : out.styled(out.japanese ? " 取り消せません" : " not undoable", .yellow)
                out.print("  \(pad(item.ruleId, 26)) \(pad(size, 10)) \(item.title)\(mark)")
                out.print(out.styled("    \(item.whatIsLost)", .dim))
                if item.state == .blocked {
                    out.print(
                        out.styled(
                            out.japanese
                                ? "    フルディスクアクセスを付与すると測定できます"
                                : "    grant Full Disk Access to measure this",
                            .yellow))
                }
            }
        }

        out.print()
        out.divider()
        let total = Output.bytes(result.totalBytes)
        let unknown = ready.filter { !$0.sizeKnown }.count
        var totalLine =
            out.japanese
            ? "合計 \(total)（\(ready.count) 件）"
            : "total \(total) (\(ready.count) items)"
        if unknown > 0 {
            totalLine +=
                out.japanese
                ? " ＋ 実行後に判明する \(unknown) 件"
                : " + \(unknown) item(s) measured after running"
        }
        out.print(out.styled(totalLine, .bold))

        // 「候補に出ていないもの」を黙って消さない。理由ごとに件数を添える。
        let setAside = result.items.filter { $0.state == .skipped && $0.tier != .c }
        if !setAside.isEmpty {
            let grouped = Dictionary(grouping: setAside, by: { $0.reason ?? "unknown" })
            let summary =
                grouped
                .sorted { $0.value.count > $1.value.count }
                .map { "\(SkipReason.describe($0.key, japanese: out.japanese)) \($0.value.count) 件" }
                .joined(separator: " / ")
            out.print(
                out.styled(
                    (out.japanese ? "対象外: " : "not listed: ") + summary, .dim))
        }
        renderCapacity(result.capacity)
        out.print(
            out.styled(
                out.japanese
                    ? "次: disclean apply（Tier A のみが既定で選ばれます）"
                    : "next: disclean apply (tier A is selected by default)",
                .cyan))
    }

    private func renderEmpty(result: ScanResult) {
        out.print()
        out.print(out.japanese ? "回収可能な項目はありません。" : "Nothing to reclaim.")
        renderCapacity(result.capacity)
        out.print(
            out.styled(
                out.japanese
                    ? "大きいものを見るだけなら disclean report を実行してください。"
                    : "Run `disclean report` to see large items disclean never deletes.",
                .cyan))
    }

    private func renderCapacity(_ sample: CapacitySample) {
        if let strict = sample.strictBytes {
            var line = out.japanese ? "空き容量 \(Output.bytes(strict))" : "free \(Output.bytes(strict))"
            if let important = sample.importantBytes, important > strict {
                line +=
                    out.japanese
                    ? "（purgeable 込み \(Output.bytes(important))）"
                    : " (\(Output.bytes(important)) incl. purgeable)"
            }
            out.print(out.styled(line, .yellow))
        }
        if let snapshots = sample.snapshotCount, snapshots > 0 {
            out.print(
                out.styled(
                    out.japanese
                        ? "ローカルスナップショットが \(snapshots) 件あります。消しても空きが即時に増えないことがあります。"
                        : "\(snapshots) local snapshot(s) present; freed space may not appear immediately.",
                    .dim))
        }
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
