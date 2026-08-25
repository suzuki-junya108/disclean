import DiscleanKit
import Foundation

/// `disclean big` の人向け表示。
///
/// 単なるファイルの羅列にしない。1 件ごとに「何のかたまりか」「消すとどうなるか」
/// 「いつから触っていないか」を添え、押す前に判断できる形で出す。
struct BigRenderer {
    let out: Output
    let home: String

    func render(_ result: BigItemResult) {
        let japanese = out.japanese
        out.print(
            out.styled(
                japanese
                    ? "書類の中にある大きいものです（消しません）"
                    : "the largest things in your documents (never deleted here)",
                .bold))
        out.print(
            out.styled(
                (japanese ? "見た場所: " : "looked in: ")
                    + result.roots.map(shorten).joined(separator: japanese ? "、" : ", "),
                .dim))
        out.print()

        if result.items.isEmpty {
            let megabytes = result.minimumBytes / 1024 / 1024
            out.print(
                japanese
                    ? "\(megabytes)MB 以上のものは見つかりませんでした（\(result.scannedEntries) 件みました）。"
                    : "nothing at or above \(megabytes)MB (looked at \(result.scannedEntries) entries).")
            printNotes(result)
            return
        }

        for item in result.items {
            let group = japanese ? item.group.labelJa : item.group.label
            out.print("  \(Output.bytes(item.bytes))  \(shorten(item.path))")
            var facts = [group]
            if let marker = item.marker { facts.append(marker) }
            if item.isDirectory {
                facts.append(japanese ? "\(item.fileCount) ファイル" : "\(item.fileCount) files")
            }
            facts.append(ageText(item))
            out.print(out.styled("    " + facts.joined(separator: " / "), .dim))
            out.print(out.styled("    " + item.displayAdvice(japanese: japanese), .cyan))
        }
        out.print()
        out.print(
            out.styled(
                japanese
                    ? "合計 \(Output.bytes(result.totalBytes))（\(result.items.count) 件）"
                    : "total \(Output.bytes(result.totalBytes)) (\(result.items.count) items)",
                .bold))
        printNotes(result)
    }

    /// 見つからなかった理由・見えていない範囲を必ず書く（黙って 0 件にしない）。
    private func printNotes(_ result: BigItemResult) {
        let japanese = out.japanese
        if result.interrupted {
            out.print(
                out.styled(
                    japanese
                        ? "途中でやめました。ここまでに見つかったぶんだけを出しています。"
                        : "stopped early: showing only what was found so far.", .yellow))
        }
        if result.truncated {
            out.print(
                out.styled(
                    japanese
                        ? "多いため大きいものだけを出しています（--limit で増やせます）。"
                        : "showing the largest ones only (raise --limit).", .yellow))
        }
        if result.blocked {
            out.print(
                out.styled(
                    japanese
                        ? "読めない場所がありました（フルディスクアクセスを付与すると全部見えます）"
                        : "some places could not be read (grant Full Disk Access to see everything)",
                    .yellow))
        }
        if result.datalessSkipped {
            out.print(
                out.styled(
                    japanese
                        ? "まだ手元に降りていないもの（iCloud）は、開かずに飛ばしました。"
                        : "items not downloaded yet (iCloud) were skipped without opening them.",
                    .yellow))
        }
        out.print(
            japanese
                ? "中身は disclean inspect --path <場所>、片づけるなら disclean big --move <場所> です。"
                : "look inside with `disclean inspect --path <path>`, move one with `disclean big --move <path>`.")
        out.print(
            japanese
                ? "ホームのすぐ下に直接置かれたファイルは扱いません（隔離庫へ移せる範囲の外です）。"
                : "files sitting directly in your home folder are out of scope (outside the movable range).")
    }

    private func ageText(_ item: BigItem) -> String {
        guard let days = item.ageDays() else {
            return out.japanese ? "最終更新は不明" : "last change unknown"
        }
        if out.japanese {
            if days >= 365 { return "\(days / 365) 年以上さわっていません" }
            if days >= 30 { return "\(days / 30) か月さわっていません" }
            return "\(days) 日前にさわりました"
        }
        if days >= 365 { return "untouched for \(days / 365)+ years" }
        if days >= 30 { return "untouched for \(days / 30) months" }
        return "last touched \(days) days ago"
    }

    private func shorten(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - うつす

    /// 押す前に、失うものと戻せる期限を平文で見せる。
    func confirmMove(plan: Plan, context: Context) -> Bool {
        let japanese = out.japanese
        out.print()
        out.print(
            out.styled(
                japanese ? "これから隔離庫へ移します:" : "About to move into quarantine:", .bold))
        for item in plan.files {
            out.print("  \(Output.bytes(item.bytes))  \(shorten(item.path))")
            out.print(out.styled("    " + item.displayAdvice(japanese: japanese), .dim))
        }
        let expires = Date().addingTimeInterval(TimeInterval(context.config.quarantineTtlDays) * 86_400)
        out.print()
        out.print(
            japanese
                ? "合計 \(Output.bytes(plan.totalBytes)) / 隔離庫 \(context.env.quarantineDir)"
                : "total \(Output.bytes(plan.totalBytes)) / quarantine \(context.env.quarantineDir)")
        out.print(
            out.styled(
                japanese
                    ? "\(Output.date(expires)) までは disclean undo で戻せます。そのあとは戻せません。"
                    : "undoable with `disclean undo` until \(Output.date(expires)). After that it is gone.",
                .yellow))
        out.print(
            out.styled(
                japanese
                    ? "これはあなたのファイルです。ほかに控えがあるか、先に確かめてください。"
                    : "these are your own files. Make sure a copy exists elsewhere first.",
                .yellow))
        out.print(japanese ? "続けますか？ yes と入力してください: " : "Continue? type yes: ")
        let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased()
        return answer == "yes"
    }

    func renderMove(outcome: ApplyOutcome, ttlDays: Int) {
        let japanese = out.japanese
        let moved = outcome.quarantined
        if !moved.isEmpty {
            let bytes = moved.reduce(Int64(0)) { $0 + $1.bytes }
            out.print(
                out.styled(
                    japanese
                        ? "隔離庫へ移しました \(moved.count) 件 / \(Output.bytes(bytes))"
                        : "moved \(moved.count) item(s) / \(Output.bytes(bytes)) into quarantine",
                    .bold))
            for entry in moved {
                out.print("  \(Output.bytes(entry.bytes))  \(shorten(entry.originalPath))")
            }
            out.print(
                japanese
                    ? "\(ttlDays) 日以内なら disclean undo --last で元の場所に戻せます。"
                        + "空き容量が増えるのは、完全に削除したあと（disclean purge）です。"
                    : "undo within \(ttlDays) days with `disclean undo --last`. "
                        + "Free space grows only after `disclean purge`.")
        }
        for item in outcome.skipped {
            out.print(
                out.styled(
                    (japanese ? "見送り: " : "skipped: ")
                        + shorten(item.path) + " — " + SkipReason.describe(item.reason, japanese: japanese),
                    .yellow))
        }
        for item in outcome.failed {
            out.print(
                out.styled(
                    (japanese ? "失敗: " : "failed: ") + shorten(item.path) + " — " + item.error, .red))
        }
        if moved.isEmpty && outcome.skipped.isEmpty && outcome.failed.isEmpty {
            out.print(japanese ? "動かせるものがありませんでした。" : "nothing was moved.")
        }
    }
}
