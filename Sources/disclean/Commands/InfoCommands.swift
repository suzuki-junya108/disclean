import ArgumentParser
import Foundation
import DiscleanKit

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report", abstract: "ディスクリンが触らない大きなものを見るだけ表示する")

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let scanner = Scanner(env: context.env, config: context.config)
        let result = await scanner.scan(catalog: context.catalog, tiers: [.c])
        let items = result.items.filter { $0.tier == .c }
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }

        if options.json {
            JSONOut.emit([
                "command": "report",
                "items": items.map(JSONOut.item),
                "totals": ["bytes": total],
            ])
        } else {
            context.out.print(
                context.out.styled(
                    context.out.japanese
                        ? "ディスクリンはこれらを削除しません。"
                        : "disclean never deletes these.",
                    .bold))
            context.out.print()
            for item in items {
                let size =
                    item.state == .blocked
                    ? (context.out.japanese ? "測れません" : "unmeasurable")
                    : Output.bytes(item.bytes)
                context.out.print("  \(size)  \(item.title)")
                context.out.print(context.out.styled("    \(item.whatIsLost)", .dim))
                if let manual = item.manualSteps {
                    context.out.print(context.out.styled("    → \(manual)", .cyan))
                }
                if item.state == .blocked {
                    context.out.print(
                        context.out.styled(
                            context.out.japanese
                                ? "    フルディスクアクセスがないため測れていません"
                                : "    not measured (needs Full Disk Access)",
                            .yellow))
                }
            }
        }
        if items.allSatisfy({ $0.state == .blocked }) && !items.isEmpty {
            throw fail(.permissionDenied)
        }
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "環境を診断する（権限・外部ツール・保存先・更新・OS の変化）")

    @OptionGroup var options: GlobalOptions
    @Flag(name: .long, help: "不足しているディレクトリを作る") var initialize = false

    static let configurationOverrides: Void = ()

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let doctor = Doctor(env: context.env, config: context.config)
        if initialize { try doctor.initializeDirectories() }
        let report = doctor.run(catalog: context.catalog, updateState: context.updateState)

        if options.json {
            JSONOut.emit([
                "command": "doctor",
                "fullDiskAccess": report.fullDiskAccess,
                "tools": report.tools.map { ["name": $0.name, "found": $0.found, "version": jsonOrNull($0.version)] },
                "state": [
                    "configDir": report.configDir, "stateDir": report.stateDir, "writable": report.writable,
                    "quarantineBytes": report.quarantineBytes, "runCount": report.runCount,
                    "orphanDirectories": report.orphanDirectories,
                ],
                "update": [
                    "autoUpdate": report.autoUpdate,
                    "appliedCatalogVersion": report.appliedCatalogVersion,
                    "lastCheckedAt": jsonOrNull(report.lastCheckedAt.map(JSONIO.string(from:))),
                    "lastCheckResult": context.updateState.lastCheckResult.rawValue,
                ],
                "os": [
                    "version": report.osDrift.osVersion,
                    "build": report.osDrift.osBuild,
                    "changedSince": jsonOrNull(report.osDrift.changedSince),
                    "rulesDisabledByOS": report.osDrift.rulesDisabledByOS.map {
                        ["ruleId": $0.ruleId, "reason": $0.reason]
                    },
                    "rulesMissingAfterOSChange": report.osDrift.rulesMissingAfterOSChange.map {
                        ["ruleId": $0.ruleId, "path": $0.path]
                    },
                ],
                "warnings": report.warnings,
            ])
        } else {
            DoctorRenderer(out: context.out).render(report: report, context: context)
        }
        if !report.writable { throw fail(.quarantineInconsistent) }
        if !report.fullDiskAccess { throw fail(.permissionDenied) }
    }
}

struct RulesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules", abstract: "ルールの一覧と検証",
        subcommands: [ListRules.self, ValidateRules.self], defaultSubcommand: ListRules.self)

    struct ListRules: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "ルールを一覧する")

        @OptionGroup var options: GlobalOptions
        @Option(name: .long, help: "Tier で絞る") var tier: String?

        func run() async throws {
            let context = Context(noUpdate: options.noUpdate)
            let tiers = try TierParser.parse(tier)
            let entries = context.catalog.entries.filter { tiers?.contains($0.rule.tier) ?? true }
            if options.json {
                JSONOut.emit([
                    "command": "rules",
                    "rules": entries.map {
                        [
                            "id": $0.rule.id, "title": $0.rule.title, "tier": $0.rule.tier.rawValue,
                            "kind": $0.rule.kind.rawValue, "enabled": $0.rule.enabled, "source": $0.source.rawValue,
                        ]
                    },
                    "valid": context.catalog.errors.isEmpty,
                    "errors": context.catalog.errors.map { ["file": $0.file, "reason": $0.reason] },
                ])
            } else {
                for entry in entries {
                    context.out.print(
                        "  \(entry.rule.tier.rawValue)  \(pad(entry.rule.id, 26))  "
                            + "\(pad(entry.rule.kind.rawValue, 10))  \(entry.source.rawValue)")
                }
            }
            if !context.catalog.errors.isEmpty { throw fail(.invalidCatalog) }
        }

        private func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
        }
    }

    struct ValidateRules: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "validate", abstract: "ルール定義を検証する")

        @OptionGroup var options: GlobalOptions

        func run() async throws {
            let context = Context(noUpdate: options.noUpdate)
            let errors = context.catalog.errors
            if options.json {
                JSONOut.emit([
                    "command": "rules",
                    "valid": errors.isEmpty,
                    "errors": errors.map {
                        ["file": $0.file, "ruleId": jsonOrNull($0.ruleId), "reason": $0.reason]
                    },
                ])
            } else {
                for error in errors {
                    context.out.warn("rules: \(error.file): \(error.reason)")
                }
                context.out.print(
                    errors.isEmpty
                        ? (context.out.japanese ? "ルールはすべて有効です。" : "all rules are valid.")
                        : (context.out.japanese ? "\(errors.count) 件の問題があります。" : "\(errors.count) problem(s)."))
            }
            if !errors.isEmpty { throw fail(.invalidCatalog) }
        }
    }
}
