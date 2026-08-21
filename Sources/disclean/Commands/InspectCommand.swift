import ArgumentParser
import DiscleanKit
import Foundation

/// 「何が入っているのか」をファイル単位で見る。読み取りだけを行う。
struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "対象の中身をファイル単位で見る（読み取りだけ）")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "見たいルール ID（例 uv-cache）") var ruleId: String?
    @Option(name: .long, help: "隔離した run の中身を見る") var run: String?
    @Option(name: .long, help: "この場所の中を見る（ホーム配下と隔離庫のみ）") var path: String?
    @Option(name: .long, help: "何件まで見せるか") var limit: Int = FileInventory.defaultLimit

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        guard ruleId != nil || run != nil || path != nil else {
            throw fail(.argumentError, "inspect: specify <ruleId>, --run <runID> or --path <path>")
        }

        if let path {
            try showPath(path, context: context)
            return
        }
        if let run {
            try showRun(run, context: context)
            return
        }
        try showRule(ruleId ?? "", context: context)
    }

    // MARK: - ルール

    private func showRule(_ id: String, context: Context) throws {
        guard let rule = context.catalog.rules.first(where: { $0.id == id }) else {
            throw fail(.argumentError, "inspect: unknown rule \"\(id)\"")
        }
        let guardian = PathGuard(
            home: context.env.home, stateDir: context.env.stateDir, configDir: context.env.configDir,
            excludedPaths: context.config.excludedPaths)
        let resolved = RulePaths.resolve(rule, home: context.env.home, guardian: guardian)
        let inventory = FileInventory.list(paths: resolved.paths, limit: limit)

        let japanese = context.out.japanese
        let title = japanese ? rule.titleJa : rule.title
        let fate: String
        if rule.kind == .command {
            fate =
                japanese
                ? "実行すると: 外部ツールが消します（戻せません）"
                : "on apply: an external tool deletes this (cannot be undone)"
        } else {
            fate =
                japanese
                ? "実行すると: 隔離庫へ移します（\(context.config.quarantineTtlDays) 日間は戻せます）"
                : "on apply: moved to quarantine (undoable for \(context.config.quarantineTtlDays) days)"
        }

        if options.json {
            JSONOut.emit([
                "command": "inspect",
                "target": [
                    "kind": "rule", "ruleId": rule.id, "title": rule.title,
                    "titleJa": rule.titleJa, "undoable": rule.kind != .command,
                    "paths": resolved.paths,
                    "whatIsLost": rule.whatIsLost,
                    "whatIsLostJa": rule.whatIsLostJa,
                ],
                "entries": entriesJSON(inventory),
                "totals": totalsJSON(inventory),
            ])
            return
        }

        context.out.print(context.out.styled(title, .bold))
        for target in resolved.paths {
            context.out.print(context.out.styled("  " + target, .cyan))
        }
        if resolved.paths.isEmpty {
            context.out.print(japanese ? "  （対象の場所が見つかりません）" : "  (no target path)")
        }
        context.out.print(fate)
        let lost = japanese ? rule.whatIsLostJa : rule.whatIsLost
        context.out.print((japanese ? "なくなるもの: " : "what is lost: ") + lost)
        printInventory(inventory, context: context)
    }

    // MARK: - 隔離した run

    private func showRun(_ runId: String, context: Context) throws {
        let store = QuarantineStore(root: context.env.quarantineDir)
        guard let target = store.loadIndex().runs.first(where: { $0.runId == runId }) else {
            throw fail(.argumentError, "inspect: unknown run id \"\(runId)\"")
        }
        let japanese = context.out.japanese

        if options.json {
            JSONOut.emit([
                "command": "inspect",
                "target": [
                    "kind": "run", "runId": target.runId,
                    "expiresAt": JSONIO.string(from: target.expiresAt),
                    "bytes": target.totalBytes, "itemCount": target.entries.count,
                ],
                "items": target.entries.map { entry in
                    let quarantined =
                        context.env.quarantineDir + "/" + target.runId + "/"
                        + entry.quarantineRelativePath
                    let inventory = FileInventory.list(paths: [quarantined], limit: limit)
                    return [
                        "ruleId": entry.ruleId,
                        "originalPath": entry.originalPath,
                        "quarantinePath": quarantined,
                        "bytes": entry.bytes,
                        "entries": entriesJSON(inventory),
                        "totals": totalsJSON(inventory),
                    ] as [String: Any]
                },
            ])
            return
        }

        let days = max(0, Int(ceil(target.expiresAt.timeIntervalSinceNow / 86_400)))
        context.out.print(
            context.out.styled(
                (japanese ? "隔離庫の " : "quarantine run ") + target.runId, .bold))
        context.out.print(
            japanese
                ? "\(target.entries.count) 件 / \(Output.bytes(target.totalBytes))・あと \(days) 日で自動削除"
                : "\(target.entries.count) items / \(Output.bytes(target.totalBytes)) · auto-deleted in \(days) days")
        for entry in target.entries {
            let quarantined =
                context.env.quarantineDir + "/" + target.runId + "/"
                + entry.quarantineRelativePath
            context.out.print("")
            context.out.print(
                context.out.styled(
                    "  " + Output.bytes(entry.bytes) + "  " + entry.ruleId, .bold))
            context.out.print(
                (japanese ? "  元の場所 " : "  original ") + entry.originalPath)
            let inventory = FileInventory.list(paths: [quarantined], limit: limit)
            printInventory(inventory, context: context, indent: "  ")
        }
    }

    // MARK: - 特定の場所

    private func showPath(_ raw: String, context: Context) throws {
        let expanded = Expand.tilde(raw, home: context.env.home)
        // 読み取りだけとはいえ、この道具が見てよいのは自分が扱う範囲だけ。
        let guardian = PathGuard(
            home: context.env.home, stateDir: context.env.stateDir, configDir: context.env.configDir,
            excludedPaths: context.config.excludedPaths)
        guard guardian.canInspect(expanded, quarantineDir: context.env.quarantineDir) else {
            throw fail(.argumentError, "inspect: --path must be inside your home directory")
        }
        let inventory = FileInventory.list(paths: [expanded], limit: limit)
        if options.json {
            JSONOut.emit([
                "command": "inspect",
                "target": ["kind": "path", "path": expanded],
                "entries": entriesJSON(inventory),
                "totals": totalsJSON(inventory),
            ])
            return
        }
        context.out.print(context.out.styled(expanded, .bold))
        printInventory(inventory, context: context)
    }

    // MARK: - 整形

    private func printInventory(_ inventory: Inventory, context: Context, indent: String = "") {
        let japanese = context.out.japanese
        if inventory.notFound {
            context.out.print(indent + (japanese ? "この場所はありません。" : "no such place."))
            return
        }
        context.out.print(
            indent
                + (japanese
                    ? "合計 \(Output.bytes(inventory.totalBytes)) / \(inventory.totalFiles) ファイル"
                    : "total \(Output.bytes(inventory.totalBytes)) / \(inventory.totalFiles) files"))
        if inventory.blocked {
            context.out.print(
                indent
                    + (japanese
                        ? "読めない場所があります（フルディスクアクセスが要ります）"
                        : "some places could not be read (needs Full Disk Access)"))
        }
        for entry in inventory.entries {
            let kind = japanese ? entry.kind.labelJa : entry.kind.label
            let count =
                entry.isDirectory
                ? (japanese ? "  \(entry.fileCount) ファイル" : "  \(entry.fileCount) files") : ""
            let modified = entry.modified.map { "  " + Output.date($0) } ?? ""
            context.out.print(
                indent + "  " + pad(Output.bytes(entry.bytes), 10) + pad(kind, japanese ? 14 : 14)
                    + entry.name + count + context.out.styled(modified, .dim))
        }
        if inventory.hiddenCount > 0 {
            context.out.print(
                indent
                    + (japanese
                        ? "  ほか \(inventory.hiddenCount) 件（--limit で増やせます）"
                        : "  and \(inventory.hiddenCount) more (raise --limit)"))
        }
    }

    private func entriesJSON(_ inventory: Inventory) -> [[String: Any]] {
        inventory.entries.map { entry in
            [
                "path": entry.path, "name": entry.name, "bytes": entry.bytes,
                "isDirectory": entry.isDirectory, "isSymlink": entry.isSymlink,
                "fileCount": entry.fileCount, "kind": entry.kind.rawValue,
                "modified": jsonOrNull(entry.modified.map(JSONIO.string(from:))),
            ]
        }
    }

    private func totalsJSON(_ inventory: Inventory) -> [String: Any] {
        [
            "bytes": inventory.totalBytes, "fileCount": inventory.totalFiles,
            "hiddenCount": inventory.hiddenCount, "blocked": inventory.blocked,
            "notFound": inventory.notFound,
        ]
    }

    private func pad(_ text: String, _ width: Int) -> String {
        let length = text.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
        return length >= width ? text + " " : text + String(repeating: " ", count: width - length)
    }
}
