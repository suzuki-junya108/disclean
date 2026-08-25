import ArgumentParser
import DiscleanKit
import Foundation

/// 書類の中にある大きいものを探す。既定は読み取りだけで、`--move` を付けたときだけ動かす。
struct BigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "big",
        abstract: "書類の中の大きいものを探す（--move を付けない限り読むだけ）")

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "報告する下限（MB）") var minMegabytes: Int = 200
    @Option(name: .customLong("in"), help: "この場所だけを見る（繰り返し指定可）") var only: [String] = []
    @Flag(name: .long, help: "~/Library の中も見る") var includeLibrary = false
    @Option(name: .long, help: "何件まで見せるか") var limit: Int = BigItemScanner.defaultLimit
    @Option(name: .long, help: "この場所を隔離庫へ移す（繰り返し指定可）") var move: [String] = []
    @Flag(name: .long, help: "確認プロンプトを省略する") var yes = false

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        if !move.isEmpty {
            try await runMove(context: context)
            return
        }
        try await runSearch(context: context)
    }

    // MARK: - さがす（読むだけ）

    private func runSearch(context: Context) async throws {
        let scanner = BigItemScanner(env: context.env, config: context.config)
        let roots = try resolvedRoots(context: context, scanner: scanner)
        let minimum = Int64(max(1, minMegabytes)) * 1024 * 1024
        let cancel = InterruptFlag.install()
        let progress = ProgressLine(out: context.out, home: context.env.home, quiet: options.json)
        let result = await scanner.scan(
            roots: roots, minimumBytes: minimum, limit: max(1, limit),
            includeLibrary: includeLibrary, isCancelled: { cancel.isSet },
            onProgress: progress.handler)
        progress.finish()

        if options.json {
            JSONOut.emit([
                "command": "big",
                "items": result.items.map(BigItemJSON.item),
                "roots": result.roots,
                "totals": [
                    "bytes": result.totalBytes,
                    "itemCount": result.items.count,
                    "minimumBytes": result.minimumBytes,
                    "scannedEntries": result.scannedEntries,
                    "truncated": result.truncated,
                    "blocked": result.blocked,
                    "datalessSkipped": result.datalessSkipped,
                    "interrupted": result.interrupted,
                ],
            ])
            if cancel.isSet { throw fail(.interrupted) }
            return
        }
        BigRenderer(out: context.out, home: context.env.home).render(result)
        if cancel.isSet { throw fail(.interrupted) }
    }

    /// `--in` で渡された場所を検証する。見てよい場所でなければ、黙って外さずに止める。
    private func resolvedRoots(context: Context, scanner: BigItemScanner) throws -> [String] {
        var roots: [String] = []
        for raw in only {
            let expanded = scanner.resolve(raw)
            guard scanner.isUsableRoot(expanded) else {
                throw fail(.argumentError, "big: --in must be a folder inside your home directory (\(raw))")
            }
            roots.append(expanded)
        }
        return roots
    }

    // MARK: - うつす（隔離庫へ）

    private func runMove(context: Context) async throws {
        let out = context.out
        let scanner = BigItemScanner(env: context.env, config: context.config)
        let items = try move.map { try describe($0, context: context, scanner: scanner) }
        let plan = Planner().plan(files: items)

        let interactive = isatty(STDIN_FILENO) == 1
        if !yes {
            guard interactive else {
                throw fail(.argumentError, "big: --yes is required in non-interactive mode")
            }
            guard BigRenderer(out: out, home: context.env.home).confirmMove(plan: plan, context: context)
            else {
                out.print(out.japanese ? "中止しました。" : "Cancelled.")
                return
            }
        }

        let executor = Executor(
            env: context.env, config: context.config, audit: context.audit,
            catalogVersion: context.catalogVersion)
        let cancel = InterruptFlag.install()
        let progress = ProgressLine(out: out, home: context.env.home, quiet: options.json)
        let outcome: ApplyOutcome
        do {
            outcome = try executor.apply(
                plan: plan, catalog: context.catalog, dryRun: false, isCancelled: { cancel.isSet },
                onProgress: progress.handler)
            progress.finish()
        } catch is AuditError {
            progress.finish()
            throw fail(.generalError, "audit: cannot write log (\(context.env.auditDir))")
        } catch {
            progress.finish()
            throw fail(.quarantineInconsistent, "big: \(error)")
        }

        if options.json {
            JSONOut.emit([
                "command": "big",
                "mode": "move",
                "runId": outcome.runId,
                "quarantined": outcome.quarantined.map {
                    [
                        "originalPath": $0.originalPath, "quarantinePath": $0.quarantinePath,
                        "bytes": $0.bytes,
                    ]
                },
                "skipped": outcome.skipped.map { ["path": $0.path, "reason": $0.reason] },
                "failed": outcome.failed.map { ["path": $0.path, "error": $0.error] },
                "totals": [
                    "reclaimedBytes": outcome.reclaimedBytes, "itemCount": outcome.quarantined.count,
                ],
                "expiresAt": jsonOrNull(outcome.expiresAt.map(JSONIO.string(from:))),
            ])
        } else {
            BigRenderer(out: out, home: context.env.home)
                .renderMove(outcome: outcome, ttlDays: context.config.quarantineTtlDays)
        }
        if !outcome.failed.isEmpty { throw fail(.partialFailure) }
    }

    /// `--move` に渡された 1 件を、いまの実体から組み立てる。
    /// 存在しない・見てよい場所でない場合は、ここで止める（黙って飛ばさない）。
    private func describe(_ raw: String, context: Context, scanner: BigItemScanner) throws -> BigItem {
        let path = scanner.resolve(raw)
        guard scanner.canInspect(path) else {
            throw fail(.argumentError, "big: --move must be inside your home directory (\(raw))")
        }
        var st = stat()
        guard lstat(path, &st) == 0 else {
            throw fail(.argumentError, "big: no such path (\(raw))")
        }
        let name = (path as NSString).lastPathComponent
        let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        let measured = DirectoryMeter.measure(path: path)
        let group: BigItemGroup
        let marker: String?
        if !isDirectory {
            group = .file
            marker = nil
        } else if let bundle = BigItemMarkers.bundle(for: name) {
            group = .bundle
            marker = bundle
        } else if let parts = BigItemMarkers.parts(for: name) {
            group = .parts
            marker = parts
        } else {
            // 目印の無いフォルダは、勝手に「部品置き場」と決めつけない。
            group = .file
            marker = nil
        }
        let kind = FileKind.infer(name: name, isDirectory: isDirectory)
        let advice = BigItemMarkers.advice(group: group, marker: marker, kind: kind)
        return BigItem(
            path: path, name: name, bytes: measured.bytes, fileCount: measured.fileCount,
            isDirectory: isDirectory, modified: measured.newestModification, kind: kind,
            group: group, marker: marker, adviceJa: advice.ja, advice: advice.en)
    }
}

/// `--json` の 1 件分。
enum BigItemJSON {
    static func item(_ item: BigItem) -> [String: Any] {
        [
            "path": item.path,
            "name": item.name,
            "bytes": item.bytes,
            "fileCount": item.fileCount,
            "isDirectory": item.isDirectory,
            "kind": item.kind.rawValue,
            "group": item.group.rawValue,
            "marker": jsonOrNull(item.marker),
            "advice": item.advice,
            "adviceJa": item.adviceJa,
            "modified": jsonOrNull(item.modified.map(JSONIO.string(from:))),
        ]
    }
}
