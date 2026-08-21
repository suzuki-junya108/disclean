import Foundation
import DiscleanKit

/// S-06 実行確認プロンプト。
struct ConfirmPrompt {
    let out: Output

    func confirm(plan: Plan, context: Context) -> Bool {
        let movable = plan.selected.filter(\.undoable)
        let external = plan.selected.filter { !$0.undoable }

        out.print()
        out.print(out.styled(out.japanese ? "これから片づけます:" : "About to clean up:", .bold))
        if !movable.isEmpty {
            out.print(
                out.japanese
                    ? "  隔離庫へ移すもの \(movable.count) 件（戻せます）"
                    : "  moved to quarantine: \(movable.count) items (undoable)")
        }
        if !external.isEmpty {
            out.print(
                out.japanese
                    ? "  外部ツールに任せるもの \(external.count) 件（戻せません）"
                    : "  handed to external tools: \(external.count) items (NOT undoable)")
        }
        for item in plan.selected {
            let undo =
                item.undoable
                ? ""
                : out.styled(out.japanese ? "  ← 取り消せません" : "  <- not undoable", .yellow)
            out.print("  \(item.ruleId)  \(Output.bytes(item.bytes))  \(item.title)\(undo)")
            out.print(out.styled("    \(item.whatIsLost)", .dim))
        }
        out.print()
        out.print(
            out.japanese
                ? "合計 \(Output.bytes(plan.totalBytes)) / 隔離庫 \(context.env.quarantineDir)"
                : "total \(Output.bytes(plan.totalBytes)) / quarantine \(context.env.quarantineDir)")
        let expires = Date().addingTimeInterval(TimeInterval(context.config.quarantineTtlDays) * 86_400)
        out.print(
            out.japanese
                ? "失効 \(Output.date(expires))（それまでは disclean undo で戻せます）"
                : "expires \(Output.date(expires)) (undo any time before that)")
        if plan.hasIrreversible {
            out.print(
                out.styled(
                    out.japanese
                        ? "※ 外部ツールに任せる項目は取り消せません。"
                        : "note: items handled by external tools cannot be undone.",
                    .yellow))
        }
        out.print()
        out.print(out.japanese ? "続けるには yes と入力してください（--yes で省略可）: " : "type yes to continue: ")
        guard let line = readLine(strippingNewline: true) else { return false }
        return line.trimmingCharacters(in: .whitespaces).lowercased() == "yes"
    }
}

/// S-07 実行結果サマリ。
struct ApplyRenderer {
    let out: Output

    func render(outcome: ApplyOutcome, delta: Int64, dryRun: Bool) {
        out.print()
        if dryRun {
            out.print(out.styled(out.japanese ? "[dry-run] 実際には移動していません" : "[dry-run] nothing moved", .yellow))
        }
        let quarantinedBytes = outcome.quarantined.reduce(Int64(0)) { $0 + $1.bytes }
        let commandBytes = outcome.commandsRun.reduce(Int64(0)) { $0 + ($1.reclaimedBytes ?? 0) }
        let approx = outcome.hasUnmeasuredCommand ? (out.japanese ? " 以上" : " or more") : ""

        out.print(
            out.styled(
                out.japanese
                    ? "片づけました: \(Output.bytes(outcome.reclaimedBytes))\(approx)"
                    : "reclaimed: \(Output.bytes(outcome.reclaimedBytes))\(approx)",
                .green))

        if !outcome.quarantined.isEmpty {
            out.print(
                out.japanese
                    ? "  隔離庫へ移動: \(outcome.quarantined.count) 件 / \(Output.bytes(quarantinedBytes))"
                    : "  moved to quarantine: \(outcome.quarantined.count) items / \(Output.bytes(quarantinedBytes))")
        }

        if !outcome.commandsRun.isEmpty {
            out.print(
                out.japanese
                    ? "  外部ツールが解放: \(Output.bytes(commandBytes))（取り消せません）"
                    : "  freed by external tools: \(Output.bytes(commandBytes)) (not undoable)")
            for command in outcome.commandsRun {
                let amount = Output.bytes(command.reclaimedBytes, japanese: out.japanese)
                out.print(out.styled("    \(command.ruleId): \(amount)", .dim))
            }
        }

        if outcome.quarantined.isEmpty && outcome.commandsRun.isEmpty && !dryRun {
            out.print(
                out.japanese
                    ? "動かせるものがありませんでした。対象が空か、条件に合いませんでした。"
                    : "nothing to move: targets were empty or did not meet the conditions.")
        }

        if !outcome.skipped.isEmpty {
            // 理由ごとにまとめる。1 件ずつ並べても、何が起きたかは伝わらない。
            let grouped = Dictionary(grouping: outcome.skipped, by: \.reason)
            out.print(
                out.styled(
                    out.japanese
                        ? "今回は見送り: \(outcome.skipped.count) 件"
                        : "left as-is: \(outcome.skipped.count) items",
                    .dim))
            for (reason, items) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
                let label = SkipReason.describe(reason, japanese: out.japanese)
                out.print(out.styled("  \(label): \(items.count) 件", .dim))
            }
        }
        if !outcome.failed.isEmpty {
            out.print(
                out.styled(
                    out.japanese ? "失敗 \(outcome.failed.count) 件:" : "failed \(outcome.failed.count):", .red))
            for failure in outcome.failed.prefix(10) {
                out.print(out.styled("  \(failure.ruleId): \(failure.error) \(failure.path)", .red))
            }
        }
        out.print(
            out.styled(
                out.japanese
                    ? "空き容量の変化（参考）: \(Output.bytes(delta))"
                    : "free space delta (reference): \(Output.bytes(delta))",
                .dim))
        if let expiresAt = outcome.expiresAt, !outcome.quarantined.isEmpty, !dryRun {
            out.print(
                out.japanese
                    ? "\(Output.date(expiresAt)) までは戻せます: disclean undo \(outcome.runId)"
                    : "undo until \(Output.date(expiresAt)): disclean undo \(outcome.runId)")
            out.print(
                out.styled(
                    out.japanese
                        ? "実際に空きが増えるのは失効後です。すぐ空けるなら disclean purge --run \(outcome.runId)"
                        : "space is freed after expiry; to free now run disclean purge --run \(outcome.runId)",
                    .dim))
        }
    }
}
