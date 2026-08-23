import ArgumentParser
import Foundation
import DiscleanKit

struct UndoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "undo", abstract: "隔離したものを元の場所へ戻す")

    @OptionGroup var options: GlobalOptions
    @Argument(help: "戻す run ID") var runId: String?
    @Flag(name: .long, help: "直近の run を対象にする") var last = false

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        guard runId != nil || last else {
            throw fail(.argumentError, "undo: specify <runID> or --last")
        }
        let executor = Executor(
            env: context.env, config: context.config, audit: context.audit, catalogVersion: context.catalogVersion)
        let progress = ProgressLine(out: context.out, home: context.env.home, quiet: options.json)
        do {
            let result = try executor.undo(runId: last ? nil : runId, onProgress: progress.handler)
            progress.finish()
            let restoredBytes = result.restored.reduce(Int64(0)) { $0 + $1.bytes }
            if options.json {
                JSONOut.emit([
                    "command": "undo",
                    "runId": result.runId,
                    "restored": result.restored.map { ["originalPath": $0.path, "bytes": $0.bytes] },
                    "skipped": result.skipped.map { ["originalPath": $0.path, "reason": $0.reason] },
                    "totals": ["bytes": restoredBytes, "itemCount": result.restored.count],
                ])
            } else {
                context.out.print(
                    context.out.styled(
                        context.out.japanese
                            ? "戻しました: \(result.restored.count) 件 / \(Output.bytes(restoredBytes))"
                            : "restored: \(result.restored.count) items / \(Output.bytes(restoredBytes))",
                        .green))
                for skip in result.skipped {
                    context.out.print(context.out.styled("  \(skip.reason): \(skip.path)", .yellow))
                }
            }
            if !result.skipped.isEmpty && result.restored.isEmpty {
                throw fail(.partialFailure)
            }
        } catch let error as QuarantineError {
            progress.finish()
            if case .unknownRun(let id) = error {
                throw fail(.argumentError, "undo: unknown run id \"\(id)\"")
            }
            throw fail(.quarantineInconsistent, "undo: \(error)")
        }
    }
}

struct PurgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "purge", abstract: "隔離庫から完全に削除する（戻せなくなります）")

    @OptionGroup var options: GlobalOptions
    @Flag(name: .long, help: "失効前のものも含めて全部消す") var all = false
    @Option(name: .long, help: "この run だけを消す") var run: String?
    @Flag(name: .long, help: "確認プロンプトを省略する") var force = false

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let store = QuarantineStore(root: context.env.quarantineDir)

        let orphans = store.orphanDirectories()
        if !orphans.isEmpty {
            for orphan in orphans {
                context.out.warn("purge: orphan directory \(orphan)")
            }
            throw fail(.quarantineInconsistent)
        }

        var purged: [PurgedRun] = context.expiredPurges
        if all || run != nil {
            if !force && isatty(STDIN_FILENO) == 1 {
                context.out.print(
                    context.out.japanese
                        ? "完全に削除します（戻せません）。続けるには yes と入力してください: "
                        : "This deletes permanently. Type yes to continue: ")
                guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
                    context.out.print(context.out.japanese ? "中止しました。" : "Cancelled.")
                    return
                }
            }
            let progress = ProgressLine(out: context.out, home: context.env.home, quiet: options.json)
            do {
                purged += try store.purge(runId: run, all: all, onProgress: progress.handler)
                progress.finish()
            } catch QuarantineError.unknownRun(let id) {
                progress.finish()
                throw fail(.argumentError, "purge: unknown run id \"\(id)\"")
            }
        }

        let total = purged.reduce(Int64(0)) { $0 + $1.bytes }
        if options.json {
            JSONOut.emit([
                "command": "purge",
                "purged": purged.map { ["runId": $0.runId, "bytes": $0.bytes, "itemCount": $0.itemCount] },
                "totals": ["bytes": total],
            ])
        } else {
            context.out.print(
                context.out.japanese
                    ? "完全に削除しました: \(purged.count) run / \(Output.bytes(total))"
                    : "purged: \(purged.count) run(s) / \(Output.bytes(total))")
        }
    }
}

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history", abstract: "これまでの操作の記録を見る")

    @OptionGroup var options: GlobalOptions
    @Option(name: .long, help: "この日時以降（ISO8601）") var since: String?
    @Option(name: .long, help: "この日時まで（ISO8601）") var until: String?
    @Option(name: .long, help: "操作の種類で絞る（apply / undo / purge / commandRun）") var action: String?

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let sinceDate = since.flatMap(JSONIO.date(from:))
        let untilDate = until.flatMap(JSONIO.date(from:))
        if since != nil && sinceDate == nil {
            throw fail(.argumentError, "history: invalid --since")
        }
        if until != nil && untilDate == nil {
            throw fail(.argumentError, "history: invalid --until")
        }
        var filterAction: AuditAction?
        if let action {
            guard let parsed = AuditAction(rawValue: action) else {
                throw fail(.argumentError, "history: unknown --action \(action)")
            }
            filterAction = parsed
        }

        let (records, corrupt) = context.audit.read(since: sinceDate, until: untilDate, action: filterAction)
        let bytes = records.filter { $0.action == .apply }.reduce(Int64(0)) { $0 + $1.bytes }

        if options.json {
            JSONOut.emit([
                "command": "history",
                "records": records.map { record in
                    var dict: [String: Any] = [
                        "ts": JSONIO.string(from: record.ts), "action": record.action.rawValue,
                        "runId": record.runId, "ruleId": record.ruleId, "bytes": record.bytes,
                        "result": record.result.rawValue, "osBuild": record.osBuild,
                        "catalogVersion": record.catalogVersion,
                    ]
                    if let path = record.path { dict["path"] = path }
                    if let reason = record.reason { dict["reason"] = reason }
                    return dict
                },
                "totals": ["bytes": bytes, "recordCount": records.count],
                "errors": corrupt.map { ["line": $0] },
            ])
        } else {
            for record in records.prefix(200) {
                let mark = record.result == .ok ? "ok" : record.result.rawValue
                context.out.print(
                    "\(Output.date(record.ts))  \(pad(record.action.rawValue, 12))  \(pad(mark, 8))  "
                        + "\(pad(record.ruleId, 24))  \(Output.bytes(record.bytes))")
            }
            context.out.print(
                context.out.styled(
                    context.out.japanese
                        ? "\(records.count) 件 / 回収 \(Output.bytes(bytes))"
                        : "\(records.count) records / reclaimed \(Output.bytes(bytes))",
                    .bold))
        }
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
