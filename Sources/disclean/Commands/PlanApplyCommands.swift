import ArgumentParser
import Foundation
import DiscleanKit

struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan", abstract: "何を消すかの計画を作る（まだ消しません）")

    @OptionGroup var options: GlobalOptions
    @Option(name: .long, help: "対象の Tier（A / B）。既定は A") var tier: String?
    @Option(name: .long, help: "追加で選ぶルール ID") var select: [String] = []
    @Option(name: .long, help: "選択から外すルール ID") var deselect: [String] = []
    @Flag(name: .long, help: "スキャンキャッシュを使わない") var noCache = false

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let tiers = try TierParser.parse(tier) ?? [.a]
        let scanner = Scanner(env: context.env, config: context.config)
        let result = await scanner.scan(catalog: context.catalog, tiers: [.a, .b], useCache: !noCache)
        try rejectTierCSelections(select + deselect, catalog: context.catalog)
        let plan: Plan
        do {
            plan = try Planner().plan(from: result, tiers: tiers, select: select, deselect: deselect)
        } catch let error as PlannerError {
            throw PlanFailure.from(error)
        }

        if options.json {
            JSONOut.emit([
                "command": "plan",
                "runId": plan.runId,
                "selected": plan.selected.map { ["ruleId": $0.ruleId, "bytes": $0.bytes] },
                "totals": ["bytes": plan.totalBytes, "itemCount": plan.selected.count],
            ])
        } else {
            context.printPendingNotices()
            if plan.selected.isEmpty {
                context.out.print(context.out.japanese ? "選ばれた項目はありません。" : "Nothing selected.")
            } else {
                for item in plan.selected {
                    context.out.print("  \(item.ruleId)  \(Output.bytes(item.bytes))  \(item.title)")
                }
                context.out.print(
                    context.out.styled(
                        context.out.japanese
                            ? "合計 \(Output.bytes(plan.totalBytes))（\(plan.selected.count) 件）"
                            : "total \(Output.bytes(plan.totalBytes)) (\(plan.selected.count) items)",
                        .bold))
            }
        }
    }
}

enum PlanFailure {
    static func from(_ error: PlannerError) -> Error {
        switch error {
        case .unknownRuleId(let id):
            FileHandle.standardError.write(Data("plan: unknown rule id \"\(id)\"\n".utf8))
        case .tierCSelected:
            FileHandle.standardError.write(Data("plan: tier C rules cannot be selected (report only)\n".utf8))
        }
        return fail(.argumentError)
    }
}

struct ApplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply", abstract: "選んだものを隔離庫へ移す（既定 7 日は元に戻せます）")

    @OptionGroup var options: GlobalOptions
    @Option(name: .long, help: "対象の Tier（A / B）。既定は A") var tier: String?
    @Option(name: .long, help: "追加で選ぶルール ID") var select: [String] = []
    @Option(name: .long, help: "選択から外すルール ID") var deselect: [String] = []
    @Option(name: .long, help: "このルールだけを対象にする") var rule: [String] = []
    @Flag(name: .long, help: "判定だけ行い、移動・実行はしない") var dryRun = false
    @Flag(name: .long, help: "確認プロンプトを省略する") var yes = false
    @Flag(name: .long, help: "スキャンキャッシュを使わない") var noCache = false

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let out = context.out
        let tiers = try TierParser.parse(tier) ?? [.a]
        let scanner = Scanner(env: context.env, config: context.config)
        let before = CapacityProbe(path: context.env.home).sample(includeSnapshots: false)
        let result = await scanner.scan(
            catalog: context.catalog, tiers: [.a, .b], ruleIds: Set(rule), useCache: !noCache)

        try rejectTierCSelections(select + deselect + rule, catalog: context.catalog)
        let plan: Plan
        do {
            plan = try Planner().plan(
                from: result, tiers: rule.isEmpty ? tiers : [.a, .b], select: select, deselect: deselect)
        } catch let error as PlannerError {
            throw PlanFailure.from(error)
        }

        if plan.selected.isEmpty {
            if options.json {
                JSONOut.emit([
                    "command": "apply", "runId": plan.runId, "quarantined": [], "skipped": [], "failed": [],
                    "totals": ["reclaimedBytes": 0, "itemCount": 0],
                ])
            } else {
                out.print(out.japanese ? "選ばれた項目はありません。" : "Nothing selected.")
            }
            return
        }

        let interactive = isatty(STDIN_FILENO) == 1
        if !yes && !dryRun {
            guard interactive else {
                throw fail(.argumentError, "apply: --yes is required in non-interactive mode")
            }
            guard ConfirmPrompt(out: out).confirm(plan: plan, context: context) else {
                out.print(out.japanese ? "中止しました。" : "Cancelled.")
                return
            }
        }

        let executor = Executor(
            env: context.env, config: context.config, audit: context.audit, catalogVersion: context.catalogVersion)
        let cancel = InterruptFlag.install()
        let progress = ProgressLine(out: out, home: context.env.home, quiet: options.json)
        let outcome: ApplyOutcome
        do {
            outcome = try executor.apply(
                plan: plan, catalog: context.catalog, dryRun: dryRun, isCancelled: { cancel.isSet },
                onProgress: progress.handler)
            progress.finish()
        } catch is AuditError {
            progress.finish()
            throw fail(.generalError, "audit: cannot write log (\(context.env.auditDir))")
        } catch {
            progress.finish()
            throw fail(.quarantineInconsistent, "apply: \(error)")
        }

        let after = CapacityProbe(path: context.env.home).sample(includeSnapshots: false)
        let delta = (after.strictBytes ?? 0) - (before.strictBytes ?? 0)

        report(outcome: outcome, delta: delta, out: out)

        if cancel.isSet { throw fail(.interrupted) }
        if !outcome.failed.isEmpty { throw fail(.partialFailure) }
    }

    /// 実行結果を出す。`--json` は 1 オブジェクト、そうでなければ人が読む形。
    private func report(outcome: ApplyOutcome, delta: Int64, out: Output) {
        guard options.json else {
            ApplyRenderer(out: out).render(outcome: outcome, delta: delta, dryRun: dryRun)
            return
        }
        JSONOut.emit([
            "command": "apply",
            "runId": outcome.runId,
            "dryRun": dryRun,
            "quarantined": outcome.quarantined.map {
                [
                    "ruleId": $0.ruleId, "originalPath": $0.originalPath,
                    "quarantinePath": $0.quarantinePath, "bytes": $0.bytes,
                ]
            },
            "skipped": outcome.skipped.map { ["ruleId": $0.ruleId, "path": $0.path, "reason": $0.reason] },
            "failed": outcome.failed.map { ["ruleId": $0.ruleId, "path": $0.path, "error": $0.error] },
            "commands": outcome.commandsRun.map {
                [
                    "ruleId": $0.ruleId, "exitCode": Int($0.exitCode),
                    "reclaimedBytes": jsonOrNull($0.reclaimedBytes),
                ]
            },
            "totals": ["reclaimedBytes": outcome.reclaimedBytes, "itemCount": outcome.quarantined.count],
            "capacity": ["freeSpaceDeltaBytes": delta],
            "expiresAt": jsonOrNull(outcome.expiresAt.map(JSONIO.string(from:))),
        ])
    }
}

/// Tier C は選べない。スキャン結果に現れない（測っていない）場合でも、
/// カタログを見て「選べない」と正しく伝える。
func rejectTierCSelections(_ ids: [String], catalog: RuleCatalog) throws {
    for id in ids {
        guard let rule = catalog.rule(id: id) else { continue }
        if rule.tier == .c {
            throw fail(.argumentError, "plan: tier C rules cannot be selected (report only)")
        }
    }
}
