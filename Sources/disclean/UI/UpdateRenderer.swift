import Foundation
import DiscleanKit

/// S-31 更新の状態と差分。
struct UpdateRenderer {
    let out: Output

    func render(outcome: UpdateCheckOutcome, state: UpdateState, env: DiscleanEnvironment) {
        if let networkError = outcome.networkError {
            out.print(
                out.styled(
                    out.japanese
                        ? "更新を確認できませんでした（オフラインかもしれません）。掃除の機能はそのまま使えます。"
                        : "could not check for updates (possibly offline). Everything else works as usual.",
                    .dim))
            if ProcessInfo.processInfo.environment["DISCLEAN_VERBOSE"] != nil {
                out.warn("update: \(networkError)")
            }
            return
        }
        if let failure = outcome.failure {
            out.print(
                out.styled(
                    out.japanese
                        ? "受け取った更新を適用しませんでした（理由: \(failure.rawValue)）。今のルールをそのまま使います。"
                        : "the received update was NOT applied (reason: \(failure.rawValue)). Keeping current rules.",
                    .red))
            return
        }

        out.print(
            out.japanese
                ? "適用中のカタログ: \(outcome.appliedVersion)"
                : "applied catalog: \(outcome.appliedVersion)")
        if let available = outcome.availableVersion, available > outcome.appliedVersion {
            out.print(
                out.japanese
                    ? "配信中のカタログ: \(available)"
                    : "available catalog: \(available)")
        }

        if outcome.autoApplied {
            out.print(
                out.styled(
                    out.japanese
                        ? "消す対象が減る変更だけだったため、自動で適用しました。"
                        : "applied automatically (the changes only shrink what gets deleted).",
                    .green))
            renderShrinking(outcome.diff)
        } else if outcome.requiresApproval, let staged = state.stagedCatalogVersion {
            renderDiff(diff: outcome.diff, version: staged, env: env)
            out.print(
                out.styled(
                    out.japanese
                        ? "適用するには: disclean update --apply"
                        : "to apply: disclean update --apply",
                    .cyan))
        } else if outcome.availableVersion == nil || outcome.availableVersion == outcome.appliedVersion {
            out.print(out.japanese ? "更新はありません。" : "no updates.")
        }

        if let appVersion = outcome.appVersion, appVersion != DiscleanVersion.current {
            out.print()
            out.print(
                out.japanese
                    ? "本体の新しい版があります: \(appVersion)（今は \(DiscleanVersion.current)）"
                    : "a newer disclean is available: \(appVersion) (current \(DiscleanVersion.current))")
            switch outcome.installMethod {
            case .brew:
                out.print("  brew upgrade disclean")
            case .app, .manual:
                out.print(
                    out.japanese
                        ? "  https://github.com/suzuki-junya108/disclean/releases から入れ替えられます"
                        : "  download from https://github.com/suzuki-junya108/disclean/releases")
            }
            out.print(
                out.styled(
                    out.japanese
                        ? "  ディスクリンは本体を自動で入れ替えません。"
                        : "  disclean never replaces itself automatically.",
                    .dim))
        }

        for warning in outcome.warnings {
            out.print(out.styled("! " + warning, .yellow))
        }
    }

    /// 拡大差分を最上部・装飾なしで見せる（何が新しく消えるようになるか）。
    func renderDiff(diff: CatalogDiff, version: Int, env: DiscleanEnvironment) {
        out.print()
        out.print(
            out.styled(
                out.japanese ? "カタログ \(version) の変更点" : "changes in catalog \(version)", .bold))
        if !diff.expanding.isEmpty {
            out.print()
            out.print(
                out.japanese
                    ? "承認が必要な変更（消す対象が増えます）:"
                    : "changes that need your approval (they add things to delete):")
            for entry in diff.expanding {
                out.print("  \(entry.ruleId): \(describe(entry))")
                for path in entry.newPaths {
                    let expanded = Expand.tilde(path, home: env.home)
                    let size = measure(expanded)
                    out.print("    + \(path)\(size)")
                }
            }
            out.print()
            out.print(
                out.japanese
                    ? "承認するまで、これらは消える対象になりません。"
                    : "none of these become deletable until you approve.")
        }
        renderShrinking(diff)
        if !diff.neutral.isEmpty {
            out.print(
                out.styled(
                    out.japanese ? "文言だけの変更 \(diff.neutral.count) 件" : "\(diff.neutral.count) text-only change(s)",
                    .dim))
        }
    }

    private func renderShrinking(_ diff: CatalogDiff) {
        guard !diff.shrinking.isEmpty else { return }
        out.print(
            out.styled(
                out.japanese
                    ? "消す対象が減る変更 \(diff.shrinking.count) 件（自動で反映されます）:"
                    : "\(diff.shrinking.count) change(s) that shrink what gets deleted (applied automatically):",
                .dim))
        for entry in diff.shrinking.prefix(20) {
            out.print(out.styled("  \(entry.ruleId): \(describe(entry))", .dim))
        }
    }

    private func measure(_ path: String) -> String {
        var st = stat()
        guard lstat(path, &st) == 0 else { return out.japanese ? "（この Mac には存在しません）" : " (not present)" }
        let measurement = DirectoryMeter.measure(path: path)
        return "  \(Output.bytes(measurement.bytes))"
    }

    private func describe(_ entry: DiffEntry) -> String {
        let base: String
        switch entry.change {
        case .ruleAdded: base = out.japanese ? "新しいルールが追加されました" : "new rule added"
        case .ruleRemoved: base = out.japanese ? "ルールが削除されました" : "rule removed"
        case .pathAdded: base = out.japanese ? "対象の場所が追加されました" : "path added"
        case .pathRemoved: base = out.japanese ? "対象の場所が減りました" : "path removed"
        case .tierRaised: base = out.japanese ? "既定で選ばれる側に変わりました" : "tier raised"
        case .tierLowered: base = out.japanese ? "既定では選ばれない側に変わりました" : "tier lowered"
        case .commandChanged: base = out.japanese ? "実行するコマンドが変わりました" : "command changed"
        case .ageRelaxed: base = out.japanese ? "対象になるまでの日数が短くなりました" : "minimum age relaxed"
        case .ageTightened: base = out.japanese ? "対象になるまでの日数が長くなりました" : "minimum age tightened"
        case .osScopeWidened: base = out.japanese ? "対応する OS の範囲が広がりました" : "OS range widened"
        case .osScopeNarrowed: base = out.japanese ? "対応する OS の範囲が狭まりました" : "OS range narrowed"
        case .revoked: base = out.japanese ? "配信元により無効化されました" : "revoked by the publisher"
        case .textChanged: base = out.japanese ? "説明文が更新されました" : "text updated"
        }
        if let before = entry.before, let after = entry.after { return "\(base)（\(before) → \(after)）" }
        if let after = entry.after { return "\(base)（\(after)）" }
        return base
    }

    static func json(outcome: UpdateCheckOutcome, state: UpdateState) -> [String: Any] {
        func entries(_ list: [DiffEntry]) -> [[String: Any]] {
            list.map { ["ruleId": $0.ruleId, "change": $0.change.rawValue, "newPaths": $0.newPaths] }
        }
        var payload: [String: Any] = [
            "command": "update",
            "catalog": [
                "applied": outcome.appliedVersion,
                "available": jsonOrNull(outcome.availableVersion),
                "publishedAt": jsonOrNull(outcome.publishedAt.map(JSONIO.string(from:))),
                "expiresAt": jsonOrNull(outcome.expiresAt.map(JSONIO.string(from:))),
                "staged": jsonOrNull(state.stagedCatalogVersion),
            ],
            "diff": [
                "expanding": entries(outcome.diff.expanding),
                "shrinking": entries(outcome.diff.shrinking),
                "neutral": entries(outcome.diff.neutral),
            ],
            "app": [
                "current": DiscleanVersion.current,
                "latest": jsonOrNull(outcome.appVersion),
                "installMethod": outcome.installMethod.rawValue,
            ],
            "applied": outcome.autoApplied,
            "requiresApproval": outcome.requiresApproval,
            "warnings": outcome.warnings,
        ]
        var errors: [[String: Any]] = []
        if let failure = outcome.failure { errors.append(["reason": failure.rawValue]) }
        if let networkError = outcome.networkError { errors.append(["reason": "network", "detail": networkError]) }
        payload["errors"] = errors
        return payload
    }
}
