import Foundation
import AppKit

/// 実行結果 1 件。
public struct ApplyOutcome: Sendable {
    public struct Moved: Sendable {
        public let ruleId: String
        public let originalPath: String
        public let quarantinePath: String
        public let bytes: Int64
    }

    public struct Skipped: Sendable {
        public let ruleId: String
        public let path: String
        public let reason: String
    }

    public struct Failed: Sendable {
        public let ruleId: String
        public let path: String
        public let error: String
    }

    public var quarantined: [Moved] = []
    public var skipped: [Skipped] = []
    public var failed: [Failed] = []
    public var commandsRun: [CommandOutcome] = []
    public var runId: String = ""
    public var expiresAt: Date?

    /// 隔離した量と、外部ツールが実際に空けた量の合計。
    public var reclaimedBytes: Int64 {
        quarantined.reduce(0) { $0 + $1.bytes } + commandsRun.reduce(0) { $0 + ($1.reclaimedBytes ?? 0) }
    }

    /// 量を測れなかった外部ツールがあるか（合計を「以上」と書くべきか）。
    public var hasUnmeasuredCommand: Bool { commandsRun.contains { $0.reclaimedBytes == nil } }
}

/// すべての破壊的操作が通る唯一の経路。入口で必ず `PathGuard` を適用する。
public struct Executor: Sendable {
    /// 人が選んだ「大きいもの」を記録するときの名前。ルール ID とぶつからない値にする。
    public static let bigItemRuleId = "big-item"

    private let env: DiscleanEnvironment
    private let config: Config
    fileprivate let guardian: PathGuard
    fileprivate let store: QuarantineStore
    fileprivate let audit: AuditLog
    private let catalogVersion: Int

    public init(env: DiscleanEnvironment, config: Config, audit: AuditLog, catalogVersion: Int) {
        self.env = env
        self.config = config
        self.guardian = PathGuard(
            home: env.home, stateDir: env.stateDir, configDir: env.configDir, excludedPaths: config.excludedPaths)
        self.store = QuarantineStore(root: env.quarantineDir)
        self.audit = audit
        self.catalogVersion = catalogVersion
    }

    /// - Parameter dryRun: 安全ガードの判定までを行い、移動・実行はしない。
    /// - Parameter onProgress: 1 件ごとに「いま何をしているか」を流す。既定は誰も見ていない。
    public func apply(
        plan: Plan, catalog: RuleCatalog, dryRun: Bool, now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        onProgress: @escaping WorkProgressHandler = ignoreProgress
    ) throws -> ApplyOutcome {
        // 記録できない削除は行わない。
        try audit.ensureWritable()

        let expiresAt = now.addingTimeInterval(TimeInterval(config.quarantineTtlDays) * 86_400)
        var index = store.loadIndex()
        var runDirectory: String?

        // 総数を先に数える。数えるのは一覧を取るだけで、中身は読まない（すぐ終わる）。
        onProgress(WorkProgress(step: .counting))
        var sink = MoveSink(tally: Tally(total: plannedCount(plan: plan, catalog: catalog)))
        sink.outcome.runId = plan.runId
        sink.outcome.expiresAt = expiresAt

        for item in plan.selected {
            if isCancelled() { break }
            guard let rule = catalog.rule(id: item.ruleId) else {
                sink.outcome.skipped.append(.init(ruleId: item.ruleId, path: "", reason: "unknown-rule"))
                continue
            }
            if let bundleIds = rule.requiresQuitApps, let running = runningApp(in: bundleIds) {
                sink.outcome.skipped.append(
                    .init(ruleId: rule.id, path: "", reason: "app-running:\(running)"))
                try audit.append(
                    record(
                        action: .apply, rule: rule, runId: plan.runId, result: .skipped,
                        detail: RecordDetail(reason: "app-running:\(running)"), now: now))
                continue
            }

            switch rule.kind {
            case .command:
                onProgress(sink.tally.report(.running, rule: rule, path: rule.command?.executable ?? ""))
                try runCommandRule(
                    rule: rule, plan: plan, dryRun: dryRun, now: now, outcome: &sink.outcome)
                sink.tally.finish(bytes: 0)
            case .directory:
                if runDirectory == nil && !dryRun {
                    runDirectory = try store.createRunDirectory(runId: plan.runId)
                }
                try moveDirectoryRule(
                    MoveContext(
                        rule: rule, item: item, plan: plan, runDirectory: runDirectory,
                        dryRun: dryRun, now: now, onProgress: onProgress),
                    sink: &sink, isCancelled: isCancelled)
            case .report:
                sink.outcome.skipped.append(.init(ruleId: rule.id, path: "", reason: "report-only"))
            }
        }

        // 人が 1 件ずつ選んだ「大きいもの」。ルールを通らないだけで、道は同じ。
        for item in plan.files {
            if isCancelled() { break }
            if runDirectory == nil && !dryRun {
                runDirectory = try store.createRunDirectory(runId: plan.runId)
            }
            try moveBigItem(
                BigMoveContext(
                    item: item, plan: plan, runDirectory: runDirectory, dryRun: dryRun, now: now,
                    onProgress: onProgress),
                sink: &sink)
        }

        if !dryRun && !sink.entries.isEmpty {
            let run = QuarantineRun(
                runId: plan.runId, createdAt: now, expiresAt: expiresAt, entries: sink.entries)
            index.runs.append(run)
            try store.saveIndex(index)
        }
        return sink.outcome
    }

    /// 1 ルール分の移動に必要な文脈（引数を増やしすぎないためのまとめ）。
    private struct MoveContext {
        let rule: Rule
        let item: ScanItem
        let plan: Plan
        let runDirectory: String?
        let dryRun: Bool
        let now: Date
        let onProgress: WorkProgressHandler
    }

    /// 移動しながら積み上がっていくもの。結果・隔離庫の記録・進みぐあいを 1 つにまとめて持ち回る。
    fileprivate struct MoveSink {
        var outcome = ApplyOutcome()
        var entries: [QuarantineEntry] = []
        var tally: Tally
    }

    private func moveDirectoryRule(
        _ context: MoveContext, sink: inout MoveSink, isCancelled: @Sendable () -> Bool
    ) throws {
        let fm = FileManager.default
        // スキャンが見せた場所と、いま動かす場所を必ず一致させる。
        // item.paths はスキャン時点の解決結果なので、そのまま使う。
        for parent in context.item.paths {
            if isCancelled() { break }
            guard let children = try? fm.contentsOfDirectory(atPath: parent) else {
                sink.outcome.failed.append(
                    .init(ruleId: context.rule.id, path: parent, error: "cannot list directory"))
                try audit.append(
                    record(
                        action: .apply, rule: context.rule, runId: context.plan.runId, result: .failed,
                        detail: RecordDetail(path: parent, reason: "cannot-list"), now: context.now))
                continue
            }
            for child in children {
                if isCancelled() { break }
                try moveChild(context, parent: parent, child: child, sink: &sink, isCancelled: isCancelled)
            }
        }
    }

    /// 対象 1 件を隔離庫へ移す。飛ばした場合も失敗した場合も、必ず 1 件として数える。
    private func moveChild(
        _ context: MoveContext, parent: String, child: String, sink: inout MoveSink,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let rule = context.rule
        let source = parent + "/" + child
        var st = stat()
        lstat(source, &st)
        let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        // ディレクトリの lstat が返すのは入れ物自身の大きさと更新時刻だけ。
        // 量も「最近使われたか」も、中身を見ないとスキャン結果と食い違う。
        // 中身を測るのが 1 件のうちで最も時間を使う。始める前に知らせる
        // （ファイルは測らないので、移すときの 1 回だけでよい）。
        if isDirectory { context.onProgress(sink.tally.report(.measuring, rule: rule, path: source)) }
        let measured =
            isDirectory ? DirectoryMeter.measure(path: source, isCancelled: isCancelled) : nil
        let bytes = measured?.bytes ?? Int64(st.st_blocks) * 512

        if let violation = guardian.validateForRemoval(
            path: source, minAgeDays: rule.minAgeDays, now: context.now,
            sameVolumeAs: context.dryRun ? nil : context.runDirectory,
            newestModification: measured?.newestModification)
        {
            sink.outcome.skipped.append(.init(ruleId: rule.id, path: source, reason: violation.rawValue))
            sink.tally.finish(bytes: 0)
            return
        }

        if context.dryRun {
            sink.outcome.quarantined.append(
                .init(ruleId: rule.id, originalPath: source, quarantinePath: "(dry-run)", bytes: bytes))
            sink.tally.finish(bytes: bytes)
            return
        }
        guard let runDirectory = context.runDirectory else {
            sink.outcome.failed.append(
                .init(ruleId: rule.id, path: source, error: "no quarantine directory"))
            sink.tally.finish(bytes: 0)
            return
        }

        let relative = rule.id + "/" + UUID().uuidString.prefix(8) + "-" + child
        let destination = runDirectory + "/" + relative
        context.onProgress(sink.tally.report(.moving, rule: rule, path: source, bytes: bytes))
        do {
            try FileManager.default.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // 監査ログに書けてから動かす（記録できない削除を作らない）。
            try audit.append(
                record(
                    action: .apply, rule: rule, runId: context.plan.runId, result: .ok,
                    detail: RecordDetail(path: source, bytes: bytes), now: context.now))
            guard rename(source, destination) == 0 else {
                let code = errno
                let reason = code == EXDEV ? "cross-volume" : String(cString: strerror(code))
                if code == EXDEV {
                    sink.outcome.skipped.append(
                        .init(ruleId: rule.id, path: source, reason: "cross-volume"))
                } else {
                    sink.outcome.failed.append(.init(ruleId: rule.id, path: source, error: reason))
                }
                sink.tally.finish(bytes: 0)
                return
            }
            sink.entries.append(
                QuarantineEntry(
                    ruleId: rule.id, originalPath: source, quarantineRelativePath: relative,
                    bytes: bytes, isDirectory: isDirectory, movedAt: context.now))
            sink.outcome.quarantined.append(
                .init(ruleId: rule.id, originalPath: source, quarantinePath: destination, bytes: bytes))
            sink.tally.finish(bytes: bytes)
        } catch let error as AuditError {
            throw error
        } catch {
            sink.outcome.failed.append(.init(ruleId: rule.id, path: source, error: "\(error)"))
            sink.tally.finish(bytes: 0)
        }
    }

    private func runCommandRule(
        rule: Rule, plan: Plan, dryRun: Bool, now: Date, outcome: inout ApplyOutcome
    ) throws {
        guard let spec = rule.command else { return }
        if let detect = rule.detect {
            let probe = CommandRunner.run(detect, timeoutSeconds: 5)
            guard probe.succeeded else {
                let reason = probe.exitCode == 127 ? "tool-not-found" : "daemon-not-running"
                outcome.skipped.append(.init(ruleId: rule.id, path: spec.executable, reason: reason))
                try audit.append(
                    record(
                        action: .commandRun, rule: rule, runId: plan.runId, result: .skipped,
                        detail: RecordDetail(reason: reason), now: now))
                return
            }
        }
        if dryRun {
            outcome.commandsRun.append(
                CommandOutcome(ruleId: rule.id, exitCode: 0, reason: "dry-run", reclaimedBytes: nil))
            return
        }

        // 実行の前後を同じ方法で測り、その差を「実際に空けた量」として報告する。
        let before = rule.measure.flatMap { CommandSizeProbe.measure($0, home: env.home) }
        let result = CommandRunner.run(spec, timeoutSeconds: rule.timeoutSeconds)
        let after = rule.measure.flatMap { CommandSizeProbe.measure($0, home: env.home) }
        var reclaimed: Int64?
        if let before, let after { reclaimed = max(0, before - after) }
        let head = String((result.standardOutput + result.standardError).prefix(CommandRunner.outputHeadLimit))
        if result.timedOut {
            outcome.failed.append(.init(ruleId: rule.id, path: spec.executable, error: "timeout"))
            try audit.append(
                record(
                    action: .commandRun, rule: rule, runId: plan.runId, result: .failed,
                    detail: RecordDetail(reason: "timeout", exitCode: Int(result.exitCode), outputHead: head),
                    now: now))
        } else if !result.succeeded && spec.expectSuccess {
            outcome.failed.append(
                .init(ruleId: rule.id, path: spec.executable, error: "exit \(result.exitCode)"))
            try audit.append(
                record(
                    action: .commandRun, rule: rule, runId: plan.runId, result: .failed,
                    detail: RecordDetail(reason: "non-zero-exit", exitCode: Int(result.exitCode), outputHead: head),
                    now: now))
        } else {
            outcome.commandsRun.append(
                CommandOutcome(
                    ruleId: rule.id, exitCode: result.exitCode, reason: nil, reclaimedBytes: reclaimed))
            try audit.append(
                record(
                    action: .commandRun, rule: rule, runId: plan.runId, result: .ok,
                    detail: RecordDetail(exitCode: Int(result.exitCode), outputHead: head), now: now))
        }
    }

    /// 隔離した項目を元のパスへ戻す。
    public func undo(
        runId: String?, now: Date = Date(), onProgress: WorkProgressHandler = ignoreProgress
    ) throws -> UndoOutcome {
        try audit.ensureWritable()
        var index = store.loadIndex()
        guard
            let runIndex = runId.flatMap({ id in index.runs.firstIndex { $0.runId == id } })
                ?? (runId == nil ? index.runs.indices.last : nil)
        else {
            throw QuarantineError.unknownRun(runId ?? "--last")
        }
        var run = index.runs[runIndex]
        let runDirectory = store.root + "/" + run.runId
        var restored: [RestoredItem] = []
        var skipped: [SkippedItem] = []
        var remaining: [QuarantineEntry] = []
        let fm = FileManager.default
        var tally = Tally(total: run.entries.count)

        for entry in run.entries {
            let source = runDirectory + "/" + entry.quarantineRelativePath
            onProgress(
                tally.report(
                    .restoring, ruleId: entry.ruleId, path: entry.originalPath, bytes: entry.bytes))
            var st = stat()
            if lstat(entry.originalPath, &st) == 0 {
                skipped.append(SkippedItem(path: entry.originalPath, reason: "destination-exists"))
                remaining.append(entry)
                tally.finish(bytes: 0)
                continue
            }
            let parent = (entry.originalPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            guard rename(source, entry.originalPath) == 0 else {
                skipped.append(SkippedItem(path: entry.originalPath, reason: String(cString: strerror(errno))))
                remaining.append(entry)
                tally.finish(bytes: 0)
                continue
            }
            restored.append(RestoredItem(path: entry.originalPath, bytes: entry.bytes))
            tally.finish(bytes: entry.bytes)
            try audit.append(
                AuditRecord(
                    ts: now, action: .undo, runId: run.runId, ruleId: entry.ruleId,
                    path: entry.originalPath, bytes: entry.bytes, result: .ok,
                    env: env, catalogVersion: catalogVersion))
        }

        run.entries = remaining
        if remaining.isEmpty {
            try? fm.removeItem(atPath: runDirectory)
            index.runs.remove(at: runIndex)
        } else {
            index.runs[runIndex] = run
        }
        try store.saveIndex(index)
        return UndoOutcome(restored: restored, skipped: skipped, runId: run.runId)
    }

    /// 何件のうち何件終わったかを数え、そのまま報せに変える小さな帳面。
    /// 進捗を出す場所すべてがこれを通るので、数え落としが起きにくい。
    struct Tally {
        let total: Int
        private(set) var completed = 0
        private(set) var bytes: Int64 = 0

        init(total: Int) {
            self.total = total
        }

        /// これから触るものを知らせる（まだ終わっていない）。
        func report(
            _ step: WorkProgress.Step, ruleId: String, path: String, bytes: Int64 = 0
        ) -> WorkProgress {
            WorkProgress(
                step: step, ruleId: ruleId, path: path, completed: completed, total: total, bytes: bytes)
        }

        func report(
            _ step: WorkProgress.Step, rule: Rule, path: String, bytes: Int64 = 0
        ) -> WorkProgress {
            report(step, ruleId: rule.id, path: path, bytes: bytes)
        }

        /// 1 件終わった。飛ばした件も失敗した件も、必ずここを通す。
        mutating func finish(bytes: Int64) {
            completed += 1
            self.bytes += bytes
        }
    }

    /// 進捗のぶんぼ（総数）。一覧を取るだけなので中身の大きさは測らない。
    private func plannedCount(plan: Plan, catalog: RuleCatalog) -> Int {
        plan.files.count
            + plan.selected.reduce(0) { sum, item in
                guard let rule = catalog.rule(id: item.ruleId) else { return sum }
                switch rule.kind {
                case .command: return sum + 1
                case .report: return sum
                case .directory:
                    return sum
                        + item.paths.reduce(0) { count, parent in
                            count + ((try? FileManager.default.contentsOfDirectory(atPath: parent))?.count ?? 0)
                        }
                }
            }
    }

    private func runningApp(in bundleIds: [String]) -> String? {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return bundleIds.first { running.contains($0) }
    }

    /// 監査ログ 1 行を組み立てる。引数が増えすぎないよう、任意項目は `Detail` にまとめる。
    private func record(
        action: AuditAction, rule: Rule, runId: String, result: ResultKind,
        detail: RecordDetail = RecordDetail(), now: Date
    ) -> AuditRecord {
        record(action: action, ruleId: rule.id, runId: runId, result: result, detail: detail, now: now)
    }

    /// ルールを持たない操作（人が選んだ「大きいもの」）用。記録の形は同じ。
    fileprivate func record(
        action: AuditAction, ruleId: String, runId: String, result: ResultKind,
        detail: RecordDetail = RecordDetail(), now: Date
    ) -> AuditRecord {
        AuditRecord(
            ts: now, action: action, runId: runId, ruleId: ruleId, path: detail.path, bytes: detail.bytes,
            result: result, reason: detail.reason, toolExitCode: detail.exitCode,
            toolOutputHead: detail.outputHead, env: env, catalogVersion: catalogVersion)
    }

    /// 監査ログの任意項目。
    fileprivate struct RecordDetail {
        var path: String?
        var bytes: Int64 = 0
        var reason: String?
        var exitCode: Int?
        var outputHead: String?
    }
}

/// 人が選んだ「大きいもの」を動かすための文脈（引数を増やしすぎないためのまとめ）。
struct BigMoveContext {
    let item: BigItem
    let plan: Plan
    let runDirectory: String?
    let dryRun: Bool
    let now: Date
    let onProgress: WorkProgressHandler
}

extension Executor {
    /// 選ばれた「大きいもの」1 件を隔離庫へ移す。
    ///
    /// ルール経由と違うのは「何を動かすか」を人が決めた点だけで、
    /// 安全ガード・監査ログ・隔離庫の記録はまったく同じものを通す。
    fileprivate func moveBigItem(_ context: BigMoveContext, sink: inout MoveSink) throws {
        let item = context.item
        let plan = context.plan
        let dryRun = context.dryRun
        let now = context.now
        let ruleId = Executor.bigItemRuleId
        context.onProgress(sink.tally.report(.moving, ruleId: ruleId, path: item.path, bytes: item.bytes))

        // 量は選んだ時点のものではなく、いまの実体で測り直す（表示と実際をずらさない）。
        let measured = DirectoryMeter.measure(path: item.path)
        let bytes = measured.bytes

        if let violation = guardian.validateForRemoval(
            path: item.path, minAgeDays: nil, now: now,
            sameVolumeAs: dryRun ? nil : context.runDirectory,
            newestModification: measured.newestModification)
        {
            sink.outcome.skipped.append(
                .init(ruleId: ruleId, path: item.path, reason: violation.rawValue))
            try audit.append(
                record(
                    action: .apply, ruleId: ruleId, runId: plan.runId, result: .skipped,
                    detail: RecordDetail(path: item.path, reason: violation.rawValue), now: now))
            sink.tally.finish(bytes: 0)
            return
        }

        if dryRun {
            sink.outcome.quarantined.append(
                .init(ruleId: ruleId, originalPath: item.path, quarantinePath: "(dry-run)", bytes: bytes))
            sink.tally.finish(bytes: bytes)
            return
        }
        guard let runDirectory = context.runDirectory else {
            sink.outcome.failed.append(
                .init(ruleId: ruleId, path: item.path, error: "no quarantine directory"))
            sink.tally.finish(bytes: 0)
            return
        }

        let relative = ruleId + "/" + UUID().uuidString.prefix(8) + "-" + item.name
        let destination = runDirectory + "/" + relative
        do {
            try FileManager.default.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // 記録できてから動かす。順序はルール経由とそろえる。
            try audit.append(
                record(
                    action: .apply, ruleId: ruleId, runId: plan.runId, result: .ok,
                    detail: RecordDetail(path: item.path, bytes: bytes), now: now))
            guard rename(item.path, destination) == 0 else {
                let code = errno
                let reason = code == EXDEV ? "cross-volume" : String(cString: strerror(code))
                if code == EXDEV {
                    sink.outcome.skipped.append(
                        .init(ruleId: ruleId, path: item.path, reason: "cross-volume"))
                } else {
                    sink.outcome.failed.append(.init(ruleId: ruleId, path: item.path, error: reason))
                }
                sink.tally.finish(bytes: 0)
                return
            }
            sink.entries.append(
                QuarantineEntry(
                    ruleId: ruleId, originalPath: item.path, quarantineRelativePath: relative,
                    bytes: bytes, isDirectory: item.isDirectory, movedAt: now))
            sink.outcome.quarantined.append(
                .init(ruleId: ruleId, originalPath: item.path, quarantinePath: destination, bytes: bytes))
            sink.tally.finish(bytes: bytes)
        } catch let error as AuditError {
            throw error
        } catch {
            sink.outcome.failed.append(.init(ruleId: ruleId, path: item.path, error: "\(error)"))
            sink.tally.finish(bytes: 0)
        }
    }
}

/// 外部コマンド型ルールの実行結果 1 件。
public struct CommandOutcome: Sendable {
    public let ruleId: String
    public let exitCode: Int32
    public let reason: String?
    /// 実行の前後を測った差。測れなかった場合は nil（0 と区別する）。
    public let reclaimedBytes: Int64?
}

/// 復元した項目 1 件。
public struct RestoredItem: Sendable {
    public let path: String
    public let bytes: Int64
}

/// 復元できずに隔離庫へ残した項目 1 件。
public struct SkippedItem: Sendable {
    public let path: String
    public let reason: String
}

/// undo 1 回分の結果。
public struct UndoOutcome: Sendable {
    public let restored: [RestoredItem]
    public let skipped: [SkippedItem]
    public let runId: String
}
