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
    private let env: DiscleanEnvironment
    private let config: Config
    private let guardian: PathGuard
    private let store: QuarantineStore
    private let audit: AuditLog
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
    public func apply(
        plan: Plan, catalog: RuleCatalog, dryRun: Bool, now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> ApplyOutcome {
        // 記録できない削除は行わない。
        try audit.ensureWritable()

        var outcome = ApplyOutcome()
        outcome.runId = plan.runId
        let expiresAt = now.addingTimeInterval(TimeInterval(config.quarantineTtlDays) * 86_400)
        outcome.expiresAt = expiresAt

        var index = store.loadIndex()
        var runEntries: [QuarantineEntry] = []
        var runDirectory: String?

        for item in plan.selected {
            if isCancelled() { break }
            guard let rule = catalog.rule(id: item.ruleId) else {
                outcome.skipped.append(.init(ruleId: item.ruleId, path: "", reason: "unknown-rule"))
                continue
            }
            if let bundleIds = rule.requiresQuitApps, let running = runningApp(in: bundleIds) {
                outcome.skipped.append(.init(ruleId: rule.id, path: "", reason: "app-running:\(running)"))
                try audit.append(
                    record(
                        action: .apply, rule: rule, runId: plan.runId, result: .skipped,
                        detail: RecordDetail(reason: "app-running:\(running)"), now: now))
                continue
            }

            switch rule.kind {
            case .command:
                try runCommandRule(rule: rule, plan: plan, dryRun: dryRun, now: now, outcome: &outcome)
            case .directory:
                if runDirectory == nil && !dryRun {
                    runDirectory = try store.createRunDirectory(runId: plan.runId)
                }
                try moveDirectoryRule(
                    MoveContext(
                        rule: rule, item: item, plan: plan, runDirectory: runDirectory,
                        dryRun: dryRun, now: now),
                    outcome: &outcome, runEntries: &runEntries, isCancelled: isCancelled)
            case .report:
                outcome.skipped.append(.init(ruleId: rule.id, path: "", reason: "report-only"))
            }
        }

        if !dryRun && !runEntries.isEmpty {
            let run = QuarantineRun(
                runId: plan.runId, createdAt: now, expiresAt: expiresAt, entries: runEntries)
            index.runs.append(run)
            try store.saveIndex(index)
        }
        return outcome
    }

    /// 1 ルール分の移動に必要な文脈（引数を増やしすぎないためのまとめ）。
    private struct MoveContext {
        let rule: Rule
        let item: ScanItem
        let plan: Plan
        let runDirectory: String?
        let dryRun: Bool
        let now: Date
    }

    private func moveDirectoryRule(
        _ context: MoveContext,
        outcome: inout ApplyOutcome, runEntries: inout [QuarantineEntry],
        isCancelled: @Sendable () -> Bool
    ) throws {
        let rule = context.rule
        let item = context.item
        let plan = context.plan
        let runDirectory = context.runDirectory
        let dryRun = context.dryRun
        let now = context.now
        let fm = FileManager.default
        for parent in item.paths {
            if isCancelled() { break }
            guard let children = try? fm.contentsOfDirectory(atPath: parent) else {
                outcome.failed.append(.init(ruleId: rule.id, path: parent, error: "cannot list directory"))
                try audit.append(
                    record(
                        action: .apply, rule: rule, runId: plan.runId, result: .failed,
                        detail: RecordDetail(path: parent, reason: "cannot-list"), now: now))
                continue
            }
            for child in children {
                if isCancelled() { break }
                let source = parent + "/" + child
                if let violation = guardian.validateForRemoval(
                    path: source, minAgeDays: rule.minAgeDays, now: now,
                    sameVolumeAs: dryRun ? nil : runDirectory)
                {
                    outcome.skipped.append(.init(ruleId: rule.id, path: source, reason: violation.rawValue))
                    continue
                }
                var st = stat()
                lstat(source, &st)
                let bytes = Int64(st.st_blocks) * 512
                let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR

                if dryRun {
                    outcome.quarantined.append(
                        .init(ruleId: rule.id, originalPath: source, quarantinePath: "(dry-run)", bytes: bytes))
                    continue
                }
                guard let runDirectory else {
                    outcome.failed.append(.init(ruleId: rule.id, path: source, error: "no quarantine directory"))
                    continue
                }
                let relative = rule.id + "/" + UUID().uuidString.prefix(8) + "-" + child
                let destination = runDirectory + "/" + relative
                do {
                    try fm.createDirectory(
                        atPath: (destination as NSString).deletingLastPathComponent,
                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    // 監査ログに書けてから動かす（記録できない削除を作らない）。
                    try audit.append(
                        record(
                            action: .apply, rule: rule, runId: plan.runId, result: .ok,
                            detail: RecordDetail(path: source, bytes: bytes), now: now))
                    guard rename(source, destination) == 0 else {
                        let code = errno
                        let reason = code == EXDEV ? "cross-volume" : String(cString: strerror(code))
                        if code == EXDEV {
                            outcome.skipped.append(.init(ruleId: rule.id, path: source, reason: "cross-volume"))
                        } else {
                            outcome.failed.append(.init(ruleId: rule.id, path: source, error: reason))
                        }
                        continue
                    }
                    runEntries.append(
                        QuarantineEntry(
                            ruleId: rule.id, originalPath: source, quarantineRelativePath: relative,
                            bytes: bytes, isDirectory: isDirectory, movedAt: now))
                    outcome.quarantined.append(
                        .init(ruleId: rule.id, originalPath: source, quarantinePath: destination, bytes: bytes))
                } catch let error as AuditError {
                    throw error
                } catch {
                    outcome.failed.append(.init(ruleId: rule.id, path: source, error: "\(error)"))
                }
            }
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
    public func undo(runId: String?, now: Date = Date()) throws -> UndoOutcome {
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

        for entry in run.entries {
            let source = runDirectory + "/" + entry.quarantineRelativePath
            var st = stat()
            if lstat(entry.originalPath, &st) == 0 {
                skipped.append(SkippedItem(path: entry.originalPath, reason: "destination-exists"))
                remaining.append(entry)
                continue
            }
            let parent = (entry.originalPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            guard rename(source, entry.originalPath) == 0 else {
                skipped.append(SkippedItem(path: entry.originalPath, reason: String(cString: strerror(errno))))
                remaining.append(entry)
                continue
            }
            restored.append(RestoredItem(path: entry.originalPath, bytes: entry.bytes))
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

    private func runningApp(in bundleIds: [String]) -> String? {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return bundleIds.first { running.contains($0) }
    }

    /// 監査ログ 1 行を組み立てる。引数が増えすぎないよう、任意項目は `Detail` にまとめる。
    private func record(
        action: AuditAction, rule: Rule, runId: String, result: ResultKind,
        detail: RecordDetail = RecordDetail(), now: Date
    ) -> AuditRecord {
        AuditRecord(
            ts: now, action: action, runId: runId, ruleId: rule.id, path: detail.path, bytes: detail.bytes,
            result: result, reason: detail.reason, toolExitCode: detail.exitCode,
            toolOutputHead: detail.outputHead, env: env, catalogVersion: catalogVersion)
    }

    /// 監査ログの任意項目。
    private struct RecordDetail {
        var path: String?
        var bytes: Int64 = 0
        var reason: String?
        var exitCode: Int?
        var outputHead: String?
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
