import Foundation

/// ルールが対象とする実際のパスを決める。
///
/// スキャンと実行が必ず同じ結果を使うよう、解決の手順をここ 1 箇所に置く。
/// 別々に解決すると、見せた場所と動かす場所がずれる。
public enum RulePaths {
    /// 解決したパス。ツールに聞く場合は実行を伴うため、結果を持ち回れるようにする。
    public struct Resolved: Sendable, Equatable {
        public let paths: [String]
        /// ツールに聞いたが答えが得られなかった（未導入・エラー）。
        public let toolUnavailable: Bool
        /// ツールが答えた場所が、触ってよい範囲の外だった。
        public let rejected: [String]
        /// ツールに聞けなかったので、ルールに書かれた既定の場所を使った。
        public let usedFallback: Bool
        /// 場所が多すぎて、途中で打ち切った（見せている量は実際より少ない）。
        public let truncated: Bool

        public init(
            paths: [String], toolUnavailable: Bool, rejected: [String], usedFallback: Bool = false,
            truncated: Bool = false
        ) {
            self.paths = paths
            self.toolUnavailable = toolUnavailable
            self.rejected = rejected
            self.usedFallback = usedFallback
            self.truncated = truncated
        }
    }

    /// - Parameter guardian: ツールが答えた場所を検証する。答えを無条件には信じない。
    public static func resolve(
        _ rule: Rule, home: String, guardian: PathGuard, timeoutSeconds: Int = 10
    ) -> Resolved {
        let declared = expandDeclared(rule.paths ?? [], home: home, guardian: guardian)
        let listed = declared.paths
        guard let pathsFrom = rule.pathsFrom else {
            return Resolved(
                paths: listed, toolUnavailable: false, rejected: declared.rejected,
                truncated: declared.truncated)
        }

        // ツールが答えられないことがある（npm 10 は `config get cache` を拒む）。
        // その場合だけ、ルールに書かれた既定の場所に実体があれば使う。
        func fallback(toolUnavailable: Bool, rejected: [String]) -> Resolved {
            let usable = listed.filter { guardian.validateRulePath($0) == nil && exists($0) }
            guard !usable.isEmpty else {
                return Resolved(paths: [], toolUnavailable: toolUnavailable, rejected: rejected)
            }
            return Resolved(
                paths: usable, toolUnavailable: false, rejected: rejected, usedFallback: true)
        }

        let result = CommandRunner.run(pathsFrom.command, timeoutSeconds: timeoutSeconds)
        guard result.succeeded else {
            return fallback(toolUnavailable: true, rejected: [])
        }
        let head =
            result.standardOutput
            .split(separator: "\n").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let base = Expand.tilde(head, home: home)
        guard base.hasPrefix("/") else {
            return fallback(toolUnavailable: true, rejected: [])
        }

        let targets =
            pathsFrom.subpaths.isEmpty
            ? [base]
            : pathsFrom.subpaths.map { base + "/" + $0 }

        // ツールの答えをそのままは使わない。同梱ルールと同じ規則で必ず検証する。
        var accepted: [String] = []
        var rejected: [String] = []
        for target in targets.map({ PathGuard.normalize($0) }) {
            if guardian.validateRulePath(target) == nil {
                accepted.append(target)
            } else {
                rejected.append(target)
            }
        }
        if accepted.isEmpty && !rejected.isEmpty {
            return fallback(toolUnavailable: false, rejected: rejected)
        }
        return Resolved(paths: accepted, toolUnavailable: false, rejected: rejected)
    }

    /// ルールに書かれた場所を実際のパスに広げる。
    ///
    /// ひな形（`*` を含む）は 1 階層ずつ広げ、**広げた先も同梱ルールと同じ規則で検証する**。
    /// 広げた結果を無条件に信じると、ひな形の書き方ひとつで範囲外へ出られてしまう。
    /// ルールに書かれた場所を広げた結果。
    private struct Declared {
        var paths: [String] = []
        var rejected: [String] = []
        var truncated = false
    }

    private static func expandDeclared(
        _ patterns: [String], home: String, guardian: PathGuard
    ) -> Declared {
        var declared = Declared()
        for pattern in patterns {
            let expanded = PathGuard.normalize(Expand.tilde(pattern, home: home))
            guard PathPattern.hasWildcard(expanded) else {
                // 決め打ちの場所は、実物が無くても「見つかりません」と言えるよう素通しする。
                declared.paths.append(expanded)
                continue
            }
            let expansion = PathPattern.expandDetailed(expanded)
            declared.truncated = declared.truncated || expansion.truncated
            for match in expansion.paths {
                if guardian.validateRulePath(match) == nil {
                    declared.paths.append(match)
                } else {
                    declared.rejected.append(match)
                }
            }
        }
        return declared
    }

    private static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }
}
