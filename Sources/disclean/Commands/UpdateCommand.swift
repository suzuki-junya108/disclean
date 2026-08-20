import ArgumentParser
import Foundation
import DiscleanKit

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "掃除ルールの更新を確認・適用する（消す対象が増える変更は承認が必要です）")

    @OptionGroup var options: GlobalOptions
    @Flag(name: .long, help: "確認だけ行い、適用しない") var check = false
    @Flag(name: .long, help: "承認待ちの更新を適用する") var apply = false
    @Flag(name: .long, help: "確認プロンプトを省略する") var yes = false
    @Flag(name: .long, help: "1 世代前のカタログへ戻す") var rollback = false
    @Flag(name: .long, help: "自動更新を無効にする（以後は通信しません）") var off = false
    @Flag(name: .long, help: "自動更新を有効にする") var on = false

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func run() async throws {
        let env = DiscleanEnvironment()
        var config = Config.load(env: env)
        let out = Output(env: env)
        let audit = AuditLog(dir: env.auditDir)
        var state = UpdateState.load(env: env)

        if off || on {
            config.autoUpdate = on
            try? config.save(env: env)
            let message =
                on
                ? (out.japanese ? "自動更新を有効にしました。" : "auto-update enabled.")
                : (out.japanese ? "自動更新を無効にしました。以後は通信しません。" : "auto-update disabled; no network access from now on.")
            if options.json {
                JSONOut.emit(["command": "update", "autoUpdate": config.autoUpdate])
            } else {
                out.print(message)
            }
            return
        }

        let updater = Updater(env: env, config: config, audit: audit)

        if rollback {
            guard let version = try updater.rollback(state: &state) else {
                throw fail(.argumentError, "update: no previous catalog to roll back to")
            }
            state.save(env: env)
            if options.json {
                JSONOut.emit(["command": "update", "rolledBackTo": version])
            } else {
                out.print(out.japanese ? "カタログ \(version) に戻しました。" : "rolled back to catalog \(version).")
            }
            return
        }

        // 承認済みの適用だけを行う場合は通信しない。
        if apply, let staged = state.stagedCatalogVersion, !check {
            let store = CatalogStore(env: env)
            let manifest = store.stagedManifest(version: staged)
            let current =
                store.activeRules().isEmpty
                ? RuleCatalogLoader(env: env, config: config).load().rules
                : store.activeRules()
            let diff = CatalogDiffer.diff(
                current: current, next: store.stagedRules(version: staged),
                revocations: manifest?.revocations ?? [])
            if !yes && isatty(STDIN_FILENO) == 1 {
                UpdateRenderer(out: out).renderDiff(diff: diff, version: staged, env: env)
                out.print(out.japanese ? "この更新を適用しますか？ yes と入力してください: " : "type yes to apply: ")
                guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
                    out.print(out.japanese ? "適用しませんでした。" : "not applied.")
                    return
                }
            } else if !yes {
                throw fail(.argumentError, "update: --yes is required in non-interactive mode")
            }
            try updater.apply(version: staged, manifest: manifest, state: &state)
            state.save(env: env)
            if options.json {
                JSONOut.emit(["command": "update", "applied": true, "catalog": ["applied": staged]])
            } else {
                out.print(
                    out.styled(
                        out.japanese ? "カタログ \(staged) を適用しました。" : "applied catalog \(staged).", .green))
            }
            return
        }

        guard config.autoUpdate || check || apply else {
            if options.json {
                JSONOut.emit(["command": "update", "autoUpdate": false])
            } else {
                out.print(
                    out.japanese
                        ? "自動更新は無効です（disclean update --on で有効にできます）。"
                        : "auto-update is disabled (enable with `disclean update --on`).")
            }
            return
        }

        let outcome = await updater.check(state: &state, timeout: 60)
        state.save(env: env)

        if options.json {
            JSONOut.emit(UpdateRenderer.json(outcome: outcome, state: state))
        } else {
            UpdateRenderer(out: out).render(outcome: outcome, state: state, env: env)
        }

        if let failure = outcome.failure {
            out.warn("update: rejected (\(failure.rawValue))")
            throw fail(.updateVerificationFailed)
        }

        // 承認が要る差分があり、--apply が指定されていれば、この場で承認を求める。
        if outcome.requiresApproval && apply, let staged = state.stagedCatalogVersion {
            if !yes {
                guard isatty(STDIN_FILENO) == 1 else {
                    throw fail(.argumentError, "update: --yes is required in non-interactive mode")
                }
                out.print(out.japanese ? "この更新を適用しますか？ yes と入力してください: " : "type yes to apply: ")
                guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
                    out.print(out.japanese ? "適用しませんでした。" : "not applied.")
                    return
                }
            }
            let store = CatalogStore(env: env)
            try updater.apply(version: staged, manifest: store.stagedManifest(version: staged), state: &state)
            state.save(env: env)
            out.print(
                out.styled(
                    out.japanese ? "カタログ \(staged) を適用しました。" : "applied catalog \(staged).", .green))
        }
    }
}
