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

        public init(
            paths: [String], toolUnavailable: Bool, rejected: [String], usedFallback: Bool = false
        ) {
            self.paths = paths
            self.toolUnavailable = toolUnavailable
            self.rejected = rejected
            self.usedFallback = usedFallback
        }
    }

    /// - Parameter guardian: ツールが答えた場所を検証する。答えを無条件には信じない。
    public static func resolve(
        _ rule: Rule, home: String, guardian: PathGuard, timeoutSeconds: Int = 10
    ) -> Resolved {
        let listed = (rule.paths ?? []).map { PathGuard.normalize(Expand.tilde($0, home: home)) }
        guard let pathsFrom = rule.pathsFrom else {
            return Resolved(paths: listed, toolUnavailable: false, rejected: [])
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

    private static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }
}
